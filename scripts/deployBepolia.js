// =============================================================================
// Bull-ish Testnet Deploy Script (Berachain Bepolia)
// =============================================================================
// Deploys and configures the full Bull-ish gamified DeFi protocol on the Bepolia testnet:
//   1. Bullas   - ERC-721 NFT collection (deployed here because it was already live on mainnet)
//   2. Moola    - ERC-20 in-game currency token
//   3. Factory  - Core game engine: manages players, tools, levels, and MOOLA claims
//   4. Wheel    - Spin-to-win plugin: players pay BERA to spin for MOOLA rewards
//   5. Multicall - Read-only aggregator for batching view calls from the frontend
//
// Key difference from the mainnet deploy script:
//   - Bullas NFT is deployed here (on mainnet it was pre-existing)
//   - All fee recipient addresses (incentives, treasury, developer, community) use a
//     single MULTISIG_ADDRESS for simplicity, whereas mainnet has separate addresses
//   - Includes additional setPlayPrice and setWheelSize configuration calls at the bottom
// =============================================================================

const { ethers } = require("hardhat");
const { utils, BigNumber } = require("ethers");
const hre = require("hardhat");

// Constants
// sleep: utility to pause execution between transactions so the RPC node can sync
const sleep = (delay) => new Promise((resolve) => setTimeout(resolve, delay));
// convert: shorthand for ethers.utils.parseUnits; converts a human-readable amount to its 18-decimal wei representation
const convert = (amount, decimals) => ethers.utils.parseUnits(amount, decimals);
// divDec: inverse of convert; divides a BigNumber by 10^decimals to get a human-readable number
const divDec = (amount, decimals = 18) => amount / 10 ** decimals;

// WBERA_ADDRESS: Wrapped BERA token on Berachain (same canonical address on both mainnet and testnet)
const WBERA_ADDRESS = "0x6969696969696969696969696969696969696969";
// VAULT_FACTORY_ADDRESS: Berachain's RewardVaultFactory; the Wheel uses this to create a BGT reward vault
const VAULT_FACTORY_ADDRESS = "0x94Ad6Ac84f6C6FbA8b8CCbD71d9f4f101def52a8";
// MULTISIG_ADDRESS: Single testnet multisig used for ALL fee recipients (incentives, treasury, developer, community).
// On mainnet these are four separate addresses, but on testnet a single address simplifies testing.
const MULTISIG_ADDRESS = "0x039ec2E90454892fCbA461Ecf8878D0C45FDdFeE";
// PYTH_ENTROPY_ADDRESS: Pyth Network's Entropy contract; provides verifiable randomness for Wheel spins
const PYTH_ENTROPY_ADDRESS = "0x36825bf3Fbdf5a29E2d5148bfe7Dcf7B5639e320";

// Contract Variables
// These are populated by either deployX() or getContracts() before any configuration step.
// Note: includes `bullas` which is not present in the mainnet deploy script.
let bullas, moola, factory, plugin, multicall;

/*===================================================================*/
/*===========================  CONTRACT DATA  =======================*/

// getContracts: Attaches to already-deployed contract instances by address.
// Used after initial deployment so subsequent config steps can reference the contracts
// without redeploying them.
async function getContracts() {
  // Bullas NFT -- deployed on testnet (on mainnet this was pre-existing)
  bullas = await ethers.getContractAt(
    "contracts/Bullas.sol:Bullas",
    "0xa54D15bD0D3Dd39C1Cfa05C6Cd285A34B4a69BE7"
  );
  moola = await ethers.getContractAt(
    "contracts/Moola.sol:Moola",
    "0x699ce67D64b4A62EADAdfA40196FFdFF31B63dBe"
  );
  factory = await ethers.getContractAt(
    "contracts/Factory.sol:Factory",
    "0x86Fe6FCA762434BCD336c18bf8b1866C7033099A"
  );
  plugin = await ethers.getContractAt(
    "contracts/Wheel.sol:Wheel",
    "0x2c2014C37A749434377955Bde51579A002Fbb3F1"
  );
  multicall = await ethers.getContractAt(
    "contracts/Multicall.sol:Multicall",
    "0x92c222bDfC6dE0d386fe8DdAEF00869c4248b21C"
  );
  console.log("Contracts Retrieved");
}

/*===========================  END CONTRACT DATA  ===================*/
/*===================================================================*/

// deployBullas: Deploys the Bullas ERC-721 NFT collection contract.
// No constructor arguments. This is only needed on testnet because the Bullas NFT
// was already deployed separately on mainnet before the rest of the protocol.
async function deployBullas() {
  console.log("Starting Bullas Deployment");
  const bullasArtifact = await ethers.getContractFactory("Bullas");
  const bullasContract = await bullasArtifact.deploy({
    gasPrice: ethers.gasPrice,
  });
  bullas = await bullasContract.deployed();
  await sleep(5000);
  console.log("Bullas Deployed at:", bullas.address);
}

// deployMoola: Deploys the Moola ERC-20 token contract.
// No constructor arguments -- the deployer becomes the initial owner with minting privileges.
async function deployMoola() {
  console.log("Starting Moola Deployment");
  const moolaArtifact = await ethers.getContractFactory("Moola");
  const moolaContract = await moolaArtifact.deploy({
    gasPrice: ethers.gasPrice,
  });
  moola = await moolaContract.deployed();
  await sleep(5000);
  console.log("Moola Deployed at:", moola.address);
}

// deployFactory: Deploys the Factory (game engine) contract.
// Constructor arg: moola.address -- the Factory needs a reference to the MOOLA token
// so it can mint MOOLA when players claim their accumulated earnings.
async function deployFactory() {
  console.log("Starting Factory Deployment");
  const factoryArtifact = await ethers.getContractFactory("Factory");
  const factoryContract = await factoryArtifact.deploy(moola.address, {
    gasPrice: ethers.gasPrice,
  });
  factory = await factoryContract.deployed();
  await sleep(5000);
  console.log("Factory Deployed at:", factory.address);
}

// deployPlugin: Deploys the Wheel (spin-to-win) plugin contract.
// Constructor args (in order):
//   1. WBERA_ADDRESS      - Wrapped BERA; the token players pay to spin the wheel
//   2. MULTISIG_ADDRESS   - Incentives recipient (testnet uses single multisig for all recipients)
//   3. MULTISIG_ADDRESS   - Treasury recipient (same multisig -- testnet simplification)
//   4. MULTISIG_ADDRESS   - Developer recipient (same multisig -- testnet simplification)
//   5. MULTISIG_ADDRESS   - Community recipient (same multisig -- testnet simplification)
//   6. factory.address    - Reference to the Factory so the Wheel can interact with game state
//   7. moola.address      - Reference to the MOOLA token so the Wheel can mint spin rewards
//   8. VAULT_FACTORY_ADDRESS - Berachain RewardVaultFactory; creates a BGT reward vault for the Wheel
//   9. PYTH_ENTROPY_ADDRESS  - Pyth Entropy; provides verifiable on-chain randomness for spin outcomes
//
// Note: On mainnet, args 2-5 are four distinct addresses. On testnet they are all MULTISIG_ADDRESS.
async function deployPlugin() {
  console.log("Starting Plugin Deployment");
  const pluginArtifact = await ethers.getContractFactory("Wheel");
  const pluginContract = await pluginArtifact.deploy(
    WBERA_ADDRESS,
    MULTISIG_ADDRESS,
    MULTISIG_ADDRESS,
    MULTISIG_ADDRESS,
    MULTISIG_ADDRESS,
    factory.address,
    moola.address,
    VAULT_FACTORY_ADDRESS,
    PYTH_ENTROPY_ADDRESS,
    {
      gasPrice: ethers.gasPrice,
    }
  );
  plugin = await pluginContract.deployed();
  await sleep(5000);
  console.log("Plugin Deployed at:", plugin.address);
}

// deployMulticall: Deploys the read-only Multicall helper contract.
// Constructor args:
//   1. WBERA_ADDRESS   - WBERA token address for price/balance lookups
//   2. moola.address   - MOOLA token address for balance lookups
//   3. factory.address - Factory address for aggregating player/game data
//   4. plugin.address  - Wheel address for aggregating spin/reward data
// The frontend uses Multicall to batch multiple view calls into a single RPC request.
async function deployMulticall() {
  console.log("Starting Multicall Deployment");
  const multicallArtifact = await ethers.getContractFactory("Multicall");
  const multicallContract = await multicallArtifact.deploy(
    WBERA_ADDRESS,
    moola.address,
    factory.address,
    plugin.address,
    {
      gasPrice: ethers.gasPrice,
    }
  );
  multicall = await multicallContract.deployed();
  console.log("Multicall Deployed at:", multicall.address);
}

// printDeployment: Logs all deployed contract addresses (including Bullas NFT)
// and the auto-created Berachain reward vault / vault token addresses for easy reference.
async function printDeployment() {
  console.log("**************************************************************");
  console.log("Moola: ", moola.address);
  console.log("Bullas: ", bullas.address);
  console.log("Factory: ", factory.address);
  console.log("Plugin: ", plugin.address);
  console.log("Multicall: ", multicall.address);
  console.log("Reward Vault: ", await plugin.rewardVault());
  console.log("Vault Token: ", await plugin.vaultToken());
  console.log("**************************************************************");
}

// verifyMoola: Submits the Moola contract source to the block explorer for verification.
async function verifyMoola() {
  await hre.run("verify:verify", {
    address: moola.address,
    constructorArguments: [],
  });
}

// verifyBullas: Submits the Bullas NFT contract source for block explorer verification.
// Only needed on testnet since Bullas was deployed here (not on mainnet).
async function verifyBullas() {
  await hre.run("verify:verify", {
    address: bullas.address,
    constructorArguments: [],
  });
}

// verifyFactory: Submits the Factory contract source for block explorer verification.
async function verifyFactory() {
  await hre.run("verify:verify", {
    address: factory.address,
    constructorArguments: [moola.address],
  });
}

// verifyPlugin: Submits the Wheel contract source for block explorer verification.
// Note: all four fee recipient args are the same MULTISIG_ADDRESS (testnet simplification).
async function verifyPlugin() {
  await hre.run("verify:verify", {
    address: plugin.address,
    constructorArguments: [
      WBERA_ADDRESS,
      MULTISIG_ADDRESS,
      MULTISIG_ADDRESS,
      MULTISIG_ADDRESS,
      MULTISIG_ADDRESS,
      factory.address,
      moola.address,
      VAULT_FACTORY_ADDRESS,
      PYTH_ENTROPY_ADDRESS,
    ],
  });
}

// verifyMulticall: Submits the Multicall contract source for block explorer verification.
async function verifyMulticall() {
  await hre.run("verify:verify", {
    address: multicall.address,
    constructorArguments: [
      WBERA_ADDRESS,
      moola.address,
      factory.address,
      plugin.address,
    ],
  });
}

// setUpSystem: Grants minter permissions on the MOOLA token to the Factory and Wheel.
//   - Factory needs minter rights so it can mint MOOLA when players claim their accumulated earnings.
//   - Wheel (plugin) needs minter rights so it can mint MOOLA as spin rewards when players win.
// Without these permissions, both contracts would revert on any mint attempt.
async function setUpSystem(wallet) {
  console.log("Starting System Set Up");
  // Grant the Factory contract permission to mint MOOLA (used when players claim earnings)
  await moola.connect(wallet).setMinter(factory.address, true);
  console.log("factory whitelisted to mint moola.");
  // Grant the Wheel contract permission to mint MOOLA (used as spin-to-win rewards)
  await moola.connect(wallet).setMinter(plugin.address, true);
  console.log("plugin whitelisted to mint moola.");
  console.log("System Initialized");
}

// setTools: Configures the 20 in-game tools (buildings) that players can purchase.
// Each tool has two parameters:
//   - UPS (Units Per Second): the MOOLA earning rate this tool generates per second
//   - Cost: the MOOLA price to buy the first copy of this tool
//
// Tools are ordered from cheapest/slowest (Tool 0) to most expensive/fastest (Tool 19).
// The UPS-to-Cost ratio generally stays consistent, rewarding players who save up for
// higher-tier tools with slightly better efficiency.
//
// Tool index:  UPS rate         |  MOOLA cost
// -----------------------------------------
// Tool  0:     0.0001 UPS       |  1 MOOLA
// Tool  1:     0.0002 UPS       |  2 MOOLA
// Tool  2:     0.0003 UPS       |  3 MOOLA
// Tool  3:     0.0004 UPS       |  4 MOOLA
// Tool  4:     0.0005 UPS       |  5 MOOLA
// Tool  5:     0.0006 UPS       |  8 MOOLA
// Tool  6:     0.0007 UPS       |  11 MOOLA
// Tool  7:     0.0008 UPS       |  15 MOOLA
// Tool  8:     0.001  UPS       |  20 MOOLA
// Tool  9:     0.0027 UPS       |  50 MOOLA
// Tool 10:     0.005  UPS       |  100 MOOLA
// Tool 11:     0.0075 UPS       |  150 MOOLA
// Tool 12:     0.015  UPS       |  300 MOOLA
// Tool 13:     0.025  UPS       |  500 MOOLA
// Tool 14:     0.1    UPS       |  1,500 MOOLA
// Tool 15:     0.2    UPS       |  5,000 MOOLA
// Tool 16:     0.3    UPS       |  15,000 MOOLA
// Tool 17:     0.4    UPS       |  60,000 MOOLA
// Tool 18:     0.5    UPS       |  250,000 MOOLA
// Tool 19:     1.0    UPS       |  1,000,000 MOOLA
async function setTools(wallet) {
  console.log("Starting Building Deployment");
  // buildingUps: MOOLA earned per second for each tool (index 0-19)
  const buildingUps = [
    convert("0.0001", 18),
    convert("0.0002", 18),
    convert("0.0003", 18),
    convert("0.0004", 18),
    convert("0.0005", 18),
    convert("0.0006", 18),
    convert("0.0007", 18),
    convert("0.0008", 18),
    convert("0.001", 18),
    convert("0.0027", 18),
    convert("0.005", 18),
    convert("0.0075", 18),
    convert("0.015", 18),
    convert("0.025", 18),
    convert("0.1", 18),
    convert("0.2", 18),
    convert("0.3", 18),
    convert("0.4", 18),
    convert("0.5", 18),
    convert("1", 18),
  ];
  // buildingCost: Base MOOLA cost to purchase the first copy of each tool (index 0-19)
  // Subsequent copies of the same tool cost more, scaled by the tool multipliers (see setToolMultipliers)
  const buildingCost = [
    convert("1", 18),
    convert("2", 18),
    convert("3", 18),
    convert("4", 18),
    convert("5", 18),
    convert("8", 18),
    convert("11", 18),
    convert("15", 18),
    convert("20", 18),
    convert("50", 18),
    convert("100", 18),
    convert("150", 18),
    convert("300", 18),
    convert("500", 18),
    convert("1500", 18),
    convert("5000", 18),
    convert("15000", 18),
    convert("60000", 18),
    convert("250000", 18),
    convert("1000000", 18),
  ];
  await factory.connect(wallet).setTool(buildingUps, buildingCost);
  console.log("Buildings set");
}

// setToolMultipliers: Configures the cost scaling curve for purchasing multiple copies of the same tool.
// Each entry represents the cost multiplier for the Nth copy of any tool.
//   - Index 0 = 1st copy:  multiplier 1.0x    (base cost)
//   - Index 1 = 2nd copy:  multiplier 1.15x   (15% more expensive)
//   - Index 2 = 3rd copy:  multiplier 1.3225x  (1.15 * 1.15)
//   - ...and so on, compounding at 15% per additional copy.
//
// Formula: multiplier[n] = 1.15^n
// This creates an exponential cost curve that discourages hoarding a single tool type
// and encourages players to diversify across different tools.
// The array contains 100 entries, supporting up to 100 copies of each tool.
async function setToolMultipliers(wallet) {
  console.log("Starting Multiplier Deployment");
  // buildingMultipliers: 100 entries of 1.15^n compounding cost multipliers (index 0 = 1x, index 99 = ~1,021,142x)
  const buildingMultipliers = [
    convert("1", 18),
    convert("1.15", 18),
    convert("1.3225", 18),
    convert("1.520875", 18),
    convert("1.74900625", 18),
    convert("2.011357188", 18),
    convert("2.313060766", 18),
    convert("2.66001988", 18),
    convert("3.059022863", 18),
    convert("3.517876292", 18),
    convert("4.045557736", 18),
    convert("4.652391396", 18),
    convert("5.350250105", 18),
    convert("6.152787621", 18),
    convert("7.075705764", 18),
    convert("8.137061629", 18),
    convert("9.357620874", 18),
    convert("10.761264", 18),
    convert("12.37545361", 18),
    convert("14.23177165", 18),
    convert("16.36653739", 18),
    convert("18.821518", 18),
    convert("21.6447457", 18),
    convert("24.89145756", 18),
    convert("28.62517619", 18),
    convert("32.91895262", 18),
    convert("37.85679551", 18),
    convert("43.53531484", 18),
    convert("50.06561207", 18),
    convert("57.57545388", 18),
    convert("66.21177196", 18),
    convert("76.14353775", 18),
    convert("87.56506841", 18),
    convert("100.6998287", 18),
    convert("115.804803", 18),
    convert("133.1755234", 18),
    convert("153.1518519", 18),
    convert("176.1246297", 18),
    convert("202.5433242", 18),
    convert("232.9248228", 18),
    convert("267.8635462", 18),
    convert("308.0430782", 18),
    convert("354.2495399", 18),
    convert("407.3869709", 18),
    convert("468.4950165", 18),
    convert("538.769269", 18),
    convert("619.5846593", 18),
    convert("712.5223582", 18),
    convert("819.400712", 18),
    convert("942.3108188", 18),
    convert("1083.657442", 18),
    convert("1246.206058", 18),
    convert("1433.136966", 18),
    convert("1648.107511", 18),
    convert("1895.323638", 18),
    convert("2179.622184", 18),
    convert("2506.565512", 18),
    convert("2882.550338", 18),
    convert("3314.932889", 18),
    convert("3812.172822", 18),
    convert("4383.998746", 18),
    convert("5041.598558", 18),
    convert("5797.838341", 18),
    convert("6667.514092", 18),
    convert("7667.641206", 18),
    convert("8817.787387", 18),
    convert("10140.4555", 18),
    convert("11661.52382", 18),
    convert("13410.75239", 18),
    convert("15422.36525", 18),
    convert("17735.72004", 18),
    convert("20396.07804", 18),
    convert("23455.48975", 18),
    convert("26973.81321", 18),
    convert("31019.8852", 18),
    convert("35672.86798", 18),
    convert("41023.79817", 18),
    convert("47177.3679", 18),
    convert("54253.97308", 18),
    convert("62392.06904", 18),
    convert("71750.8794", 18),
    convert("82513.51131", 18),
    convert("94890.53801", 18),
    convert("109124.1187", 18),
    convert("125492.7365", 18),
    convert("144316.647", 18),
    convert("165964.144", 18),
    convert("190858.7656", 18),
    convert("219487.5805", 18),
    convert("252410.7176", 18),
    convert("290272.3252", 18),
    convert("333813.174", 18),
    convert("383885.1501", 18),
    convert("441467.9226", 18),
    convert("507688.111", 18),
    convert("583841.3276", 18),
    convert("671417.5268", 18),
    convert("772130.1558", 18),
    convert("887949.6792", 18),
    convert("1021142.131", 18),
  ];
  await factory.connect(wallet).setToolMultipliers(buildingMultipliers);
  console.log("Multipliers set");
}

// setLevels: Configures the 6 player progression levels.
// Each level has two parameters:
//   - Unlock threshold: cumulative MOOLA that must be earned/claimed to reach this level
//   - Cost multiplier: a percentage discount/surcharge applied to tool purchases at this level
//
// Level 0: threshold =         0 MOOLA, cost multiplier =   0% (starter level, no bonus)
// Level 1: threshold =        10 MOOLA, cost multiplier =   1%
// Level 2: threshold =        50 MOOLA, cost multiplier =   5%
// Level 3: threshold =       500 MOOLA, cost multiplier =  25%
// Level 4: threshold =    50,000 MOOLA, cost multiplier =  50%
// Level 5: threshold = 5,000,000 MOOLA, cost multiplier = 100%
//
// Higher levels unlock access to better tools and provide increasing cost efficiency.
async function setLevels(wallet) {
  console.log("Starting Level Deployment");
  await factory
    .connect(wallet)
    .setLvl(
      ["0", "10", "50", "500", "50000", "5000000"],
      [0, 1, 5, 25, 50, 100]
    );
  console.log("Levels set");
}

// transferOwnership: Transfers ownership of all three ownable contracts
// (Moola, Factory, Wheel) from the deployer wallet to the MULTISIG_ADDRESS.
// This is a critical security step -- once ownership is transferred, only the multisig
// can perform admin actions (e.g., updating tools, adjusting fees, pausing contracts).
// On testnet all three go to the same MULTISIG_ADDRESS (on mainnet they go to TREASURY_ADDRESS).
// The 5-second sleep between transfers ensures each transaction is confirmed before the next.
async function transferOwnership(wallet) {
  await moola.connect(wallet).transferOwnership(MULTISIG_ADDRESS);
  console.log("Moola ownership transferred to multisig");
  await sleep(5000);
  await factory.connect(wallet).transferOwnership(MULTISIG_ADDRESS);
  console.log("Factory ownership transferred to multisig");
  await sleep(5000);
  await plugin.connect(wallet).transferOwnership(MULTISIG_ADDRESS);
  console.log("Plugin ownership transferred to multisig");
}

// main: Orchestrates the full deployment and configuration sequence.
//
// Deployment order (when all steps are active):
//   1. deployMoola()          - Deploy the MOOLA token first (other contracts depend on it)
//   2. deployBullas()         - Deploy the Bullas NFT (testnet only; pre-existing on mainnet)
//   3. deployFactory()        - Deploy the Factory (needs moola.address)
//   4. deployPlugin()         - Deploy the Wheel (needs factory.address and moola.address)
//   5. deployMulticall()      - Deploy the Multicall helper (needs all contract addresses above)
//   6. printDeployment()      - Log all addresses for the deployment record
//   7. verifyX()              - Verify each contract's source on the block explorer
//   8. setUpSystem()          - Grant minter permissions to Factory and Wheel
//   9. setTools()             - Configure the 20 tools with UPS rates and MOOLA costs
//  10. setToolMultipliers()   - Configure the 15% compounding cost curve (100 entries)
//  11. setLevels()            - Configure the 6 player levels with thresholds and multipliers
//  12. transferOwnership()    - Hand off all contract ownership to the multisig
//  13. setPlayPrice()         - Set the BERA cost per Wheel spin (3.3 BERA in wei)
//  14. setWheelSize()         - Set the number of segments on the Wheel (300)
//
// Most steps are commented out because deployment is done incrementally --
// uncomment each step as needed and re-run the script. getContracts() is used
// to re-attach to already-deployed contracts between runs.
async function main() {
  const [wallet] = await ethers.getSigners();

  console.log("Using wallet: ", wallet.address);

  // Re-attach to already-deployed contracts (used for post-deploy configuration steps)
  await getContracts();

  // --- Step 1-5: Initial contract deployments (already completed, so commented out) ---
  // await deployMoola();
  // await deployBullas();
  // await deployFactory();
  // await deployPlugin();
  // await deployMulticall();
  // await printDeployment();

  // --- Step 6: Source verification on the block explorer (already completed) ---
  // await verifyMoola();
  // await verifyBullas();
  // await verifyFactory();
  // await verifyPlugin();
  // await verifyMulticall();

  // --- Step 7-10: System configuration (already completed) ---
  // await setUpSystem(wallet);
  // await setTools(wallet);
  // await setToolMultipliers(wallet);
  // await setLevels(wallet);

  // console.log("starting transactions");

  // --- Step 11: Ownership transfer to multisig (already completed) ---
  // await transferOwnership(wallet);

  // --- Step 12: Set the BERA cost per Wheel spin to 3.3 BERA (in wei) ---
  // await plugin.setPlayPrice("3300000000000000000");
  // --- Step 13: Set the Wheel to 300 segments (determines prize distribution granularity) ---
  // await plugin.setWheelSize(300);

  // console.log("transactions complete");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
