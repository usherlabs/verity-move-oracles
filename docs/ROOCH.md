# Oracles for Rooch Network

## Running with Rooch (Locally)

[See Video Guide for Local Development](https://www.loom.com/share/09f69ebfcf7f4b4899150c4a83e7c704?sid=4ca55c5e-fdf2-4bb7-8401-87af05295362).

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
rooch move run --function 0x9ce8eaf2166e9a6d4e8f1d27626297a0cf5ba1eaeb31137e08cc8f7773fb83f8::example_caller::request_data --sender-account default --args 'string:https://api.x.com/2/users/by/username/elonmusk?user.fields=public_metrics' --args 'string:GET' --args 'string:{}' --args 'string:{}' --args 'string:.data.public_metrics.followers_count' --args 'address:0x694cbe655b126e9e6a997e86aaab39e538abf30a8c78669ce23a98740b47b65d'
```

To check the state of the response object on a local Rooch node, use the following command:

```bash
rooch state -a /object/0x7a01ddf194f8a1c19212d56f747294352bf2e5cf23e6e10e64937aa1955704b0
```

To confirm the `Request` Object State, use the Object ID generated from the initial transaction to query the state of the response object.
This allows you to verify that the request was processed successfully and that the response object is correctly stored in the Rooch Network state.

## Instructions for Rooch on Test/Dev/Mainnet

An example of requesting the Twitter Followers Count on a Rooch Testnet:

```bash
rooch move run --function 0x9ce8eaf2166e9a6d4e8f1d27626297a0cf5ba1eaeb31137e08cc8f7773fb83f8::example_caller::request_data --sender-account default --args 'string:https://api.x.com/2/users/by/username/elonmusk?user.fields=public_metrics' --args 'string:GET' --args 'string:{}' --args 'string:{}' --args 'string:.data.public_metrics.followers_count' --args 'address:0x694cbe655b126e9e6a997e86aaab39e538abf30a8c78669ce23a98740b47b65d'
```

To check the state of the response object on testnet, devnet, or mainnet, 

1. Switch to the relevant network using `rooch env switch --alias <NETWORK_ALIAS>`
2. Use the following command:

```bash
rooch object --object-ids <OBJECT_ID>
```
