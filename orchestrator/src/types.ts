export type RoochEnv = {
  privateKey: string;
  chainId: string;
  oracleAddress: string;
  indexerCron?: string;
};

export const RoochNetworkList = ["testnet", "devnet", "localnet"] as const;

export const ChainList = ["ROOCH", "APTOS"] as const;

export type RoochNetwork = (typeof RoochNetworkList)[number];

export type SupportedChain = (typeof ChainList)[number];

export const SupportedChain = ChainList.reduce(
  (acc, value) => {
    acc[value] = value;
    return acc;
  },
  {} as Record<(typeof ChainList)[number], string>,
);
