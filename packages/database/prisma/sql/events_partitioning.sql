-- Paste this at the END of the generated init migration.sql
-- (see README "Prisma setup"). Prisma can't declare partitioned tables,
-- so we replace the table Prisma generated with a monthly RANGE-partitioned one.
-- Column types deliberately match what Prisma generates (TEXT ids, TIMESTAMP(3))
-- so future `prisma migrate dev` runs don't report drift.

DROP TABLE IF EXISTS "TrackingEvent" CASCADE;

CREATE TABLE "TrackingEvent" (
  "id"         TEXT         NOT NULL DEFAULT gen_random_uuid()::text,
  "occurredAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "sessionId"  TEXT         NOT NULL,
  "productId"  TEXT,
  "type"       "EventType"  NOT NULL,
  "color"      TEXT,
  "size"       TEXT,
  "durationMs" INTEGER,
  "page"       TEXT,
  "meta"       JSONB,
  CONSTRAINT "TrackingEvent_pkey" PRIMARY KEY ("id", "occurredAt"),
  CONSTRAINT "TrackingEvent_sessionId_fkey" FOREIGN KEY ("sessionId")
    REFERENCES "Session"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT "TrackingEvent_productId_fkey" FOREIGN KEY ("productId")
    REFERENCES "Product"("id") ON DELETE SET NULL ON UPDATE CASCADE
) PARTITION BY RANGE ("occurredAt");

-- Monthly partitions (automate with pg_partman or a scheduled job later)
CREATE TABLE "TrackingEvent_2026_10" PARTITION OF "TrackingEvent"
  FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE "TrackingEvent_2026_11" PARTITION OF "TrackingEvent"
  FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');
CREATE TABLE "TrackingEvent_2026_12" PARTITION OF "TrackingEvent"
  FOR VALUES FROM ('2026-12-01') TO ('2027-01-01');
-- Safety net so inserts never fail if a month partition is missing
CREATE TABLE "TrackingEvent_default" PARTITION OF "TrackingEvent" DEFAULT;

CREATE INDEX "TrackingEvent_sessionId_occurredAt_idx" ON "TrackingEvent" ("sessionId", "occurredAt");
CREATE INDEX "TrackingEvent_productId_type_occurredAt_idx" ON "TrackingEvent" ("productId", "type", "occurredAt");
CREATE INDEX "TrackingEvent_occurredAt_brin_idx" ON "TrackingEvent" USING BRIN ("occurredAt");
