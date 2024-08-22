import { randomUUID } from "node:crypto";
import * as fs from "node:fs";
import * as path from "node:path";
import { config } from "dotenv";

// Convert object to .env format
const convertToEnvFormat = (obj: Record<string, string | undefined>): string => {
  return Object.entries(obj)
    .map(([key, value]) => `${key}=${value ?? ""}`)
    .join("\n");
};

const envFilePath = path.resolve(__dirname, ".env.");

// Function to create .env file
const createEnvFile = (config: Record<string, string | undefined>, envFilePath: string) => {
  fs.writeFileSync(envFilePath, convertToEnvFormat(config), "utf8");
};

// Function to delete .env file
const deleteEnvFile = (envFilePath: string) => {
  if (fs.existsSync(envFilePath)) {
    fs.unlinkSync(envFilePath);
  }
};

describe(".env Check", () => {
  let testFilePath: string;
  beforeEach(() => {
    testFilePath = envFilePath + randomUUID();
  });

  afterEach(() => {
    deleteEnvFile(testFilePath);
  });

  test("test dynamic Env", async () => {
    const data = {
      test: "tedded",
    };
    createEnvFile(data, testFilePath);
    config({ path: testFilePath });
    expect(data.test).toBe(process.env.test);
  });

  const tests = [
    {
      name: "Empty .env file",
      data: {},
      wantErr: true,
      errorMessage: '"roochOracleAddress" is not allowed to be empty',
    },
    {
      name: "test invalid roochOracleAddress",
      data: {
        ROOCH_ORACLE_ADDRESS: "0xf81628c3bf85c3fc628f29a3739365d4428101fbbecca0dcc7e3851f34faea6V",
      },
      wantErr: true,
      errorMessage: '"roochOracleAddress" contains an invalid value',
    },
    {
      name: "Invalid Chain Check ",
      data: {
        PREFERRED_CHAIN: "ROOCHd",
        ROOCH_ORACLE_ADDRESS: "0xf81628c3bf85c3fc628f29a3739365d4428101fbbecca0dcc7e3851f34faea6a",
      },
      wantErr: true,
      errorMessage: '"preferredChain" must be one of [ROOCH, APTOS]',
    },
    {
      name: "valid ROOCH_ORACLE_ADDRESS but missing",
      data: {
        PREFERRED_CHAIN: "ROOCH",
        ROOCH_ORACLE_ADDRESS: "0xf81628c3bf85c3fc628f29a3739365d4428101fbbecca0dcc7e3851f34faea6c",
      },
      wantErr: true,
      errorMessage: '"roochPrivateKey" is not allowed to be empty',
    },
    {
      name: "valid data",
      data: {
        PREFERRED_CHAIN: "ROOCH",
        ROOCH_ORACLE_ADDRESS: "0xf81628c3bf85c3fc628f29a3739365d4428101fbbecca0dcc7e3851f34faea6c",
        ROOCH_PRIVATE_KEY: "0xf81628c3bf85c3fc628f29a3739365d4428101fbbecca0dcc7e3851f34faea6c",
      },
      wantErr: false,
      errorMessage: '"roochPrivateKey" is not allowed to be empty',
    },
    {
      name: "rooch variables not required when preferred chain is set to APTOS ",
      data: {
        PREFERRED_CHAIN: "APTOS",
      },
      wantErr: false,
      errorMessage: "",
    },
  ];

  tests.forEach(({ name, data, wantErr, errorMessage }) => {
    it(name, async () => {
      createEnvFile(data, testFilePath);
      config({ path: testFilePath, override: true });
      if (wantErr) {
        try {
          const { default: envVars } = await import("../env");
          expect(envVars).toBeNull();
        } catch (err: any) {
          expect(err?.message).toBe(errorMessage);
          expect(err).toBeInstanceOf(Error);
        }
      } else {
        const { default: envVars } = await import("../env");
        expect(envFilePath).not.toBeNull();
      }
    });
  });
});
