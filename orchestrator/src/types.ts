export type RoochEnv = {
  privateKey: string;
  chainId: string;
  oracleAddress: string;
  indexerCron?: string;
};
export const ALLOWED_HOST = ["x.com", "api.x.com", "twitter.com", "api.twitter.com"];

export const RoochNetworkList = ["testnet", "devnet", "localnet"] as const;

export const AptosNetworkList = ["testnet", "mainnet"] as const;

export const ChainList = ["ROOCH", "APTOS"] as const;

export type RoochNetwork = (typeof RoochNetworkList)[number];

export type AptosNetwork = (typeof AptosNetworkList)[number];

export type SupportedChain = (typeof ChainList)[number];

export const SupportedChain = ChainList.reduce(
  (acc, value) => {
    acc[value] = value;
    return acc;
  },
  {} as Record<(typeof ChainList)[number], string>,
);

interface ParamsValue {
  abilities: number;
  type: string;
  value: {
    body: string;
    headers: string;
    method: string;
    url: string;
  };
}

interface NotifyValue {
  abilities: number;
  type: string;
  value: VecValue;
}
interface VecValue {
  vec: string[];
}

export interface IRequestAdded {
  notify?: NotifyValue;
  oracle: string;
  params: ParamsValue;
  pick: string;
  request_id: string;
}

export type ProcessedRequestAdded<T> = {
  notify?: string;
  oracle: string;
  params: {
    body: string;
    headers: string;
    method: string;
    url: string;
  };
  pick: string;
  request_id: string;
  fullData: T;
};

interface IDecoded<T> {
  abilities: number;
  type: string;
  value: T;
}

export interface IEvent<T> {
  event_id: {
    event_handle_id: string;
    event_seq: string;
  };
  event_type: string;
  event_data: string;
  event_index: string;
  decoded_event_data: IDecoded<T>;
}

interface Result<T> {
  data: IEvent<T>[];
}

export interface JsonRpcResponse<T> {
  jsonrpc: string;
  result: Result<T>;
}

export const RequestStatus = {
  INDEXED: 1,
  SUCCESS: 2,
  INVALID_URL: 3,
  INVALID_PAYLOAD: 4,
  UNREACHABLE: 5,
  FAILED: 6,
};
