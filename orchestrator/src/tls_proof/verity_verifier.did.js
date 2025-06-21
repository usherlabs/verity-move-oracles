export const idlFactory = ({ IDL }) => {
  const ProofResponse = IDL.Variant({
    SessionProof: IDL.Text,
    FullProof: IDL.Text,
  });
  const ProofVerificationResponse = IDL.Vec(ProofResponse);
  const ProofBatch = IDL.Record({
    proof_requests: IDL.Vec(IDL.Text),
    notary_pub_key: IDL.Text,
  });
  const DirectVerificationResponse = IDL.Record({
    signature: IDL.Text,
    root: IDL.Text,
    results: ProofVerificationResponse,
  });
  const DirectVerificationResult = IDL.Variant({
    Ok: DirectVerificationResponse,
    Err: IDL.Text,
  });
  return IDL.Service({
    ping: IDL.Func([], [IDL.Text], ["query"]),
    public_key: IDL.Func([], [IDL.Record({ sec1_pk: IDL.Text, etherum_pk: IDL.Text })], []),
    verify_proof_async: IDL.Func([IDL.Vec(IDL.Text), IDL.Text], [ProofVerificationResponse], []),
    verify_proof_async_batch: IDL.Func([IDL.Vec(ProofBatch)], [ProofVerificationResponse], []),
    verify_proof_direct: IDL.Func([IDL.Vec(IDL.Text), IDL.Text], [DirectVerificationResult], []),
    verify_proof_direct_batch: IDL.Func([IDL.Vec(ProofBatch)], [DirectVerificationResult], []),
  });
};
export const init = ({ IDL }) => {
  return [];
};
