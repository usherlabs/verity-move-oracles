import { verifyVerifier } from "./identity";
import type { ProofVerificationResponse } from "./verity_verifier.did.js";

async function verify_proof(proof: string, public_key: string) {
  const verity = await verifyVerifier();
  const result = (await verity.verify_proof_direct([proof], public_key)) as ProofVerificationResponse;
  return result;
}

export default verify_proof;
``;
