import env from "@/env";
import { Actor, HttpAgent } from "@dfinity/agent";
import { Secp256k1KeyIdentity } from "@dfinity/identity";
import bip39 from "bip39";
import hdkey from "hdkey";
import fetch from "isomorphic-fetch";

import { idlFactory as verity_verifier_idl } from "./verity_verifier.did.js";

export const identityFromSeed = async (phrase: string) => {
  const seed = await bip39.mnemonicToSeed(phrase);
  const root = hdkey.fromMasterSeed(seed);
  const addr_node = root.derive("m/44'/223'/0'/0/0");
  console.log({ addr_node: addr_node.privateKey });
  if (!addr_node.privateKey) {
    throw Error("invalid Seed Prase");
  }

  return Secp256k1KeyIdentity.fromSecretKey(addr_node.privateKey);
};

export const identity = identityFromSeed(env.proof.icSeed);

export const createActor = async (
  canisterId: string,
  options?: {
    agentOptions?: ConstructorParameters<typeof HttpAgent>[0];
    actorOptions?: Omit<Parameters<typeof Actor.createActor>[1], "agent" | "canisterId">;
  },
) => {
  const agent = new HttpAgent({ ...options?.agentOptions });
  await agent.fetchRootKey();
  return Actor.createActor(verity_verifier_idl, {
    agent,
    canisterId,
    ...options?.actorOptions,
  });
};

export const verifyVerifier = async () => {
  return await createActor(env.proof.icCanisterId, {
    agentOptions: {
      host: "https://icp0.io",
      fetch,
      identity: await identity,
    },
  });
};
