-- CreateTable
CREATE TABLE "Events" (
    "id" TEXT NOT NULL,
    "eventHandleId" TEXT NOT NULL,
    "eventSeq" INTEGER NOT NULL,
    "eventType" TEXT NOT NULL,
    "eventData" TEXT NOT NULL,
    "eventIndex" TEXT NOT NULL,
    "decoded_event_data" TEXT NOT NULL,
    "status" INTEGER NOT NULL,
    "retries" INTEGER NOT NULL,
    "response" TEXT,
    "indexedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updateAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Events_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "Events_eventHandleId_eventSeq_idx" ON "Events"("eventHandleId", "eventSeq");
