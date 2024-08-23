// TODO: Improve coverage to 90%
const coverageToNumber = 20; // [0..100]

/*
 * For a detailed explanation regarding each configuration property and type check, visit:
 * https://jestjs.io/docs/configuration
 */

export default {
  testTimeout: 40000,

  verbose: true,
  rootDir: "./",
  transform: {
    "^.+\\.ts?$": "ts-jest",
  },
  moduleFileExtensions: ["ts", "js", "json", "node"],
  clearMocks: true, // clear mocks before every test
  resetMocks: false, // reset mock state before every test
  testMatch: [
    "<rootDir>/**/*.spec.ts", // Commenting cache test for github actions
    "<rootDir>/**/*.test.ts",
    "<rootDir>/**/*.test.js",
  ], // match only tests inside /tests folder
  testPathIgnorePatterns: ["<rootDir>/node_modules/"], // exclude unnecessary folders

  // following lines are about coverage
  collectCoverage: true,
  collectCoverageFrom: ["<rootDir>/orchestrator/src/**/*.ts"],
  coverageDirectory: "<rootDir>/coverage",
  coverageReporters: ["lcov"],
  coverageThreshold: {
    global: {
      //   branches: coverageToNumber,
      //   functions: coverageToNumber,
      lines: coverageToNumber,
      statements: coverageToNumber,
    },
  },
};
