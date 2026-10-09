import { EventType, prisma, type Prisma } from '@vibethread/database';
import { SOCKET_ROOMS } from '@vibethread/shared';
import { Errors } from '../lib/errors';
import { ANALYTICS_EVENTS } from '../realtime/analytics-events';
import { emitToRoom } from '../realtime/emitters';
import type { TrackBatchInput } from '../schemas/track';

/**
 * Event ingestion.
 *  - Works for guests and signed-in users (`userId` comes from optionalAuth).
 *  - The session row is created on the first batch; a login later links it to the user.
 *  - Events for unknown products are kept but lose their productId (FK safety).
 *  - `variantId` is accepted instead of productId; the server fills product, colour and size.
 *  - Device clocks are not trusted: occurredAt is clamped to [now - 24h, now].
 */

const DAY_MS = 24 * 60 * 60 * 1000;

function clampTime(iso: string | undefined, now: number): Date {
  if (!iso) return new Date(now);
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return new Date(now);
  return new Date(Math.min(now, Math.max(now - DAY_MS, t)));
}

async function ensureSession(input: TrackBatchInput, userId: string | null) {
  const existing = await prisma.session.findUnique({
    where: { id: input.sessionId },
    select: { id: true, anonymousId: true, userId: true },
  });

  if (existing) {
    if (existing.anonymousId !== input.anonymousId) throw Errors.badRequest('Session does not belong to this device');
    await prisma.session.update({
      where: { id: existing.id },
      data: {
        lastSeenAt: new Date(),
        endedAt: null,
        ...(userId && !existing.userId ? { userId } : {}),
      },
    });
    return;
  }

  try {
    await prisma.session.create({
      data: {
        id: input.sessionId,
        anonymousId: input.anonymousId,
        userId,
        deviceType: input.deviceType ?? null,
      },
    });
  } catch (err) {
    // two first batches raced: the other one created it, which is fine
    if ((err as { code?: string }).code !== 'P2002') throw err;
  }
}

export async function ingest(input: TrackBatchInput, userId: string | null) {
  await ensureSession(input, userId);

  const now = Date.now();
  const wantedIds = [...new Set(input.events.map((e) => e.productId).filter((x): x is string => !!x))];
  const known = wantedIds.length
    ? new Set((await prisma.product.findMany({ where: { id: { in: wantedIds } }, select: { id: true } })).map((p) => p.id))
    : new Set<string>();

  const wantedVariants = [...new Set(input.events.map((e) => e.variantId).filter((x): x is string => !!x))];
  const variants = new Map<string, { productId: string; color: string; size: string }>();
  if (wantedVariants.length) {
    const found = await prisma.productVariant.findMany({
      where: { id: { in: wantedVariants } },
      select: { id: true, productId: true, color: true, size: true },
    });
    for (const v of found) variants.set(v.id, { productId: v.productId, color: v.color, size: v.size });
  }

  const rows: Prisma.TrackingEventCreateManyInput[] = input.events.map((e) => {
    const v = e.variantId ? variants.get(e.variantId) : undefined;
    const productId = e.productId && known.has(e.productId) ? e.productId : (v?.productId ?? null);
    return {
      sessionId: input.sessionId,
      occurredAt: clampTime(e.occurredAt, now),
      type: e.type,
      productId,
      color: e.color ?? v?.color ?? null,
      size: e.size ?? v?.size ?? null,
      durationMs: e.durationMs ?? null,
      page: e.page ?? null,
      meta: (e.meta ?? undefined) as Prisma.InputJsonValue | undefined,
    };
  });

  await prisma.trackingEvent.createMany({ data: rows });

  // session bookkeeping driven by special events
  const last = [...input.events].reverse();
  const end = last.find((e) => e.type === EventType.SESSION_END);
  const bought = input.events.some((e) => e.type === EventType.CHECKOUT_COMPLETE);
  if (end || bought) {
    await prisma.session.update({
      where: { id: input.sessionId },
      data: {
        ...(end ? { endedAt: new Date(), exitPage: end.page ?? null } : {}),
        ...(bought ? { converted: true } : {}),
      },
    });
  }

  // tiny live feed for the staff dashboard (no PII: ids and types only)
  emitToRoom(SOCKET_ROOMS.STAFF, ANALYTICS_EVENTS.EVENTS, {
    sessionId: input.sessionId,
    count: rows.length,
    events: rows.slice(-20).map((r) => ({
      type: r.type,
      productId: r.productId,
      occurredAt: (r.occurredAt as Date).toISOString(),
    })),
  });

  return { accepted: rows.length };
}
