const convert = (amount, decimals) => ethers.utils.parseUnits(amount, decimals);
const divDec = (amount, decimals = 18) => amount / 10 ** decimals;
const divDec6 = (amount, decimals = 6) => amount / 10 ** decimals;
const { expect } = require("chai");
const { ethers, network } = require("hardhat");
const { execPath } = require("process");

const AddressZero = "0x0000000000000000000000000000000000000000";
const pointZeroOne = convert("0.01", 18);
const price = convert("0.04269", 18);
const price2 = convert("0.08538", 18);
const price10 = convert("0.4269", 18);
const price100 = convert("4.269", 18);
const one = convert("1", 18);
const ten = convert("10", 18);
const oneHundred = convert("100", 18);
const oneHundredEleven = convert("111", 18);

let owner, treasury, user0, user1, user2, user3, user4, developer;
let base, voter;
let moola, bullas, factory, plugin, multicall, vaultFactory;
let claim;

describe("local: test1", function () {
  before("Initial set up", async function () {
    console.log("Begin Initialization");

    [owner, treasury, user0, user1, user2, user3, user4, developer] =
      await ethers.getSigners();

    const vaultFactoryArtifact = await ethers.getContractFactory(
      "BerachainRewardsVaultFactory"
    );
    vaultFactory = await vaultFactoryArtifact.deploy();
    console.log("- Vault Factory Initialized");

    const baseArtifact = await ethers.getContractFactory("Base");
    base = await baseArtifact.deploy();
    console.log("- BASE Initialized");

    const voterArtifact = await ethers.getContractFactory("Voter");
    voter = await voterArtifact.deploy();
    console.log("- Voter Initialized");

    const bullasArtifact = await ethers.getContractFactory("Bullas");
    bullas = await bullasArtifact.deploy();
    console.log("- Bullas Initialized");

    const moolaArtifact = await ethers.getContractFactory("Moola");
    moola = await moolaArtifact.deploy();
    console.log("- Moola Initialized");

    const factoryArtifact = await ethers.getContractFactory("Factory");
    factory = await factoryArtifact.deploy(moola.address, bullas.address);
    console.log("- Factory Initialized");

    const pluginArtifact = await ethers.getContractFactory("QueuePlugin");
    plugin = await pluginArtifact.deploy(
      base.address,
      voter.address,
      [base.address],
      [base.address],
      treasury.address,
      developer.address,
      factory.address,
      moola.address,
      bullas.address,
      vaultFactory.address
    );
    console.log("- Plugin Initialized");

    const multicallArtifact = await ethers.getContractFactory("Multicall");
    multicall = await multicallArtifact.deploy(
      base.address,
      moola.address,
      factory.address,
      bullas.address,
      plugin.address,
      AddressZero
    );
    console.log("- Multicall Initialized");

    const claimArtifact = await ethers.getContractFactory("MoolaClaim");
    claim = await claimArtifact.deploy(moola.address);
    console.log("- Claim Initialized");

    await moola.setMinter(factory.address, true);
    await moola.setMinter(plugin.address, true);
    await moola.setMinter(owner.address, true);
    await voter.setPlugin(plugin.address);
    await moola.setTransferWhitelist(claim.address, true);
    console.log("- System set up");

    console.log("Initialization Complete");
    console.log();
  });

  it("First test", async function () {
    console.log("******************************************************");
    await claim.setClaims(
      [user0.address, user1.address, user2.address],
      [one, ten, oneHundred]
    );
    await moola.mint(claim.address, oneHundredEleven);
    console.log(
      "Moola Balance of Claim: ",
      divDec(await moola.balanceOf(claim.address))
    );
  });

  it("User0 claims", async function () {
    console.log("******************************************************");
    console.log(
      "Moola Balance of Claim: ",
      divDec(await moola.balanceOf(claim.address))
    );
    console.log(
      "User0 Balance: ",
      divDec(await moola.balanceOf(user0.address))
    );
    await claim.connect(user0).claim();
    console.log(
      "Moola Balance of Claim: ",
      divDec(await moola.balanceOf(claim.address))
    );
  });

  it("User0 claims", async function () {
    console.log("******************************************************");
    console.log(
      "Moola Balance of Claim: ",
      divDec(await moola.balanceOf(claim.address))
    );
    console.log(
      "User0 Balance: ",
      divDec(await moola.balanceOf(user0.address))
    );
    await expect(claim.connect(user0).claim()).to.be.revertedWith(
      "MoolaClaim__NoClaimableAmount"
    );
    console.log(
      "Moola Balance of Claim: ",
      divDec(await moola.balanceOf(claim.address))
    );
    console.log(
      "User0 Balance: ",
      divDec(await moola.balanceOf(user0.address))
    );
  });

  it("First test", async function () {
    console.log("******************************************************");
    await claim.setClaims([user0.address], [one]);
    await moola.mint(claim.address, one);
    console.log(
      "Moola Balance of Claim: ",
      divDec(await moola.balanceOf(claim.address))
    );
  });

  it("User0 claims", async function () {
    console.log("******************************************************");
    console.log(
      "Moola Balance of Claim: ",
      divDec(await moola.balanceOf(claim.address))
    );
    console.log(
      "User0 Balance: ",
      divDec(await moola.balanceOf(user0.address))
    );
    await claim.connect(user0).claim();
    console.log(
      "Moola Balance of Claim: ",
      divDec(await moola.balanceOf(claim.address))
    );
    console.log(
      "User0 Balance: ",
      divDec(await moola.balanceOf(user0.address))
    );
  });

  it("User1 claims", async function () {
    console.log("******************************************************");
    console.log(
      "Moola Balance of Claim: ",
      divDec(await moola.balanceOf(claim.address))
    );
    console.log(
      "User1 Balance: ",
      divDec(await moola.balanceOf(user1.address))
    );
    await claim.connect(user1).claim();
    console.log(
      "Moola Balance of Claim: ",
      divDec(await moola.balanceOf(claim.address))
    );
    console.log(
      "User1 Balance: ",
      divDec(await moola.balanceOf(user1.address))
    );
  });

  it("User2 claims", async function () {
    console.log("******************************************************");
    console.log(
      "Moola Balance of Claim: ",
      divDec(await moola.balanceOf(claim.address))
    );
    console.log(
      "User2 Balance: ",
      divDec(await moola.balanceOf(user2.address))
    );
    await claim.connect(user2).claim();
    console.log(
      "Moola Balance of Claim: ",
      divDec(await moola.balanceOf(claim.address))
    );
    console.log(
      "User2 Balance: ",
      divDec(await moola.balanceOf(user2.address))
    );
  });
});
