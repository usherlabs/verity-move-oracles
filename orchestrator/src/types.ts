export type RoochEnv = {
  privateKey: string;
  chainId: string;
  oracleAddress: string;
  indexerCron?: string;
};
export const ALLOWED_HOST = ["x.com", "api.x.com", "twitter.com", "api.twitter.com"];

export const RoochNetworkList = ["testnet", "devnet", "localnet", "pre-mainnet"] as const;

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

interface OracleParams {
  abilities: number;
  type: string;
  value: {
    body: string;
    headers: string;
    method: string;
    url: string;
  };
}

interface ResponseValue {
  vec: string[];
}

interface Response {
  abilities: number;
  type: string;
  value: ResponseValue;
}

interface Data {
  created_at: string;
  edit_history_tweet_ids?: string[];
  id: string;
  text: string;
  entities: {
    hashtags: Array<{
      start: number;
      end: number;
      tag: string;
    }>;
  };
  author_id: string;
}

interface TweetData {
  data: Data;
}

export interface IOracleRequest {
  oracle: string;
  params: OracleParams;
  pick: string;
  response: TweetData;
  response_status: number;
}

export type ProcessedRequestAdded<T> = {
  creator?: string;
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

export interface AptosTransactionData {
  account_transactions: Array<{
    account_address: string;
    transaction_version: number;
  }>;
}

export interface AptosBlockMetadataTransaction {
  version: string;
  hash: string;
  state_change_hash: string;
  event_root_hash: string;
  state_checkpoint_hash?: string | null;
  gas_used: string;
  success: boolean;
  vm_status: string;
  accumulator_root_hash: string;
  changes: Array<{
    address: string;
    state_key_hash: string;
    data: {
      type: string;
      data: {
        [key: string]: any;
      };
    };
    type: string;
  }>;
  id: string;
  epoch: string;
  round: string;
  events: Array<{
    guid: {
      creation_number: number;
      account_address: string;
    };
    sequence_number: number;
    type: string;
    data: {
      [key: string]: any;
    };
  }>;
  previous_block_votes_bitvec: number[];
  proposer: string;
  failed_proposer_indices: string[];
  timestamp: number;
  type: string;
}

export interface AptosRequestEvent {
  creator: string;
  notify: {
    vec: string[];
  };
  oracle: string;
  params: {
    body: string;
    headers: string;
    method: string;
    url: string;
  };
  pick: string;
  request_id: string;
}
