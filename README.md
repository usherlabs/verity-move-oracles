# Verity Move Oracles

An Oracle Network for sourcing and verifying data from restricted APIs on Move oriented blockchains.

The first Oracle supported is an Oracle for X (Twitter) data. 

## Supported Blockchains

- [x] [Rooch Network](https://rooch.network/)
- [x] [Aptos](https://aptosfoundation.org/)
- [ ] Sui

## Contracts & Oracles

### Rooch Network

[See Video Demo on Testnet](https://www.loom.com/share/72903d5067b14a05989918f2300f4660?sid=6b7886dd-6074-4751-8d8c-609634117982).

See [Rooch Network Doc](./docs/ROOCH.md) for more information on local development, and testing instructions.

Contracts:

- **Testnet**: `0x9a759932a6640790b3e2a5fefdf23917c8830dcd8998fe8af3f3b49b0ab5ca35`

Oracles:

- **X (Twitter)**: `0x694cbe655b126e9e6a997e86aaab39e538abf30a8c78669ce23a98740b47b65d`

### Aptos Network

See [Aptos Doc](./docs/APTOS.md) for more information on local development, and testing instructions.

Contracts:

- **Testnet**: `0xa2b7160c0dc70548e8105121b075df9ea3b98c0c82294207ca38cb1165b94f59`

Oracles:

- **X (Twitter)**: *Coming Soon*

## Run an Oracle

## Prerequisites

Before running the script, ensure you have the following prerequisites installed:

- **Node.js**: Alongside npm, yarn, or pnpm package managers.

### Step 1: Install Node Dependencies

```bash
npm install
# or
yarn install
# or
pnpm install
```

### Step 2: Run Prisma Migration

If you're not already running PostgreSQL locally, you can use Docker to set it up quickly. Follow these steps:

#### Set Your .env variables for PostgreSQL

Ensure your `.env` file contains the following PostgreSQL credentials:

```plaintext
POSTGRES_USER=your_username
POSTGRES_PASSWORD=your_password
POSTGRES_DB=your_database
```

Replace `your_username`, `your_password`, and `your_database` with your desired PostgreSQL username, password, and database name.

#### Run PostgreSQL with Docker

Use Docker Compose to start a PostgreSQL container. Create a `docker-compose.yml` file with the following content:

```yaml
version: '3.1'

services:
  db:
    image: postgres
    restart: always
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    ports:
      - "5432:5432"
```

Run the following command to start the PostgreSQL container in detached mode:

```bash
docker-compose up -d
```

This will start a PostgreSQL instance accessible on port 5432 of your localhost, using the credentials specified in your `.env` file.

#### Run the Prisma migration 

This will update your database schema according to your models.

**In Production (for PostgreSQL):**

```bash
pnpm prisma:generate
pnpm prisma:deploy
```

### Step 3: Update the .env file with the correct values

Copy the example environment file to create your own `.env` file:

```bash
cp .env.example .env
```

**To support Rooch Network**, export the Rooch Private Key:

```bash
rooch account export --address <Rooch Address>
``` 

To connect to the local Rooch node, set `ROOCH_CHAIN_ID` to `"localnet"`.  
Otherwise, connect to testNet by setting `ROOCH_CHAIN_ID` to `"testnet"`, or to TestNet by setting `ROOCH_CHAIN_ID` to `"testnet"`.  
Ensure that `ROOCH_ORACLE_ADDRESS` is set to the address of the deployed module, e.g., `"0x85859e45551846d9ab8651bb0b6f6e1740c9d758cfda05cfc39d49e2a604d783"`.

**To support Aptos Network**, set `APTOS_PRIVATE_KEY` to your Aptos Wallet Private Key.

### Step 4: Run Orchestrator Node

Start the development server for your application. This step might vary depending on your project setup; the command below assumes a typical setup.

```bash
npm run dev
# or
yarn dev
# or
pnpm dev
```
