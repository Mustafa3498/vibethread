import { EventType } from '@vibethread/database';
import { z } from 'zod';

const uuid = z.string().uuid();

const eventSchema = z.object({
  type: z.nativeEnum(EventType),
  productId: uuid.optional(),
  /** Alternative to productId (cart lines only know the variant): the server resolves product, colour and size. */
  variantId: uuid.optional(),
  color: z.string().trim().max(40).optional(),
  size: z.string().trim().max(20).optional(),
  /** hover / dwell time in ms (client-measured, clamped to 1h) */
  durationMs: z.coerce.number().int().min(0).max(3_600_000).optional(),
  page: z.string().trim().max(120).optional(),
  /** flexible payload; kept small on purpose */
  meta: z
    .record(z.unknown())
    .refine((m) => JSON.stringify(m).length <= 2000, 'meta too large')
    .optional(),
  /** ISO time the event happened on the device (server clamps it). */
  occurredAt: z.string().datetime({ offset: true }).optional(),
});

export const trackBatchSchema = z.object({
  /** Client-generated UUID, one per app session. */
  sessionId: uuid,
  /** Stable per-install id, so anonymous visitors can be recognised across sessions. */
  anonymousId: z.string().trim().min(8).max(64),
  deviceType: z.string().trim().max(30).optional(),
  events: z.array(eventSchema).min(1).max(50),
});
export type TrackBatchInput = z.infer<typeof trackBatchSchema>;
export type TrackEventInput = z.infer<typeof eventSchema>;

export const analyticsQuery = z.object({
  days: z.coerce.number().int().min(1).max(90).default(7),
});
export type AnalyticsQuery = z.infer<typeof analyticsQuery>;
