-- CreateTable
CREATE TABLE "Events" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "eventHandleId" TEXT NOT NULL,
    "eventSeq" INTEGER NOT NULL,
    "eventType" TEXT NOT NULL,
    "eventData" TEXT NOT NULL,
    "eventIndex" TEXT NOT NULL,
    "decoded_event_data" TEXT NOT NULL,
    "status" INTEGER NOT NULL,
    "retries" INTEGER NOT NULL,
    "response" TEXT,
    "executedAt" DATETIME,
    "indexedAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updateAt" DATETIME NOT NULL
);

-- CreateIndex
CREATE INDEX "Events_eventHandleId_eventSeq_idx" ON "Events"("eventHandleId", "eventSeq");
