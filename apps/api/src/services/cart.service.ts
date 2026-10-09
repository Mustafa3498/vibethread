import { CartStatus, prisma, ProductStatus, ReservationStatus, type Prisma } from '@vibethread/database';
import { SOCKET_EVENTS, SOCKET_ROOMS } from '@vibethread/shared';
import { Errors } from '../lib/errors';
import { FREE_SHIPPING_OVER, MAX_QTY_PER_LINE, round2, shippingFeeFor, unitPriceOf } from '../lib/pricing';
import { emitToRoom } from '../realtime/emitters';
import * as inventory from './inventory.service';

/**
 * Cart rules
 *  - One ACTIVE cart per user (created on first use). Guests come later.
 *  - Adding to the cart does NOT hold stock (abandoned carts must not lock units).
 *    Stock is held at checkout (see order.service.startCheckout).
 *  - Any cart change drops an existing checkout hold, so a stale hold can never
 *    cover different quantities than the cart now contains.
 *  - Every change is pushed to the user's other devices (`cart:sync`).
 */

export const cartInclude = {
  items: {
    orderBy: { addedAt: 'asc' },
    include: {
      variant: {
        include: {
          inventory: true,
          product: { include: { images: { orderBy: { sortOrder: 'asc' } } } },
        },
      },
    },
  },
} satisfies Prisma.CartInclude;

export type FullCart = Prisma.CartGetPayload<{ include: typeof cartInclude }>;
type FullItem = FullCart['items'][number];

export type CartIssue = 'UNAVAILABLE' | 'OUT_OF_STOCK' | 'EXCEEDS_STOCK';

// ───────────────────────── reads ─────────────────────────

export async function getActiveCart(userId: string): Promise<FullCart> {
  const existing = await prisma.cart.findFirst({
    where: { userId, status: CartStatus.ACTIVE },
    orderBy: { updatedAt: 'desc' },
    include: cartInclude,
  });
  if (existing) return existing;
  return prisma.cart.create({ data: { userId }, include: cartInclude });
}

/** Live (not yet expired) stock holds of one cart. */
export async function activeHolds(cartId: string) {
  return prisma.stockReservation.findMany({
    where: { cartId, status: ReservationStatus.ACTIVE, expiresAt: { gt: new Date() } },
    select: { variantId: true, quantity: true, expiresAt: true },
  });
}

export function toCartLine(item: FullItem, ownHeld: number) {
  const v = item.variant;
  const p = v.product;

  // Units this cart already holds are counted as reserved in the inventory row,
  // so add them back: the shopper's own hold must not make their cart look short.
  const free = v.inventory ? Math.max(v.inventory.quantity - v.inventory.reserved, 0) : 0;
  const available = free + ownHeld;
  const threshold = v.inventory?.lowStockThreshold ?? 5;

  const sellable = v.isActive && p.status === ProductStatus.ACTIVE;
  let issue: CartIssue | null = null;
  if (!sellable) issue = 'UNAVAILABLE';
  else if (available === 0) issue = 'OUT_OF_STOCK';
  else if (item.quantity > available) issue = 'EXCEEDS_STOCK';

  const unitPrice = unitPriceOf(p, v);
  const colorKey = v.color.toLowerCase();
  const image =
    p.images.find((i) => i.color?.toLowerCase() === colorKey) ??
    p.images.find((i) => !i.color) ??
    p.images[0];

  return {
    id: item.id,
    variantId: v.id,
    productId: p.id,
    slug: p.slug,
    name: p.name,
    sku: v.sku,
    color: v.color,
    colorHex: v.colorHex,
    size: v.size,
    imageUrl: image?.url ?? null,
    unitPrice,
    quantity: item.quantity,
    lineTotal: round2(unitPrice * item.quantity),
    available,
    maxQuantity: Math.min(available, MAX_QTY_PER_LINE),
    lowStock: available > 0 && available <= threshold,
    issue,
  };
}

export function toCartPayload(
  cart: FullCart,
  holds: { variantId: string; quantity: number; expiresAt: Date }[],
) {
  const heldBy = new Map<string, number>();
  for (const h of holds) heldBy.set(h.variantId, (heldBy.get(h.variantId) ?? 0) + h.quantity);

  const items = cart.items.map((i) => toCartLine(i, heldBy.get(i.variantId) ?? 0));
  const subtotal = round2(items.reduce((s, l) => s + (l.issue === 'UNAVAILABLE' ? 0 : l.lineTotal), 0));
  const shippingFee = shippingFeeFor(subtotal);
  const expiresAt = holds.length ? new Date(Math.min(...holds.map((h) => h.expiresAt.getTime()))) : null;

  return {
    id: cart.id,
    items,
    itemCount: items.reduce((s, l) => s + l.quantity, 0),
    subtotal,
    shippingFee,
    total: round2(subtotal + shippingFee),
    freeShippingThreshold: FREE_SHIPPING_OVER,
    amountToFreeShipping: subtotal > 0 && subtotal < FREE_SHIPPING_OVER ? round2(FREE_SHIPPING_OVER - subtotal) : 0,
    hold: expiresAt ? { expiresAt: expiresAt.toISOString() } : null,
    hasIssues: items.some((l) => l.issue !== null),
  };
}

export async function getCartPayload(userId: string) {
  const cart = await getActiveCart(userId);
  return toCartPayload(cart, await activeHolds(cart.id));
}

/** Returns the fresh cart AND pushes it to the user's other devices. */
export async function syncCart(userId: string) {
  const payload = await getCartPayload(userId);
  emitToRoom(SOCKET_ROOMS.user(userId), SOCKET_EVENTS.CART_SYNC, payload);
  return payload;
}

// ───────────────────────── helpers ─────────────────────────

async function loadSellableVariant(variantId: string) {
  const variant = await prisma.productVariant.findUnique({
    where: { id: variantId },
    include: { inventory: true, product: true },
  });
  if (!variant || !variant.isActive || variant.product.status !== ProductStatus.ACTIVE) {
    throw Errors.notFound('This item is not available');
  }
  return variant;
}
type SellableVariant = Awaited<ReturnType<typeof loadSellableVariant>>;

async function ensureAvailable(cartId: string, variant: SellableVariant, wanted: number) {
  const held = (await activeHolds(cartId))
    .filter((h) => h.variantId === variant.id)
    .reduce((s, h) => s + h.quantity, 0);
  const free = variant.inventory ? Math.max(variant.inventory.quantity - variant.inventory.reserved, 0) : 0;
  const available = free + held;

  if (available <= 0) throw Errors.conflict(`${variant.product.name} (${variant.size}) is sold out`);
  if (wanted > available) throw Errors.conflict(`Only ${available} left in ${variant.size}`);
}

/** Cart content changed: bump updatedAt (abandonment tracking) and drop any checkout hold. */
async function cartChanged(cartId: string) {
  await prisma.cart.update({ where: { id: cartId }, data: { status: CartStatus.ACTIVE } });
  await inventory.releaseReservations({ cartId });
}

// ───────────────────────── mutations ─────────────────────────

export async function addItem(userId: string, variantId: string, quantity: number) {
  const variant = await loadSellableVariant(variantId);
  const cart = await getActiveCart(userId);

  const existing = cart.items.find((i) => i.variantId === variantId);
  const wanted = Math.min((existing?.quantity ?? 0) + quantity, MAX_QTY_PER_LINE);
  await ensureAvailable(cart.id, variant, wanted);

  await prisma.cartItem.upsert({
    where: { cartId_variantId: { cartId: cart.id, variantId } },
    create: { cartId: cart.id, variantId, quantity: wanted },
    update: { quantity: wanted },
  });
  await cartChanged(cart.id);
  return syncCart(userId);
}

/** quantity 0 removes the line. */
export async function setQuantity(userId: string, variantId: string, quantity: number) {
  if (quantity === 0) return removeItem(userId, variantId);

  const cart = await getActiveCart(userId);
  if (!cart.items.some((i) => i.variantId === variantId)) throw Errors.notFound('Item is not in your cart');

  const variant = await loadSellableVariant(variantId);
  await ensureAvailable(cart.id, variant, quantity);

  await prisma.cartItem.update({
    where: { cartId_variantId: { cartId: cart.id, variantId } },
    data: { quantity },
  });
  await cartChanged(cart.id);
  return syncCart(userId);
}

export async function removeItem(userId: string, variantId: string) {
  const cart = await getActiveCart(userId);
  await prisma.cartItem.deleteMany({ where: { cartId: cart.id, variantId } });
  await cartChanged(cart.id);
  return syncCart(userId);
}

export async function clearCart(userId: string) {
  const cart = await getActiveCart(userId);
  await prisma.cartItem.deleteMany({ where: { cartId: cart.id } });
  await cartChanged(cart.id);
  return syncCart(userId);
}
