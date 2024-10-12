-- DropIndex
DROP INDEX "Events_eventHandleId_eventSeq_idx";

-- AlterTable
ALTER TABLE "Events" ADD COLUMN     "chain" TEXT NOT NULL DEFAULT 'ROOCH-testnet';

-- CreateIndex
CREATE INDEX "Events_eventHandleId_eventSeq_chain_idx" ON "Events"("eventHandleId", "eventSeq", "chain");
