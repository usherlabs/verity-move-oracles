-- CreateTable
CREATE TABLE "SupportedUrl" (
    "domain" TEXT NOT NULL,
    "supported_path" TEXT[],
    "authType" TEXT NOT NULL,
    "authKey" TEXT NOT NULL,
    "requestRate" BIGINT NOT NULL,

    CONSTRAINT "SupportedUrl_pkey" PRIMARY KEY ("domain")
);

-- CreateIndex
CREATE INDEX "SupportedUrl_authKey_idx" ON "SupportedUrl"("authKey");
