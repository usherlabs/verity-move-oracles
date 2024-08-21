export type RoochEnv = {
  privateKey: string;
  chainId: string;
  oracleAddress: string;
  indexerCron?: string;
};

export type RoochNetwork = "testnet" | "devnet" | "localnet";
