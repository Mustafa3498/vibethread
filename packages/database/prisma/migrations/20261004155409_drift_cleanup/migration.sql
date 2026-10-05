-- DropIndex
DROP INDEX "TrackingEvent_occurredAt_brin_idx";

-- AlterTable
ALTER TABLE "TrackingEvent" ALTER COLUMN "id" DROP DEFAULT;
