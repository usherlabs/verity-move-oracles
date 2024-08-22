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

interface Value {
  notify: NotifyValue;
  oracle: string;
  params: ParamsValue;
  pick: string;
}

export interface IRequestAdded {
  abilities: number;
  type: string;
  value: Value;
}

export interface IEvent<T> {
  event_id: {
    event_handle_id: string;
    event_seq: string;
  };
  event_type: string;
  event_data: string;
  event_index: string;
  decoded_event_data: T;
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
};
