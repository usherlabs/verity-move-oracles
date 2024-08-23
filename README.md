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

- **Roach**: A blockchain development toolset.
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

```bash
npx prisma migrate deploy
```

#### Step 6: Run Orchestrator

Start the development server for your application. This step might vary depending on your project setup; the command below assumes a typical setup.

```bash
npm run dev
# or
yarn dev
# or
pnpm dev
```

#### Step 7: Send New Request Transaction

Finally, send a new request transaction to have it indexed. Make sure to replace placeholders with actual values relevant to your setup.

```bash
cd rooch
rooch move run --function <contractAddress>::example_caller::request_data --sender-account default --args 'string:v2v3v' --args 'string:v2v3v' --args 'string:v2v3v' --args 'string:v2v3v' --args 'string:v2v3v' --args 'address:0x9a759932a6640790b3e2a5fefdf23917c8830dcd8998fe8af3f3b49b0ab5ca35'
```


