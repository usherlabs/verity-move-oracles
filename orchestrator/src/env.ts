import type { RoochNetwork } from "@/types";

export default {
  rooch: {
    chainId: process.env.ROOCH_CHAIN_ID || ("testnet" as RoochNetwork),
    oracleAddress: process.env.ROOCH_ORACLE_ADDRESS || "",
    indexerCron: process.env.ROOCH_INDEXER_CRON || "*/5 * * * * *",
    privateKey: process.env.ROOCH_PRIVATE_KEY || "",
  },
  // aptos: {
  //   chainId: process.env.APTOS_CHAIN_ID,
  //   oracleAddress: process.env.APTOS_ORACLE_ADDRESS,
  //   indexerCron: process.env.APTOS_INDEXER_CRON,
  //   privateKey: process.env.APTOS_PRIVATE_KEY,
  // }
};
