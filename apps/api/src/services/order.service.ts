import { randomBytes } from 'node:crypto';
import {
  CartStatus,
  OrderStatus,
  PaymentStatus,
  Prisma,
  prisma,
  ProductStatus,
} from '@vibethread/database';
import { SOCKET_ROOMS } from '@vibethread/shared';
import { Errors } from '../lib/errors';
import {
  estimatedDeliveryFor,
  HOLD_MINUTES,
  round2,
  shippingFeeFor,
  toNum,
  unitPriceOf,
} from '../lib/pricing';
import { paginated } from '../lib/serialize';
import { emitToRoom } from '../realtime/emitters';
import { ORDER_EVENTS } from '../realtime/order-events';
import type { MyOrdersQuery, PlaceOrderInput, StaffOrdersQuery, StaffStatusInput } from '../schemas/shop';
import { activeHolds, getActiveCart, syncCart, type FullCart } from './cart.service';
import * as inventory from './inventory.service';

/**
 * Order flow (cash on delivery)
 *   1. startCheckout  -> stock is HELD for HOLD_MINUTES (reservation)
 *   2. placeOrder     -> order rows are written, the hold is COMMITTED (units are sold),
 *                        cart becomes CONVERTED and a new empty cart starts
 *   3. staff move the order: PENDING_PAYMENT (= "Placed" for COD) -> PACKING -> READY_TO_SHIP
 *                        -> SHIPPED -> DELIVERED (COD is marked PAID on delivery)
 *   4. cancel / return puts the units back on the shelf (ledger entry RETURN)
 */

// ───────────────────────── serializers ─────────────────────────

const orderInclude = {
  address: true,
  items: {
    include: {
      variant: {
        select: {
          product: { select: { slug: true, images: { orderBy: { sortOrder: 'asc' }, take: 1 } } },
        },
      },
    },
  },
} satisfies Prisma.OrderInclude;
type FullOrder = Prisma.OrderGetPayload<{ include: typeof orderInclude }>;

const staffOrderInclude = {
  ...orderInclude,
  user: { select: { id: true, fullName: true, email: true, phone: true } },
} satisfies Prisma.OrderInclude;
type StaffOrder = Prisma.OrderGetPayload<{ include: typeof staffOrderInclude }>;

const STATUS_LABELS: Record<OrderStatus, string> = {
  PENDING_PAYMENT: 'Placed',
  PAID: 'Paid',
  PACKING: 'Packing',
  READY_TO_SHIP: 'Ready to ship',
  SHIPPED: 'Shipped',
  DELIVERED: 'Delivered',
  CANCELLED: 'Cancelled',
  RETURNED: 'Returned',
};

function statusLabel(o: { status: OrderStatus; paymentMethod: string | null }) {
  if (o.status === OrderStatus.PENDING_PAYMENT && o.paymentMethod && o.paymentMethod !== 'COD') {
    return 'Awaiting payment';
  }
  return STATUS_LABELS[o.status];
}

export function toOrderPayload(o: FullOrder) {
  return {
    id: o.id,
    orderNumber: o.orderNumber,
    status: o.status,
    statusLabel: statusLabel(o),
    paymentStatus: o.paymentStatus,
    paymentMethod: o.paymentMethod,
    subtotal: toNum(o.subtotal),
    shippingFee: toNum(o.shippingFee),
    discount: toNum(o.discount),
    total: toNum(o.total),
    estimatedDelivery: o.estimatedDelivery?.toISOString() ?? null,
    trackingNumber: o.trackingNumber,
    courier: o.courier,
    placedAt: o.placedAt.toISOString(),
    canCancel: CUSTOMER_CAN_CANCEL.includes(o.status),
    address: {
      id: o.address.id,
      label: o.address.label,
      line1: o.address.line1,
      line2: o.address.line2,
      city: o.address.city,
      state: o.address.state,
      postalCode: o.address.postalCode,
      country: o.address.country,
    },
    items: o.items.map((i) => ({
      id: i.id,
      variantId: i.variantId,
      productName: i.productName,
      sku: i.sku,
      color: i.color,
      size: i.size,
      unitPrice: toNum(i.unitPrice),
      quantity: i.quantity,
      lineTotal: round2(Number(i.unitPrice) * i.quantity),
      slug: i.variant.product.slug,
      imageUrl: i.variant.product.images[0]?.url ?? null,
    })),
  };
}

export function toStaffOrderPayload(o: StaffOrder) {
  return {
    ...toOrderPayload(o),
    customer: { id: o.user.id, fullName: o.user.fullName, email: o.user.email, phone: o.user.phone },
  };
}

// ───────────────────────── checkout (stock hold) ─────────────────────────

type Line = {
  variantId: string;
  productName: string;
  sku: string;
  color: string;
  size: string;
  quantity: number;
  unitPrice: number;
  unitCost: number | null;
};

/** Cart -> priced lines. Throws if something can no longer be sold. */
function linesOf(cart: FullCart): Line[] {
  if (cart.items.length === 0) throw Errors.badRequest('Your cart is empty');

  return cart.items.map((i) => {
    const v = i.variant;
    const p = v.product;
    if (!v.isActive || p.status !== ProductStatus.ACTIVE) {
      throw Errors.conflict(`${p.name} (${v.color}, ${v.size}) is no longer available. Remove it from your cart.`);
    }
    return {
      variantId: v.id,
      productName: p.name,
      sku: v.sku,
      color: v.color,
      size: v.size,
      quantity: i.quantity,
      unitPrice: unitPriceOf(p, v),
      unitCost: toNum(p.costPrice),
    };
  });
}

const covers = (holds: { variantId: string; quantity: number }[], lines: Line[]) =>
  lines.every(
    (l) =>
      holds.filter((h) => h.variantId === l.variantId).reduce((s, h) => s + h.quantity, 0) >= l.quantity,
  );

async function releaseQuietly(cartId: string) {
  try {
    await inventory.releaseReservations({ cartId });
  } catch (err) {
    console.error('[orders] releasing hold failed', err);
  }
}

/** Reserves every line for HOLD_MINUTES and verifies the hold really covers the cart. */
async function holdStock(cartId: string, lines: Line[]) {
  await inventory.releaseReservations({ cartId });
  await inventory.reserveStock({
    cartId,
    items: lines.map((l) => ({ variantId: l.variantId, quantity: l.quantity })),
    ttlMinutes: HOLD_MINUTES,
  });

  if (!covers(await activeHolds(cartId), lines)) {
    await releaseQuietly(cartId);
    throw Errors.conflict('Some items just sold out. Please review your cart.');
  }
}

export async function startCheckout(userId: string) {
  const cart = await getActiveCart(userId);
  const lines = linesOf(cart);

  await holdStock(cart.id, lines);

  const payload = await syncCart(userId);
  return { ...payload, holdMinutes: HOLD_MINUTES };
}

// ───────────────────────── place order ─────────────────────────

const newOrderNumber = () => `VT-${randomBytes(4).toString('hex').toUpperCase()}`;

async function loadOrder(id: string) {
  const order = await prisma.order.findUnique({ where: { id }, include: orderInclude });
  if (!order) throw Errors.notFound('Order not found');
  return order;
}

export async function placeOrder(userId: string, input: PlaceOrderInput) {
  const [user, address] = await Promise.all([
    prisma.user.findUnique({ where: { id: userId }, select: { id: true, phone: true, isActive: true } }),
    prisma.address.findFirst({ where: { id: input.addressId, userId } }),
  ]);
  if (!user || !user.isActive) throw Errors.unauthorized('Account not available');
  if (!address) throw Errors.badRequest('Choose a delivery address');

  const phone = input.phone ?? user.phone;
  if (!phone) throw Errors.badRequest('A phone number is required for delivery');
  if (input.phone && input.phone !== user.phone) {
    await prisma.user.update({ where: { id: userId }, data: { phone: input.phone } });
  }

  const cart = await getActiveCart(userId);
  const lines = linesOf(cart);

  // Reuse the checkout hold if it is still valid, otherwise try to take it again.
  if (!covers(await activeHolds(cart.id), lines)) await holdStock(cart.id, lines);

  const subtotal = round2(lines.reduce((s, l) => s + l.unitPrice * l.quantity, 0));
  const shippingFee = shippingFeeFor(subtotal);
  const total = round2(subtotal + shippingFee);

  let orderId: string | null = null;
  for (let attempt = 0; attempt < 3 && !orderId; attempt++) {
    try {
      const created = await prisma.$transaction(async (tx) => {
        const o = await tx.order.create({
          data: {
            orderNumber: newOrderNumber(),
            userId,
            cartId: cart.id,
            addressId: address.id,
            status: OrderStatus.PENDING_PAYMENT,
            paymentStatus: PaymentStatus.UNPAID,
            paymentMethod: input.paymentMethod,
            subtotal,
            shippingFee,
            discount: 0,
            total,
            estimatedDelivery: estimatedDeliveryFor(address.city),
            items: {
              create: lines.map((l) => ({
                variantId: l.variantId,
                productName: l.productName,
                sku: l.sku,
                color: l.color,
                size: l.size,
                unitPrice: l.unitPrice,
                unitCost: l.unitCost,
                quantity: l.quantity,
              })),
            },
          },
          select: { id: true },
        });
        await tx.cart.update({ where: { id: cart.id }, data: { status: CartStatus.CONVERTED } });
        return o;
      });
      orderId = created.id;
    } catch (err) {
      if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') {
        const target = String(err.meta?.target ?? '');
        if (target.includes('orderNumber')) continue; // random collision: try another number
        if (target.includes('cartId')) throw Errors.conflict('This order was already placed');
      }
      await releaseQuietly(cart.id);
      throw err;
    }
  }
  if (!orderId) {
    await releaseQuietly(cart.id);
    throw Errors.conflict('Could not create the order. Please try again.');
  }

  // The hold becomes a sale: quantity AND reserved both drop (live stock update goes out).
  try {
    const committed: unknown = await inventory.commitReservations({ cartId: cart.id, orderId });
    if (typeof committed === 'number' && committed < lines.length) {
      throw Errors.conflict('Could not confirm stock for your order. Please try again.');
    }
  } catch (err) {
    // Undo: the order never happened, and the cart can be used again.
    await prisma.order
      .update({ where: { id: orderId }, data: { status: OrderStatus.CANCELLED, cartId: null } })
      .catch(() => undefined);
    await prisma.cart
      .update({ where: { id: cart.id }, data: { status: CartStatus.ACTIVE } })
      .catch(() => undefined);
    await releaseQuietly(cart.id);
    throw err;
  }

  const order = await loadOrder(orderId);
  const payload = toOrderPayload(order);

  await syncCart(userId); // new empty cart on every device
  emitToRoom(SOCKET_ROOMS.user(userId), ORDER_EVENTS.UPDATED, summary(order));
  emitToRoom(SOCKET_ROOMS.STAFF, ORDER_EVENTS.NEW, { ...summary(order), total: payload.total });

  return payload;
}

const summary = (o: { id: string; orderNumber: string; status: OrderStatus; paymentMethod: string | null }) => ({
  id: o.id,
  orderNumber: o.orderNumber,
  status: o.status,
  statusLabel: statusLabel(o),
});

// ───────────────────────── customer reads / cancel ─────────────────────────

export async function listMyOrders(userId: string, q: MyOrdersQuery) {
  const where: Prisma.OrderWhereInput = { userId };
  const [total, rows] = await Promise.all([
    prisma.order.count({ where }),
    prisma.order.findMany({
      where,
      orderBy: { placedAt: 'desc' },
      skip: (q.page - 1) * q.pageSize,
      take: q.pageSize,
      include: orderInclude,
    }),
  ]);
  return paginated(rows.map(toOrderPayload), total, q.page, q.pageSize);
}

export async function getMyOrder(userId: string, id: string) {
  const order = await prisma.order.findFirst({ where: { id, userId }, include: orderInclude });
  if (!order) throw Errors.notFound('Order not found');
  return toOrderPayload(order);
}

/** Customers may cancel until the parcel is handed to the courier. */
const CUSTOMER_CAN_CANCEL: OrderStatus[] = [OrderStatus.PENDING_PAYMENT, OrderStatus.PACKING];

export async function cancelMyOrder(userId: string, id: string) {
  await moveOrder({
    id,
    userId,
    from: CUSTOMER_CAN_CANCEL,
    to: OrderStatus.CANCELLED,
    actorId: userId,
  });
  return getMyOrder(userId, id);
}

// ───────────────────────── staff (fulfillment queue) ─────────────────────────

const TRANSITIONS: Partial<Record<OrderStatus, OrderStatus[]>> = {
  PENDING_PAYMENT: [OrderStatus.PACKING, OrderStatus.CANCELLED],
  PAID: [OrderStatus.PACKING, OrderStatus.CANCELLED],
  PACKING: [OrderStatus.READY_TO_SHIP, OrderStatus.CANCELLED],
  READY_TO_SHIP: [OrderStatus.SHIPPED, OrderStatus.CANCELLED],
  SHIPPED: [OrderStatus.DELIVERED, OrderStatus.RETURNED],
  DELIVERED: [OrderStatus.RETURNED],
};

export async function listStaffOrders(q: StaffOrdersQuery) {
  const where: Prisma.OrderWhereInput = {};
  if (q.status) where.status = q.status;
  if (q.q) {
    where.OR = [
      { orderNumber: { contains: q.q, mode: 'insensitive' } },
      { user: { email: { contains: q.q, mode: 'insensitive' } } },
      { user: { fullName: { contains: q.q, mode: 'insensitive' } } },
    ];
  }

  const [total, rows] = await Promise.all([
    prisma.order.count({ where }),
    prisma.order.findMany({
      where,
      orderBy: { placedAt: 'desc' },
      skip: (q.page - 1) * q.pageSize,
      take: q.pageSize,
      include: staffOrderInclude,
    }),
  ]);
  return paginated(rows.map(toStaffOrderPayload), total, q.page, q.pageSize);
}

async function loadStaffOrder(id: string) {
  const order = await prisma.order.findUnique({ where: { id }, include: staffOrderInclude });
  if (!order) throw Errors.notFound('Order not found');
  return toStaffOrderPayload(order);
}

export const getStaffOrder = loadStaffOrder;

export async function updateOrderStatus(id: string, input: StaffStatusInput, actorId: string) {
  const current = await prisma.order.findUnique({
    where: { id },
    select: { id: true, status: true, userId: true, paymentMethod: true },
  });
  if (!current) throw Errors.notFound('Order not found');

  const allowed = TRANSITIONS[current.status] ?? [];
  if (!allowed.includes(input.status)) {
    throw Errors.badRequest(`An order that is ${current.status} cannot be moved to ${input.status}`);
  }

  const extra: Prisma.OrderUpdateManyMutationInput = {};
  if (input.status === OrderStatus.SHIPPED) {
    if (input.trackingNumber) extra.trackingNumber = input.trackingNumber;
    if (input.courier) extra.courier = input.courier;
  }
  if (input.status === OrderStatus.DELIVERED && current.paymentMethod === 'COD') {
    extra.paymentStatus = PaymentStatus.PAID; // cash collected by the courier
  }

  await moveOrder({
    id,
    from: [current.status],
    to: input.status,
    actorId,
    extra,
    restock: input.status === OrderStatus.CANCELLED || input.status === OrderStatus.RETURNED,
  });

  const updated = await loadStaffOrder(id);
  emitToRoom(SOCKET_ROOMS.user(current.userId), ORDER_EVENTS.UPDATED, summary(updated));
  emitToRoom(SOCKET_ROOMS.STAFF, ORDER_EVENTS.UPDATED, summary(updated));
  return updated;
}

// ───────────────────────── shared state change ─────────────────────────

/**
 * Guarded status change: only applies if the order is still in one of `from`
 * (so two staff members or a customer + staff cannot both win a race).
 * Cancelling or returning puts every unit back on the shelf.
 */
async function moveOrder(args: {
  id: string;
  userId?: string;
  from: OrderStatus[];
  to: OrderStatus;
  actorId: string;
  extra?: Prisma.OrderUpdateManyMutationInput;
  restock?: boolean;
}) {
  const restock = args.restock ?? args.to === OrderStatus.CANCELLED;
  const where: Prisma.OrderWhereInput = {
    id: args.id,
    status: { in: args.from },
    ...(args.userId ? { userId: args.userId } : {}),
  };

  const res = await prisma.order.updateMany({ where, data: { ...args.extra, status: args.to } });
  if (res.count === 0) {
    const exists = await prisma.order.findFirst({
      where: { id: args.id, ...(args.userId ? { userId: args.userId } : {}) },
      select: { id: true },
    });
    throw exists
      ? Errors.conflict('This order can no longer be changed')
      : Errors.notFound('Order not found');
  }

  if (restock) {
    const items = await prisma.orderItem.findMany({
      where: { orderId: args.id },
      select: { variantId: true, quantity: true },
    });
    for (const item of items) {
      await inventory.returnStock({
        variantId: item.variantId,
        quantity: item.quantity,
        orderId: args.id,
        actorId: args.actorId,
      });
    }
  }
}
