-- DropIndex
DROP INDEX "Events_eventHandleId_eventSeq_chain_idx";

-- AlterTable
ALTER TABLE "Events" ADD COLUMN     "oracleAddress" TEXT NOT NULL DEFAULT '0x9ce8eaf2166e9a6d4e8f1d27626297a0cf5ba1eaeb31137e08cc8f7773fb83f8';

-- CreateIndex
CREATE INDEX "Events_eventHandleId_eventSeq_chain_oracleAddress_idx" ON "Events"("eventHandleId", "eventSeq", "chain", "oracleAddress");
