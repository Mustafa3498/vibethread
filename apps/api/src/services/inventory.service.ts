import { Prisma, prisma, ReservationStatus, StockMovementType } from '@vibethread/database';
import {
  SOCKET_EVENTS,
  SOCKET_ROOMS,
  type InventoryAlertPayload,
  type StockUpdatePublic,
  type StockUpdateStaff,
} from '@vibethread/shared';
import { AppError, Errors } from '../lib/errors';
import { emitToRoom } from '../realtime/emitters';
import type { InventoryListQuery, StockAdjustInput } from '../schemas/catalog';
import { paginated } from '../lib/serialize';

type Tx = Prisma.TransactionClient;

export const RESERVATION_TTL_MINUTES = 15;
export const FAST_MOVING_UNITS_24H = 10;

const NOW_UTC = Prisma.sql`(NOW() AT TIME ZONE 'UTC')`;

export interface StockLine {
  variantId: string;
  quantity: number;
}
interface Holder {
  cartId?: string;
  orderId?: string;
}

/*
 * Stock model
 *   quantity  = physical units on the shelf
 *   reserved  = units held for in-progress checkouts
 *   available = quantity - reserved   ← what customers see and can buy
 *
 * Every mutation below is a single guarded UPDATE (or row-locked read) so concurrent
 * buyers can never oversell, and the DB CHECK constraint is the last line of defense.
 */

// ───────────────────────── manual stock changes (staff) ─────────────────────────

export async function adjustStock(
  variantId: string,
  input: StockAdjustInput,
  actorId: string | null,
) {
  const result = await prisma.$transaction(async (tx) => {
    const rows = await tx.$queryRaw<{ quantity: number; reserved: number }[]>`
      SELECT quantity, reserved FROM "Inventory" WHERE "variantId" = ${variantId} FOR UPDATE`;
    const row = rows[0];
    if (!row) throw Errors.notFound('Variant not found');

    const target = input.setQuantity !== undefined ? input.setQuantity : row.quantity + input.delta!;
    const delta = target - row.quantity;

    if (target < 0) throw Errors.badRequest('Stock cannot go below 0');
    if (target < row.reserved) {
      throw Errors.conflict(
        `${row.reserved} unit(s) are held in active checkouts. Stock cannot go below that right now.`,
      );
    }
    if (delta === 0) return { quantity: row.quantity, reserved: row.reserved, delta: 0 };

    await tx.$executeRaw`
      UPDATE "Inventory" SET quantity = ${target}, "updatedAt" = ${NOW_UTC} WHERE "variantId" = ${variantId}`;
    await tx.stockMovement.create({
      data: {
        variantId,
        type:
          input.type ??
          (input.setQuantity === undefined && delta > 0
            ? StockMovementType.RESTOCK
            : StockMovementType.ADJUSTMENT),
        delta,
        reason: input.reason ?? (input.setQuantity !== undefined ? 'Manual stock count' : null),
        actorId,
      },
    });
    return { quantity: target, reserved: row.reserved, delta };
  });

  if (result.delta !== 0) await afterStockChange([variantId]);
  return { variantId, quantity: result.quantity, reserved: result.reserved, available: result.quantity - result.reserved, delta: result.delta };
}

// ───────────────────────── reservations (used by cart/checkout in Step 7) ─────────────────────────

export async function reserveStock(input: Holder & { items: StockLine[]; ttlMinutes?: number }) {
  if (!input.cartId && !input.orderId) throw Errors.badRequest('A reservation needs a cartId or orderId');
  const items = mergeLines(input.items);
  const expiresAt = new Date(Date.now() + (input.ttlMinutes ?? RESERVATION_TTL_MINUTES) * 60_000);

  const reservations = await prisma.$transaction(async (tx) => {
    const created = [];
    // sorted → consistent lock order → no deadlocks between concurrent checkouts
    for (const line of items) {
      const n = await tx.$executeRaw`
        UPDATE "Inventory" SET reserved = reserved + ${line.quantity}, "updatedAt" = ${NOW_UTC}
        WHERE "variantId" = ${line.variantId} AND quantity - reserved >= ${line.quantity}`;
      if (n === 0) {
        const inv = await tx.inventory.findUnique({ where: { variantId: line.variantId } });
        throw new AppError(409, 'INSUFFICIENT_STOCK', 'Not enough stock for one of the items', {
          variantId: line.variantId,
          requested: line.quantity,
          available: inv ? Math.max(inv.quantity - inv.reserved, 0) : 0,
        });
      }
      created.push(
        await tx.stockReservation.create({
          data: { variantId: line.variantId, cartId: input.cartId, orderId: input.orderId, quantity: line.quantity, expiresAt },
        }),
      );
      await tx.stockMovement.create({
        data: { variantId: line.variantId, type: StockMovementType.RESERVE, delta: line.quantity, reason: holderLabel(input) },
      });
    }
    return created;
  });

  await afterStockChange(items.map((i) => i.variantId));
  return reservations;
}

/** Frees active holds (cart emptied, checkout abandoned/cancelled). Returns how many were released. */
export async function releaseReservations(holder: Holder, status: 'RELEASED' | 'EXPIRED' = 'RELEASED') {
  requireHolder(holder);
  return settle({ status: ReservationStatus.ACTIVE, ...holderWhere(holder) }, status, null);
}

/** Payment succeeded: held units become a sale (quantity AND reserved both drop). */
export async function commitReservations(holder: Holder & { orderId: string }) {
  requireHolder(holder);
  return settle({ status: ReservationStatus.ACTIVE, ...holderWhere(holder) }, 'COMMITTED', holder.orderId);
}

/** Job: expire holds whose TTL passed. Safe to run on several instances (status claim is atomic). */
export async function expireStaleReservations(batch = 200) {
  return settle(
    { status: ReservationStatus.ACTIVE, expiresAt: { lt: new Date() } },
    'EXPIRED',
    null,
    batch,
  );
}

/** Customer returned goods → back on the shelf. */
export async function returnStock(input: { variantId: string; quantity: number; orderId?: string; actorId?: string }) {
  await prisma.$transaction(async (tx) => {
    const n = await tx.$executeRaw`
      UPDATE "Inventory" SET quantity = quantity + ${input.quantity}, "updatedAt" = ${NOW_UTC}
      WHERE "variantId" = ${input.variantId}`;
    if (n === 0) throw Errors.notFound('Variant not found');
    await tx.stockMovement.create({
      data: {
        variantId: input.variantId,
        type: StockMovementType.RETURN,
        delta: input.quantity,
        reason: input.orderId ? `Return for order ${input.orderId}` : 'Customer return',
        actorId: input.actorId ?? null,
      },
    });
  });
  await afterStockChange([input.variantId]);
}

// ───────────────────────── internals ─────────────────────────

async function settle(
  where: Prisma.StockReservationWhereInput,
  status: 'RELEASED' | 'EXPIRED' | 'COMMITTED',
  orderId: string | null,
  take?: number,
) {
  const touched = new Set<string>();
  let count = 0;

  await prisma.$transaction(async (tx) => {
    const rows = await tx.stockReservation.findMany({ where, take, orderBy: { createdAt: 'asc' } });
    for (const r of rows.sort((a, b) => a.variantId.localeCompare(b.variantId))) {
      // atomic claim: only one worker/request can move a reservation out of ACTIVE
      const claim = await tx.stockReservation.updateMany({
        where: { id: r.id, status: ReservationStatus.ACTIVE },
        data: { status, ...(orderId ? { orderId } : {}) },
      });
      if (claim.count === 0) continue;

      if (status === 'COMMITTED') {
        const n = await tx.$executeRaw`
          UPDATE "Inventory" SET quantity = quantity - ${r.quantity}, reserved = reserved - ${r.quantity}, "updatedAt" = ${NOW_UTC}
          WHERE "variantId" = ${r.variantId} AND quantity >= ${r.quantity} AND reserved >= ${r.quantity}`;
        if (n === 0) throw new AppError(500, 'INVENTORY_CORRUPT', `Cannot commit reservation ${r.id}`);
        await tx.stockMovement.create({
          data: { variantId: r.variantId, type: StockMovementType.SALE, delta: -r.quantity, reason: `Order ${orderId}` },
        });
      } else {
        await tx.$executeRaw`
          UPDATE "Inventory" SET reserved = GREATEST(reserved - ${r.quantity}, 0), "updatedAt" = ${NOW_UTC}
          WHERE "variantId" = ${r.variantId}`;
        await tx.stockMovement.create({
          data: {
            variantId: r.variantId,
            type: StockMovementType.RELEASE,
            delta: -r.quantity,
            reason: status === 'EXPIRED' ? 'Hold expired' : 'Hold released',
          },
        });
      }
      touched.add(r.variantId);
      count++;
    }
  }, { timeout: 20_000 });

  if (touched.size) await afterStockChange([...touched]);
  return count;
}

function mergeLines(lines: StockLine[]): StockLine[] {
  const m = new Map<string, number>();
  for (const l of lines) {
    if (!Number.isInteger(l.quantity) || l.quantity <= 0) throw Errors.badRequest('Quantities must be positive integers');
    m.set(l.variantId, (m.get(l.variantId) ?? 0) + l.quantity);
  }
  return [...m].map(([variantId, quantity]) => ({ variantId, quantity })).sort((a, b) => a.variantId.localeCompare(b.variantId));
}
const holderLabel = (h: Holder) => (h.orderId ? `Hold for order ${h.orderId}` : `Hold for cart ${h.cartId}`);
const requireHolder = (h: Holder) => {
  if (!h.cartId && !h.orderId) throw Errors.badRequest('cartId or orderId required');
};
const holderWhere = (h: Holder): Prisma.StockReservationWhereInput =>
  h.cartId && h.orderId ? { OR: [{ cartId: h.cartId }, { orderId: h.orderId }] } : h.cartId ? { cartId: h.cartId } : { orderId: h.orderId };

// ───────────────────────── post-change hook: alerts + live broadcast ─────────────────────────

/** Best-effort: never fails the stock operation that triggered it. */
export async function afterStockChange(variantIds: string[]) {
  const ids = [...new Set(variantIds)];
  try {
    await evaluateAlerts(ids);
    await broadcastStock(ids);
  } catch (err) {
    console.error('[inventory] post-change hook failed:', err);
  }
}

const variantWithStock = {
  select: {
    id: true,
    sku: true,
    color: true,
    size: true,
    productId: true,
    product: { select: { name: true } },
    inventory: { select: { quantity: true, reserved: true, lowStockThreshold: true } },
  },
} satisfies Prisma.ProductVariantDefaultArgs;

async function broadcastStock(ids: string[]) {
  const variants = await prisma.productVariant.findMany({ where: { id: { in: ids } }, ...variantWithStock });
  for (const v of variants) {
    const inv = v.inventory;
    if (!inv) continue;
    const available = Math.max(inv.quantity - inv.reserved, 0);
    const lowStock = available > 0 && available <= inv.lowStockThreshold;
    const pub: StockUpdatePublic = { productId: v.productId, variantId: v.id, available, lowStock };
    const staff: StockUpdateStaff = {
      ...pub,
      sku: v.sku,
      color: v.color,
      size: v.size,
      quantity: inv.quantity,
      reserved: inv.reserved,
      lowStockThreshold: inv.lowStockThreshold,
    };
    emitToRoom(SOCKET_ROOMS.product(v.productId), SOCKET_EVENTS.STOCK_UPDATED, pub);
    emitToRoom(SOCKET_ROOMS.STAFF, SOCKET_EVENTS.STOCK_UPDATED, staff);
  }
}

async function evaluateAlerts(ids: string[]) {
  const variants = await prisma.productVariant.findMany({ where: { id: { in: ids } }, ...variantWithStock });
  const since = new Date(Date.now() - 24 * 3600 * 1000);
  const sold = await prisma.stockMovement.groupBy({
    by: ['variantId'],
    where: { variantId: { in: ids }, type: StockMovementType.SALE, createdAt: { gte: since } },
    _sum: { delta: true },
  });
  const sold24h = new Map(sold.map((s) => [s.variantId, -(s._sum.delta ?? 0)]));

  for (const v of variants) {
    const inv = v.inventory;
    if (!inv) continue;
    const available = Math.max(inv.quantity - inv.reserved, 0);
    const label = `${v.product.name} — ${v.color} / ${v.size} (${v.sku})`;

    if (available === 0) {
      await raiseAlert(v, 'OUT_OF_STOCK', `${label} is out of stock`);
    } else if (available <= inv.lowStockThreshold) {
      await raiseAlert(v, 'LOW_STOCK', `${label}: only ${available} left`);
    } else {
      // stock recovered → auto-resolve open stock alerts
      await prisma.inventoryAlert.updateMany({
        where: { variantId: v.id, isRead: false, type: { in: ['LOW_STOCK', 'OUT_OF_STOCK'] } },
        data: { isRead: true },
      });
    }
    const fast = sold24h.get(v.id) ?? 0;
    if (fast >= FAST_MOVING_UNITS_24H) {
      await raiseAlert(v, 'FAST_MOVING', `${label}: ${fast} sold in the last 24h — consider restocking`);
    }
  }
}

async function raiseAlert(
  v: { id: string; sku: string; productId: string; product: { name: string } },
  type: 'LOW_STOCK' | 'OUT_OF_STOCK' | 'FAST_MOVING',
  message: string,
) {
  const open = await prisma.inventoryAlert.findFirst({ where: { variantId: v.id, type, isRead: false } });
  if (open) return; // one open alert per variant+type — no spam
  // escalation: low-stock alert is superseded by out-of-stock
  if (type === 'OUT_OF_STOCK') {
    await prisma.inventoryAlert.updateMany({ where: { variantId: v.id, type: 'LOW_STOCK', isRead: false }, data: { isRead: true } });
  }
  const alert = await prisma.inventoryAlert.create({ data: { variantId: v.id, type, message } });
  const payload: InventoryAlertPayload = {
    id: alert.id,
    type,
    variantId: v.id,
    productId: v.productId,
    productName: v.product.name,
    sku: v.sku,
    message,
    createdAt: alert.createdAt.toISOString(),
  };
  emitToRoom(SOCKET_ROOMS.STAFF, SOCKET_EVENTS.INVENTORY_ALERT, payload);
}

// ───────────────────────── staff read APIs ─────────────────────────

export async function listInventory(q: InventoryListQuery) {
  const where: Prisma.ProductVariantWhereInput = { isActive: true };
  if (q.q) {
    where.OR = [
      { sku: { contains: q.q, mode: 'insensitive' } },
      { product: { name: { contains: q.q, mode: 'insensitive' } } },
      { color: { contains: q.q, mode: 'insensitive' } },
    ];
  }
  if (q.lowStock || q.outOfStock) {
    // column-to-column comparisons aren't expressible in Prisma filters → small raw query for ids
    const ids = await prisma.$queryRaw<{ variantId: string }[]>`
      SELECT "variantId" FROM "Inventory"
      WHERE (${q.outOfStock ?? false}::boolean AND quantity - reserved <= 0)
         OR (${q.lowStock ?? false}::boolean AND quantity - reserved > 0 AND quantity - reserved <= "lowStockThreshold")`;
    where.id = { in: ids.map((r) => r.variantId) };
  }
  const [total, rows] = await Promise.all([
    prisma.productVariant.count({ where }),
    prisma.productVariant.findMany({
      where,
      include: { inventory: true, product: { select: { id: true, name: true, slug: true, status: true } } },
      orderBy: [{ product: { name: 'asc' } }, { color: 'asc' }, { size: 'asc' }],
      skip: (q.page - 1) * q.pageSize,
      take: q.pageSize,
    }),
  ]);
  const items = rows.map((v) => {
    const quantity = v.inventory?.quantity ?? 0;
    const reserved = v.inventory?.reserved ?? 0;
    const available = Math.max(quantity - reserved, 0);
    const threshold = v.inventory?.lowStockThreshold ?? 0;
    return {
      variantId: v.id,
      sku: v.sku,
      color: v.color,
      size: v.size,
      product: v.product,
      quantity,
      reserved,
      available,
      lowStockThreshold: threshold,
      status: available === 0 ? 'OUT_OF_STOCK' : available <= threshold ? 'LOW_STOCK' : 'OK',
    };
  });
  return paginated(items, total, q.page, q.pageSize);
}

export async function listMovements(q: { variantId?: string; type?: StockMovementType; page: number; pageSize: number }) {
  const where: Prisma.StockMovementWhereInput = { variantId: q.variantId, type: q.type };
  const [total, rows] = await Promise.all([
    prisma.stockMovement.count({ where }),
    prisma.stockMovement.findMany({
      where,
      include: {
        variant: { select: { sku: true, color: true, size: true, product: { select: { name: true } } } },
        actor: { select: { id: true, fullName: true } },
      },
      orderBy: { createdAt: 'desc' },
      skip: (q.page - 1) * q.pageSize,
      take: q.pageSize,
    }),
  ]);
  return paginated(rows, total, q.page, q.pageSize);
}

export async function listAlerts(q: { unread?: boolean; page: number; pageSize: number }) {
  const where: Prisma.InventoryAlertWhereInput = q.unread ? { isRead: false } : {};
  const [total, rows] = await Promise.all([
    prisma.inventoryAlert.count({ where }),
    prisma.inventoryAlert.findMany({
      where,
      include: { variant: { select: { sku: true, color: true, size: true, productId: true, product: { select: { name: true } } } } },
      orderBy: { createdAt: 'desc' },
      skip: (q.page - 1) * q.pageSize,
      take: q.pageSize,
    }),
  ]);
  return paginated(rows, total, q.page, q.pageSize);
}

export async function markAlertRead(id: string) {
  const res = await prisma.inventoryAlert.updateMany({ where: { id }, data: { isRead: true } });
  if (res.count === 0) throw Errors.notFound('Alert not found');
}
export const markAllAlertsRead = () =>
  prisma.inventoryAlert.updateMany({ where: { isRead: false }, data: { isRead: true } }).then((r) => r.count);
