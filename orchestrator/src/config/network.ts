import type { SuiNetwork } from "@/types";
import { getFullnodeUrl } from "@mysten/sui/client";

export const networkConfig = {
  localnet: {
    url: getFullnodeUrl("localnet"),
  },
  devnet: {
    url: getFullnodeUrl("devnet"),
  },
  testnet: {
    url: getFullnodeUrl("testnet"),
  },
  mainnet: {
    url: getFullnodeUrl("mainnet"),
  },
} as const;

export function getNetworkConfig(network: SuiNetwork) {
  return networkConfig[network];
}
