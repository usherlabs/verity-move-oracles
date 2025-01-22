/*
  Warnings:

  - A unique constraint covering the columns `[chain,module]` on the table `Keeper` will be added. If there are existing duplicate values, this will fail.

*/
-- DropIndex
DROP INDEX "Keeper_chain_module_idx";

-- CreateIndex
CREATE UNIQUE INDEX "Keeper_chain_module_key" ON "Keeper"("chain", "module");
