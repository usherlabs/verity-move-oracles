import { Account, Ed25519PrivateKey } from "@aptos-labs/ts-sdk";

async function main() {
  // Generate new private key and account
  const privateKey = Ed25519PrivateKey.generate();
  const account = Account.fromPrivateKey({ privateKey });

  console.log("\nSave these securely:");
  console.log("Private Key:", privateKey.toString());
  console.log("Account Address:", account.accountAddress.toString());
}

main().catch(console.error);
