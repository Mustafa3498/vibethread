import { Role } from '@vibethread/database';
import { Router, type NextFunction, type Request, type Response } from 'express';
import { asyncHandler } from '../lib/async-handler';
import { Errors } from '../lib/errors';
import { authenticate, optionalAuth, requireRole } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { analyticsQuery, trackBatchSchema, type AnalyticsQuery, type TrackBatchInput } from '../schemas/track';
import * as analytics from '../services/analytics.service';
import * as tracking from '../services/tracking.service';

/** Tiny in-memory limiter: 120 batches per minute per IP (swap for Redis when we scale out). */
const hits = new Map<string, { n: number; resetAt: number }>();
function limit(req: Request, _res: Response, next: NextFunction) {
  const key = req.ip ?? 'unknown';
  const now = Date.now();
  const h = hits.get(key);
  if (!h || h.resetAt < now) {
    hits.set(key, { n: 1, resetAt: now + 60_000 });
    if (hits.size > 5000) for (const [k, v] of hits) if (v.resetAt < now) hits.delete(k);
    return next();
  }
  if (++h.n > 120) return next(Errors.badRequest('Too many tracking requests'));
  next();
}

/** POST /api/track: guests and signed-in users. Tracking must never block the app, so it answers 202. */
export const trackRouter = Router();
trackRouter.post(
  '/',
  limit,
  optionalAuth,
  validate(trackBatchSchema),
  asyncHandler(async (req, res) => {
    const out = await tracking.ingest(req.body as TrackBatchInput, req.auth?.userId ?? null);
    res.status(202).json(out);
  }),
);

/** Staff analytics, mounted at /api/manage/analytics. */
export const analyticsRouter = Router();
analyticsRouter.use(authenticate, requireRole(Role.SHOPKEEPER, Role.ADMIN));
analyticsRouter.get(
  '/overview',
  validate(analyticsQuery, 'query'),
  asyncHandler(async (req, res) => {
    res.json(await analytics.overview((req.query as unknown as AnalyticsQuery).days));
  }),
);
analyticsRouter.post(
  '/rollup',
  asyncHandler(async (_req, res) => {
    const today = analytics.pktDayString(new Date());
    res.json({ date: today, products: await analytics.rollupDay(today) });
  }),
);
