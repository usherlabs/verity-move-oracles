# Verity Move Oracles

An Oracle Network for sourcing and verifying data from restricted APIs on Move oriented blockchains.

The first Oracle supported is an Oracle for X (Twitter) data. 

## Supported Blockchains

- [x] [Rooch Network](https://rooch.network/)
- [ ] [Aptos](https://aptosfoundation.org/)
- [ ] ~Sui~

## Running Rooch orchestrator (Locally)

### Prerequisites

Before running the script, ensure you have the following prerequisites installed:

- **Rooch**: A blockchain development toolset.
- **Node.js**: Alongside npm, yarn, or pnpm package managers.

### Step-by-Step Instructions

#### Step 1: Create a Roach Account

First, you need to create a Roach account. This account will be used throughout the setup process.

```bash
rooch account create
```

#### Step 2: Clear and Start Local Network

Clear any existing state and start the local network.

```bash
rooch server clean
rooch server start
```

#### Step 3: Deploy Contracts

Navigate to the `rooch` directory, build the contracts for development, publish them with named addresses and update `.env` `ROOCH_ORACLE_ADDRESS` with deployed Address

```bash
cd rooch
rooch move build --dev
rooch move publish --named-addresses verity_test_foreign_module=default,verity=default
cd ..
```

#### Step 4: Install Node Dependencies

Install the necessary Node.js dependencies using npm, yarn, or pnpm. Ensure you are in the root project directory.

```bash
npm install
# or
yarn install
# or
pnpm install
```

#### Step 5: Run Prisma Migration

Run the Prisma migration to update your database schema according to your models.

**In Production (for PostgreSQL):**

```bash
pnpm clean:db
pnpm prisma:generate
pnpm prisma:deploy
```

**In Development (for SQLite):**

```bash
pnpm clean:db
pnpm prisma:generate:dev
pnpm prisma:deploy:dev
```

#### Step 6: Update the .env file with the correct values

Copy the example environment file to create your own `.env` file:

```bash
cp .env.example .env
```

Export the Rooch Private Key:

```bash
rooch account export --address <Rooch Address>
``` 

To connect to the local Rooch node, set `ROOCH_CHAIN_ID` to `"localnet"`.  
Otherwise, connect to testNet by setting `ROOCH_CHAIN_ID` to `"testnet"`, or to TestNet by setting `ROOCH_CHAIN_ID` to `"testnet"`.  
Ensure that `ROOCH_ORACLE_ADDRESS` is set to the address of the deployed module, e.g., `"0x85859e45551846d9ab8651bb0b6f6e1740c9d758cfda05cfc39d49e2a604d783"`.

#### Step 7: Run Orchestrator

Start the development server for your application. This step might vary depending on your project setup; the command below assumes a typical setup.

```bash
npm run dev
# or
yarn dev
# or
pnpm dev
```

#### Step 8: Send New Request Transaction

Finally, send a new request transaction to have it indexed. Make sure to replace placeholders with actual values relevant to your setup.

```bash
rooch move run --function  <contractAddress>::example_caller::request_data --sender-account default --args 'string:https://api.x.com/2/users/by/username/elonmusk?user.fields=public_metrics' --args 'string:GET' --args 'string:{}' --args 'string:{}' --args 'string:.data.public_metrics.followers_count' --args 'address:<Orchestrator Address>'
```

Here's an example of requesting the Twitter Followers Count on a Local Rooch Node:

```bash
rooch move run --function 0x85859e45551846d9ab8651bb0b6f6e1740c9d758cfda05cfc39d49e2a604d783::example_caller::request_data --sender-account 0x85859e45551846d9ab8651bb0b6f6e1740c9d758cfda05cfc39d49e2a604d783 --args 'string:https://api.x.com/2/users/by/username/elonmusk?user.fields=public_metrics' --args 'string:GET' --args 'string:{}' --args 'string:{}' --args 'string:.data.public_metrics.followers_count' --args 'address:0x85859e45551846d9ab8651bb0b6f6e1740c9d758cfda05cfc39d49e2a604d783'
```

To check the state of the response object, use the following command:

```bash
rooch state -a /object/0x7a01ddf194f8a1c19212d56f747294352bf2e5cf23e6e10e64937aa1955704b0
```

To confirm the `Request` Object State, use the Object ID generated from the initial transaction to query the state of the response object.
This allows you to verify that the request was processed successfully and that the response object is correctly stored in the Rooch Network state.
