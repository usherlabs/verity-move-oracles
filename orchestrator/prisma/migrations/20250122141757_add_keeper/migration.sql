-- CreateTable
CREATE TABLE "Keeper" (
    "id" TEXT NOT NULL,
    "chain" TEXT NOT NULL DEFAULT 'ROOCH-testnet',
    "module" TEXT NOT NULL,
    "privateKey" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updateAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Keeper_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "Keeper_chain_module_idx" ON "Keeper"("chain", "module");
