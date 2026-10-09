import { EventType, OrderStatus, prisma } from '@vibethread/database';
import { round2 } from '../lib/pricing';

/**
 * Daily rollup into ProductDailyStats.
 *  - Days are Pakistan days (UTC+5), because the shop and its staff live there.
 *  - views / dwell / cart adds / checkouts / hesitation come from tracking events.
 *  - purchases and revenue come from real orders (cancelled/returned excluded),
 *    never from client events, so they cannot be faked or double counted.
 *  - Re-running a day is safe: rows are overwritten, not incremented.
 */

const PKT_OFFSET = '+05:00';
const DAY_MS = 24 * 60 * 60 * 1000;

export function pktDayString(d: Date): string {
  return new Date(d.getTime() + 5 * 60 * 60 * 1000).toISOString().slice(0, 10);
}
export function dayRange(ymd: string) {
  const start = new Date(`${ymd}T00:00:00.000${PKT_OFFSET}`);
  return { start, end: new Date(start.getTime() + DAY_MS), dateColumn: new Date(`${ymd}T00:00:00.000Z`) };
}

type Acc = {
  views: number;
  dwellSum: number;
  dwellCount: number;
  cartAdds: number;
  checkouts: number;
  hesitation: number;
  purchases: number;
  revenue: number;
};
const blank = (): Acc => ({ views: 0, dwellSum: 0, dwellCount: 0, cartAdds: 0, checkouts: 0, hesitation: 0, purchases: 0, revenue: 0 });

export async function rollupDay(ymd: string): Promise<number> {
  const { start, end, dateColumn } = dayRange(ymd);
  const acc = new Map<string, Acc>();
  const get = (id: string) => {
    let a = acc.get(id);
    if (!a) acc.set(id, (a = blank()));
    return a;
  };

  const groups = await prisma.trackingEvent.groupBy({
    by: ['productId', 'type'],
    where: { occurredAt: { gte: start, lt: end }, productId: { not: null } },
    _count: { _all: true },
    _sum: { durationMs: true },
  });
  const dwellCounts = await prisma.trackingEvent.groupBy({
    by: ['productId'],
    where: { occurredAt: { gte: start, lt: end }, productId: { not: null }, type: EventType.PRODUCT_VIEW, durationMs: { not: null } },
    _count: { _all: true },
  });

  for (const g of groups) {
    const a = get(g.productId!);
    const n = g._count._all;
    switch (g.type) {
      case EventType.PRODUCT_VIEW:
        a.views += n;
        a.dwellSum += g._sum.durationMs ?? 0;
        break;
      case EventType.ADD_TO_CART:
        a.cartAdds += n;
        break;
      case EventType.CHECKOUT_START:
        a.checkouts += n;
        break;
      case EventType.SIZE_TOGGLE:
      case EventType.ADD_TO_CART_HOVER:
        a.hesitation += n;
        break;
      default:
        break;
    }
  }
  for (const d of dwellCounts) get(d.productId!).dwellCount += d._count._all;

  const items = await prisma.orderItem.findMany({
    where: {
      order: { placedAt: { gte: start, lt: end }, status: { notIn: [OrderStatus.CANCELLED, OrderStatus.RETURNED] } },
    },
    select: { variantId: true, quantity: true, unitPrice: true },
  });
  // OrderItem has no relation to ProductVariant, so resolve variant -> product here
  const variantIds = [...new Set(items.map((i) => i.variantId))];
  const variants = variantIds.length
    ? await prisma.productVariant.findMany({ where: { id: { in: variantIds } }, select: { id: true, productId: true } })
    : [];
  const productOf = new Map(variants.map((v) => [v.id, v.productId]));
  for (const it of items) {
    const productId = productOf.get(it.variantId);
    if (!productId) continue; // variant was deleted since the order
    const a = get(productId);
    a.purchases += it.quantity;
    a.revenue += Number(it.unitPrice) * it.quantity;
  }

  for (const [productId, a] of acc) {
    const data = {
      views: a.views,
      avgDwellMs: a.dwellCount ? Math.round(a.dwellSum / a.dwellCount) : 0,
      cartAdds: a.cartAdds,
      checkouts: a.checkouts,
      purchases: a.purchases,
      hesitationHits: a.hesitation,
      revenue: round2(a.revenue),
    };
    await prisma.productDailyStats.upsert({
      where: { productId_date: { productId, date: dateColumn } },
      create: { productId, date: dateColumn, ...data },
      update: data,
    });
  }
  return acc.size;
}

async function rollupRecent() {
  const today = pktDayString(new Date());
  const yesterday = pktDayString(new Date(Date.now() - DAY_MS));
  await rollupDay(yesterday);
  await rollupDay(today);
}

let timer: NodeJS.Timeout | undefined;
/** Recomputes yesterday + today now and every 5 minutes. Safe to call twice. */
export function startAnalyticsRollup(intervalMs = 5 * 60 * 1000) {
  if (timer) return;
  const run = () => rollupRecent().catch((err) => console.error('[analytics] rollup failed:', err));
  void run();
  timer = setInterval(run, intervalMs);
  timer.unref();
}

// ───────────────────────── reads for the staff dashboard ─────────────────────────

export async function overview(days: number) {
  const today = pktDayString(new Date());
  const from = pktDayString(new Date(Date.now() - (days - 1) * DAY_MS));
  const rows = await prisma.productDailyStats.findMany({
    where: { date: { gte: dayRange(from).dateColumn, lte: dayRange(today).dateColumn } },
    include: { product: { select: { id: true, name: true, slug: true } } },
  });

  const totals = { views: 0, cartAdds: 0, checkouts: 0, purchases: 0, revenue: 0, hesitationHits: 0 };
  const byProduct = new Map<string, { product: { id: string; name: string; slug: string }; views: number; cartAdds: number; checkouts: number; purchases: number; revenue: number; hesitationHits: number; dwellWeighted: number }>();
  const byDay = new Map<string, { date: string; views: number; cartAdds: number; purchases: number; revenue: number }>();

  for (const r of rows) {
    totals.views += r.views;
    totals.cartAdds += r.cartAdds;
    totals.checkouts += r.checkouts;
    totals.purchases += r.purchases;
    totals.revenue += Number(r.revenue);
    totals.hesitationHits += r.hesitationHits;

    const p = byProduct.get(r.productId) ?? { product: r.product, views: 0, cartAdds: 0, checkouts: 0, purchases: 0, revenue: 0, hesitationHits: 0, dwellWeighted: 0 };
    p.views += r.views;
    p.cartAdds += r.cartAdds;
    p.checkouts += r.checkouts;
    p.purchases += r.purchases;
    p.revenue += Number(r.revenue);
    p.hesitationHits += r.hesitationHits;
    p.dwellWeighted += r.avgDwellMs * r.views;
    byProduct.set(r.productId, p);

    const key = r.date.toISOString().slice(0, 10);
    const d = byDay.get(key) ?? { date: key, views: 0, cartAdds: 0, purchases: 0, revenue: 0 };
    d.views += r.views;
    d.cartAdds += r.cartAdds;
    d.purchases += r.purchases;
    d.revenue += Number(r.revenue);
    byDay.set(key, d);
  }

  const since5 = new Date(Date.now() - 5 * 60 * 1000);
  const since30 = new Date(Date.now() - 30 * 60 * 1000);
  const [activeSessions, events30] = await Promise.all([
    prisma.session.count({ where: { lastSeenAt: { gte: since5 }, endedAt: null } }),
    prisma.trackingEvent.count({ where: { occurredAt: { gte: since30 } } }),
  ]);

  const pct = (a: number, b: number) => (b > 0 ? round2((a / b) * 100) : 0);
  return {
    range: { from, to: today, days },
    totals: {
      ...totals,
      revenue: round2(totals.revenue),
      viewToCartPct: pct(totals.cartAdds, totals.views),
      cartToPurchasePct: pct(totals.purchases, totals.cartAdds),
    },
    daily: [...byDay.values()].sort((a, b) => a.date.localeCompare(b.date)).map((d) => ({ ...d, revenue: round2(d.revenue) })),
    products: [...byProduct.values()]
      .sort((a, b) => b.views - a.views)
      .slice(0, 20)
      .map(({ dwellWeighted, ...p }) => ({
        ...p,
        revenue: round2(p.revenue),
        avgDwellMs: p.views ? Math.round(dwellWeighted / p.views) : 0,
        viewToCartPct: pct(p.cartAdds, p.views),
      })),
    live: { activeSessions, eventsLast30Min: events30 },
  };
}
