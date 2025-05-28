import type { ActorMethod } from "@dfinity/agent";
import type { IDL } from "@dfinity/candid";

export interface DirectVerificationResponse {
  signature: string;
  root: string;
  results: ProofVerificationResponse;
}
export type DirectVerificationResult = { Ok: DirectVerificationResponse } | { Err: string };
export interface MerkleTree {
  root: string;
  num_leaves: bigint;
  nodes: Array<string>;
}
export interface ProofBatch {
  proof_requests: Array<string>;
  notary_pub_key: string;
}
export type ProofResponse = { SessionProof: string } | { FullProof: string };
export type ProofVerificationResponse = Array<ProofResponse>;
export interface _SERVICE {
  ping: ActorMethod<[], string>;
  public_key: ActorMethod<[], { sec1_pk: string; etherum_pk: string }>;
  verify_proof_async: ActorMethod<[Array<string>, string], ProofVerificationResponse>;
  verify_proof_async_batch: ActorMethod<[Array<ProofBatch>], ProofVerificationResponse>;
  verify_proof_direct: ActorMethod<[Array<string>, string], DirectVerificationResult>;
  verify_proof_direct_batch: ActorMethod<[Array<ProofBatch>], DirectVerificationResult>;
}
export declare const idlFactory: IDL.InterfaceFactory;
export declare const init: (args: { IDL: typeof IDL }) => IDL.Type[];
