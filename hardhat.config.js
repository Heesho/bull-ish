const { config } = require("dotenv");

require("@nomiclabs/hardhat-waffle");
require("@nomicfoundation/hardhat-verify");
require("solidity-coverage");

const CHAIN_ID = 80069; // Berachain Bepolia chain id
// const CHAIN_ID = 80094; // Berachain Mainnet chain id

config();
const PRIVATE_KEY = process.env.PRIVATE_KEY || "";
const SCAN_API_KEY = process.env.SCAN_API_KEY || "";
const RPC_URL = process.env.RPC_URL || "";

module.exports = {
  solidity: {
    version: "0.8.19",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    mainnet: {
      url: RPC_URL,
      chainId: CHAIN_ID,
      accounts: [PRIVATE_KEY],
    },
    hardhat: {},
  },
  etherscan: {
    apiKey: SCAN_API_KEY,
    customChains: [
      {
        network: "berachain",
        chainId: 80094,
        urls: {
          apiURL: "https://api.berascan.com/api",
          browserURL: "https://berascan.com/",
        },
      },
      {
        network: "berachain_bepolia",
        chainId: 80069,
        urls: {
          apiURL:
            "https://api.routescan.io/v2/network/testnet/evm/80069/etherscan",
          browserURL: "https://bepolia.beratrail.io",
        },
      },
    ],
  },
  paths: {
    sources: "./contracts",
    tests: "./tests",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  mocha: {
    timeout: 300000,
  },
};
