const convert = (amount, decimals) => ethers.utils.parseUnits(amount, decimals);
const divDec = (amount, decimals = 18) => amount / 10 ** decimals;
const divDec6 = (amount, decimals = 6) => amount / 10 ** decimals;
const { expect } = require("chai");
const { ethers, network } = require("hardhat");
const { execPath } = require("process");

const AddressZero = "0x0000000000000000000000000000000000000000";
const pointZeroOne = convert("0.01", 18);
const price = convert("0.69", 18);
const price2 = convert("1.38", 18);
const price10 = convert("6.9", 18);
const price100 = convert("69", 18);
const one = convert("1", 18);
const ten = convert("10", 18);
const oneHundred = convert("100", 18);

let owner, treasury, user0, user1, user2, user3, user4, developer;
let base, voter;
let moola, bullas, factory, plugin, multicall, vaultFactory;
let moola2, factory2, multicall2;

describe("local: test0", function () {
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
    factory = await factoryArtifact.deploy(moola.address);
    console.log("- Factory Initialized");

    moola2 = await moolaArtifact.deploy();
    console.log("- Moola2 Initialized");

    factory2 = await factoryArtifact.deploy(moola2.address);
    console.log("- Factory2 Initialized");

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
      vaultFactory.address
    );
    console.log("- Plugin Initialized");

    const multicallArtifact = await ethers.getContractFactory("Multicall");
    multicall = await multicallArtifact.deploy(
      base.address,
      moola.address,
      factory.address,
      plugin.address,
      AddressZero
    );
    console.log("- Multicall Initialized");

    multicall2 = await multicallArtifact.deploy(
      base.address,
      moola2.address,
      factory2.address,
      plugin.address,
      AddressZero
    );
    console.log("- Multicall2 Initialized");

    await moola.setMinter(factory.address, true);
    await moola2.setMinter(factory2.address, true);
    await moola.setMinter(plugin.address, true);
    await moola2.setMinter(plugin.address, true);
    await voter.setPlugin(plugin.address);
    console.log("- System set up");

    console.log("Initialization Complete");
    console.log();
  });

  it("User0 mints a clicker", async function () {
    console.log("******************************************************");
    await bullas.connect(user0).mint();
    await bullas.connect(user1).mint();
    console.log("User0 has ", await bullas.balanceOf(user0.address), " bullas");
    console.log(
      "User0 has Token ID: ",
      await bullas.tokenOfOwnerByIndex(user0.address, 0)
    );
    console.log("User1 has ", await bullas.balanceOf(user1.address), " bullas");
    console.log(
      "User1 has Token ID: ",
      await bullas.tokenOfOwnerByIndex(user1.address, 0)
    );
  });

  it("User0 clicks cookie", async function () {
    console.log("******************************************************");

    await multicall
      .connect(user0)
      .click(user0.address, 1, "this is a message", {
        value: price,
      });

    await expect(
      multicall.connect(user0).click(user0.address, 1, "this is a message", {
        value: pointZeroOne,
      })
    ).to.be.reverted;

    await multicall
      .connect(user0)
      .click(user0.address, 1, "this is a message", {
        value: price,
      });

    await multicall
      .connect(user0)
      .click(user0.address, 2, "this is a message", {
        value: price2,
      });
  });

  it("Owner sets tools", async function () {
    console.log("******************************************************");
    await factory
      .connect(owner)
      .setTool(
        [
          ethers.utils.parseUnits("0.0000001", 18),
          ethers.utils.parseUnits("0.000001", 18),
          ethers.utils.parseUnits("0.000008", 18),
          ethers.utils.parseUnits("0.000047", 18),
          ethers.utils.parseUnits("0.00026", 18),
          ethers.utils.parseUnits("0.0014", 18),
        ],
        [
          ethers.utils.parseUnits("0.000015", 18),
          ethers.utils.parseUnits("0.0001", 18),
          ethers.utils.parseUnits("0.0011", 18),
          ethers.utils.parseUnits("0.012", 18),
          ethers.utils.parseUnits("0.13", 18),
          ethers.utils.parseUnits("1.4", 18),
        ]
      );
  });

  it("Owner sets tool multipliers", async function () {
    console.log("******************************************************");
    await factory.connect(owner).setToolMultipliers([
      "1000000000000000000", // 1
      "1150000000000000000", // 2
      "1322500000000000000", // 3
      "1520875000000000000", // 4
      "1749006250000000000", // 5
      "2011357187500000000", // 6
      "2313060768750000000", // 7
      "2660019884062500000", // 8
      "3059022867265625000", // 9
      "3517876297355468750", // 10
      "4045557736969289062",
      "4652391392514672421",
      "5350250105891873285",
      "6152787621674654277",
      "7075705764925852415",
      "8137061629665738723",
      "9357620874116591137",
      "10761264009734079868",
      "12375453609734181844",
      "14231771647954150830", // 20
      "16366537393147273455",
      "18821517902019348493",
      "21644745787322255767",
      "24891457556820594132",
      "28625176193143683252",
      "32918952612105216229",
      "37856795515121028664",
      "43535314841394182944",
      "50065612067598320385",
      "57575453877633198463", // 30
      "66211771960298198222",
      "76143537754252997955",
      "87565068417320947649",
      "10069982869941708939",
      "11580480300432965283",
      "13317552345497960076",
      "15315185197222654087",
      "17612462976706053100",
      "20254332423211961060",
      "23292482286663755219", // 40
    ]);
  });

  it("User0 purchases tool", async function () {
    console.log("******************************************************");
    await factory.connect(user0).purchaseTool(user0.address, 0, 1);
  });

  it("Forward 2 hour", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [7200]);
    await network.provider.send("evm_mine");
  });

  it("User0 claims moola", async function () {
    console.log("******************************************************");
    await factory.connect(user0).claim(user0.address);
  });

  it("User0 purchases tool", async function () {
    console.log("******************************************************");
    await factory.connect(user0).purchaseTool(user0.address, 0, 5);
  });

  it("Owner sets levels", async function () {
    console.log("******************************************************");
    await factory
      .connect(owner)
      .setLvl(["0", "10", "50", "500"], [0, 1, 5, 25]);
  });

  it("User0 building1 state", async function () {
    console.log("******************************************************");
    console.log("USER0 STATE");
    console.log(await multicall.getFactory(user0.address));
  });

  it("User0 building1 state", async function () {
    console.log("******************************************************");
    console.log("USER0 STATE");
    console.log(await multicall.getFactory(user0.address));
    console.log(await multicall.getUpgrades(user0.address));
    console.log(await multicall.getTools(user0.address));
  });

  it("User0 upgrades building0", async function () {
    console.log("******************************************************");
    await factory.connect(user0).upgradeTool(user0.address, 0);
  });

  it("User0 purchases building", async function () {
    console.log("******************************************************");
    await factory.connect(user0).purchaseTool(user0.address, 0, 4);
  });

  it("User0 building1 state", async function () {
    console.log("******************************************************");
    console.log("USER0 STATE");
    console.log(await multicall.getFactory(user0.address));
    console.log(await multicall.getUpgrades(user0.address));
    console.log(await multicall.getTools(user0.address));
  });

  it("Forward 2 hour", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [7200]);
    await network.provider.send("evm_mine");
  });

  it("User0 upgrades building0", async function () {
    console.log("******************************************************");
    await factory.connect(user0).upgradeTool(user0.address, 0);
  });

  it("User0 state", async function () {
    console.log("******************************************************");
    console.log("USER0 STATE");
    console.log(await multicall.getFactory(user0.address));
    console.log(await multicall.getUpgrades(user0.address));
    console.log(await multicall.getTools(user0.address));
  });

  it("Get id of owner", async function () {
    console.log("******************************************************");
    console.log(await bullas.tokenOfOwnerByIndex(user0.address, 0));
  });

  it("Forward 2 hour", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [7200]);
    await network.provider.send("evm_mine");
  });

  it("User0 building1 state", async function () {
    console.log("******************************************************");
    console.log("USER0 STATE");
    console.log(await multicall.getFactory(user0.address));
    console.log(await multicall.getUpgrades(user0.address));
    console.log(await multicall.getTools(user0.address));
  });

  it("User0 upgrades building0", async function () {
    console.log("******************************************************");
    await factory.connect(user0).purchaseTool(user0.address, 3, 1);
  });

  it("User0 building1 state", async function () {
    console.log("******************************************************");
    console.log("USER0 STATE");
    console.log(await multicall.getFactory(user0.address));
    console.log(await multicall.getUpgrades(user0.address));
    console.log(await multicall.getTools(user0.address));
  });

  it("Forward 2 hour", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [7200]);
    await network.provider.send("evm_mine");
  });

  it("User0 building1 state", async function () {
    console.log("******************************************************");
    console.log("USER0 STATE");
    console.log(await multicall.getFactory(user0.address));
    console.log(await multicall.getUpgrades(user0.address));
    console.log(await multicall.getTools(user0.address));
  });

  it("User0 building id 1 costs", async function () {
    console.log("******************************************************");
    console.log(await factory.getMultipleToolCost(0, 10, 15));
    console.log(await multicall.getMultipleToolCost(user0.address, 0, 5));
    console.log(await factory.getMultipleToolCost(0, 10, 27));
    console.log(await multicall.getMultipleToolCost(user0.address, 0, 17));
  });

  it("Forward 8 hour", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [4 * 7200]);
    await network.provider.send("evm_mine");
  });

  it("Forward Time 8 hours", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [4 * 7200]);
  });

  it("User0 purchases building1", async function () {
    console.log("******************************************************");
    await factory.connect(user0).purchaseTool(user0.address, 1, 10);
  });

  it("Forward Time 8 hours", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [4 * 7200]);
  });

  it("User0 purchases building2", async function () {
    console.log("******************************************************");
    await factory.connect(user0).purchaseTool(user0.address, 2, 10);
  });

  it("Forward Time 8 hours", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [4 * 7200]);
  });

  it("User0 purchases building3", async function () {
    console.log("******************************************************");
    await factory.connect(user0).purchaseTool(user0.address, 3, 9);
  });

  it("Forward Time 8 hours", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [4 * 7200]);
  });

  it("User0 purchases building4", async function () {
    console.log("******************************************************");
    await factory.connect(user0).purchaseTool(user0.address, 4, 10);
  });

  it("Forward Time 8 hours", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [4 * 7200]);
  });

  it("User0 purchases building5", async function () {
    console.log("******************************************************");
    await factory.connect(user0).purchaseTool(user0.address, 5, 10);
  });

  it("User0 building1 state", async function () {
    console.log("******************************************************");
    console.log("USER0 STATE");
    console.log(await multicall.getFactory(user0.address));
    console.log(await multicall.getTools(user0.address));
  });

  it("User0 building1 state", async function () {
    console.log("******************************************************");
    console.log("USER0 STATE");
    console.log(await multicall.getFactory(user0.address));
    console.log(await multicall.getTools(user0.address));
  });

  it("User0 purchases building0", async function () {
    console.log("******************************************************");
    await factory.connect(user0).purchaseTool(user0.address, 0, 20);
  });

  it("User0 building1 state", async function () {
    console.log("******************************************************");
    console.log("USER0 STATE");
    console.log(await multicall.getFactory(user0.address));
    console.log(await multicall.getUpgrades(user0.address));
    console.log(await multicall.getTools(user0.address));
  });

  it("User0 purchases building0", async function () {
    console.log("******************************************************");
    await factory.connect(user0).purchaseTool(user0.address, 1, 10);
  });

  it("User0 purchases building0", async function () {
    console.log("******************************************************");
    await factory.connect(user0).purchaseTool(user0.address, 1, 10);
  });

  it("User0 purchases building0", async function () {
    console.log("******************************************************");
    await factory.connect(user0).purchaseTool(user0.address, 2, 8);
  });

  it("User0 building1 state", async function () {
    console.log("******************************************************");
    console.log("USER0 STATE");
    console.log(await multicall.getFactory(user0.address));
    console.log(await multicall.getUpgrades(user0.address));
    console.log(await multicall.getTools(user0.address));
  });

  it("Forward 8 hour", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [4 * 7200]);
    await network.provider.send("evm_mine");
  });

  it("User0 bakery state", async function () {
    console.log("******************************************************");
    console.log("USER0 STATE");
    console.log(await multicall.getFactory(user0.address));
  });

  it("User0 sets booster", async function () {
    console.log("******************************************************");
    await factory.setBooster(bullas.address);
  });

  it("User0 clicks cookie", async function () {
    console.log("******************************************************");

    await multicall
      .connect(user0)
      .click(user0.address, 1, "this is a message", {
        value: price,
      });

    await multicall
      .connect(user0)
      .click(user0.address, 1, "this is a message", {
        value: price,
      });

    await multicall
      .connect(user0)
      .click(user0.address, 1, "this is a message", {
        value: price,
      });
  });

  it("User0 clicks cookie", async function () {
    console.log("******************************************************");

    await multicall
      .connect(user0)
      .click(user0.address, 2, "this is a message", {
        value: price2,
      });

    await multicall
      .connect(user0)
      .click(user0.address, 2, "this is a message", {
        value: price2,
      });

    await multicall
      .connect(user0)
      .click(user0.address, 2, "this is a message", {
        value: price2,
      });
  });

  it("Forward 100 seconds", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [100]);
    await network.provider.send("evm_mine");
  });

  it("User0 mints a clicker", async function () {
    console.log("******************************************************");
    await bullas.connect(user2).mint();
    console.log("User0 has ", await bullas.balanceOf(user0.address), " bullas");
    console.log(
      "User0 has Token ID: ",
      await bullas.tokenOfOwnerByIndex(user0.address, 0)
    );
    console.log("User1 has ", await bullas.balanceOf(user1.address), " bullas");
    console.log(
      "User1 has Token ID: ",
      await bullas.tokenOfOwnerByIndex(user1.address, 0)
    );
    console.log("User2 has ", await bullas.balanceOf(user2.address), " bullas");
    console.log(
      "User2 has Token ID: ",
      await bullas.tokenOfOwnerByIndex(user2.address, 0)
    );
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");
    let price = await plugin.getPrice();
    await multicall
      .connect(user3)
      .click(user0.address, 10, "this is a message", {
        value: price10,
      });

    await multicall
      .connect(user1)
      .click(user1.address, 10, "this is a message", {
        value: price10,
      });

    await multicall
      .connect(user2)
      .click(user2.address, 10, "this is a message", {
        value: price10,
      });
  });

  it("View Queue", async function () {
    console.log("******************************************************");
    console.log(await plugin.getQueue());
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Count: ", await plugin.count());
  });

  it("Queue Data 2", async function () {
    console.log("******************************************************");
    console.log(await plugin.getQueueSize());
  });

  it("Queue Data 3", async function () {
    console.log("******************************************************");
    console.log(await plugin.getQueueFragment(0, 10));
  });

  it("Claim and distro from plugin", async function () {
    console.log("******************************************************");
    console.log("Treasury Balance: ", await base.balanceOf(treasury.address));
    await plugin.claimAndDistribute();
    console.log("Treasury Balance: ", await base.balanceOf(treasury.address));
  });

  it("User0 state", async function () {
    console.log("******************************************************");
    console.log("USER0 STATE");
    console.log(await multicall.getFactory(user0.address));
  });

  it("User0 state", async function () {
    console.log("******************************************************");
    console.log("USER0 STATE");
    console.log(await multicall.getFactory(user0.address));
  });

  it("User0 state", async function () {
    console.log("******************************************************");
    console.log("USER0 STATE");
    console.log(await multicall.getFactory(user0.address));
    console.log(await multicall.getUpgrades(user0.address));
    console.log(await multicall.getTools(user0.address));
  });

  it("User0 purchases tool", async function () {
    console.log("******************************************************");
    await factory.connect(user0).purchaseTool(user0.address, 2, 12);
    await factory.connect(user0).purchaseTool(user0.address, 3, 20);
    await factory.connect(user0).purchaseTool(user0.address, 4, 20);
  });

  it("Forward time 8 hours", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [8 * 3600]);
    await network.provider.send("evm_mine");
  });

  it("User0 purchases tool", async function () {
    console.log("******************************************************");
    await factory.connect(user0).purchaseTool(user0.address, 5, 20);
  });

  it("User0 building1 state", async function () {
    console.log("******************************************************");
    console.log("USER0 STATE");
    console.log(await multicall.getFactory(user0.address));
    console.log(await multicall.getTools(user0.address));
  });

  it("Forward time 8 hours", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [8 * 3600]);
    await network.provider.send("evm_mine");
  });

  it("claim", async function () {
    console.log("******************************************************");
    await factory.claim(user0.address);
  });

  it("Forward time 8 hours", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [8 * 3600]);
    await network.provider.send("evm_mine");
  });

  it("claim", async function () {
    console.log("******************************************************");
    await factory.claim(user0.address);
  });

  it("Forward time 8 hours", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [8 * 3600]);
    await network.provider.send("evm_mine");
  });

  it("User0 building1 state", async function () {
    console.log("******************************************************");
    console.log("USER0 STATE");
    console.log(await multicall.getFactory(user0.address));
    console.log(await multicall.getTools(user0.address));
  });

  it("User0 purchases tool", async function () {
    console.log("******************************************************");
    await factory.connect(user0).purchaseTool(user0.address, 0, 10);
    await factory.connect(user0).purchaseTool(user0.address, 1, 10);
    await factory.connect(user0).purchaseTool(user0.address, 2, 10);
    await factory.connect(user0).purchaseTool(user0.address, 3, 10);
    await factory.connect(user0).purchaseTool(user0.address, 4, 10);
    await factory.connect(user0).purchaseTool(user0.address, 5, 10);
  });

  it("Forward time 8 hours", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [8 * 3600]);
    await network.provider.send("evm_mine");
  });

  it("User0 purchases tool", async function () {
    console.log("******************************************************");
    await expect(
      factory.connect(user0).purchaseTool(user0.address, 4, 5)
    ).to.be.revertedWith("Factory__AmountMaxed");
  });

  it("Forward time 8 hours", async function () {
    console.log("******************************************************");
    await factory.claim(user0.address);
    await network.provider.send("evm_increaseTime", [8 * 3600]);
    await network.provider.send("evm_mine");
  });

  it("User0 purchases tool", async function () {
    console.log("******************************************************");
    await expect(
      factory.connect(user0).purchaseTool(user0.address, 5, 5)
    ).to.be.revertedWith("Factory__AmountMaxed");
  });

  it("Forward time 8 hours", async function () {
    console.log("******************************************************");
    await factory.claim(user0.address);
    await network.provider.send("evm_increaseTime", [8 * 3600]);
    await network.provider.send("evm_mine");
  });

  it("User0 purchases tool", async function () {
    console.log("******************************************************");
    await expect(
      factory.connect(user0).purchaseTool(user0.address, 6, 5)
    ).to.be.revertedWith("Factory__ToolDoesNotExist");
  });

  it("Forward time 8 hours", async function () {
    console.log("******************************************************");
    await factory.claim(user0.address);
    await network.provider.send("evm_increaseTime", [8 * 3600]);
    await network.provider.send("evm_mine");
  });

  it("User0 purchases tool", async function () {
    console.log("******************************************************");
    await expect(
      factory.connect(user0).purchaseTool(user0.address, 7, 1)
    ).to.be.revertedWith("Factory__ToolDoesNotExist");
  });

  it("Forward time 8 hours", async function () {
    console.log("******************************************************");
    await factory.claim(user0.address);
    await network.provider.send("evm_increaseTime", [8 * 3600]);
    await network.provider.send("evm_mine");
  });

  it("User0 purchases tool", async function () {
    console.log("******************************************************");
    await expect(
      factory.connect(user0).purchaseTool(user0.address, 7, 5)
    ).to.be.revertedWith("Factory__ToolDoesNotExist");
  });

  it("Forward time 8 hours", async function () {
    console.log("******************************************************");
    await factory.claim(user0.address);
    await network.provider.send("evm_increaseTime", [8 * 3600]);
    await network.provider.send("evm_mine");
  });

  it("User0 purchases tool", async function () {
    console.log("******************************************************");
    await expect(
      factory.connect(user0).purchaseTool(user0.address, 7, 5)
    ).to.be.revertedWith("Factory__ToolDoesNotExist");
  });

  it("Forward time 8 hours", async function () {
    console.log("******************************************************");
    await factory.claim(user0.address);
    await network.provider.send("evm_increaseTime", [8 * 3600]);
    await network.provider.send("evm_mine");
  });

  it("User0 upgrades building0", async function () {
    console.log("******************************************************");
    await factory.connect(user0).upgradeTool(user0.address, 0);
    await factory.connect(user0).upgradeTool(user0.address, 1);
    await factory.connect(user0).upgradeTool(user0.address, 2);
    await factory.connect(user0).upgradeTool(user0.address, 3);
  });

  it("Forward time 8 hours", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [8 * 3600]);
    await network.provider.send("evm_mine");
  });

  it("User0 upgrades building0", async function () {
    console.log("******************************************************");
    await expect(
      factory.connect(user0).upgradeTool(user0.address, 0)
    ).to.be.revertedWith("Factory__LevelMaxed");
    await factory.connect(user0).upgradeTool(user0.address, 1);
    await factory.connect(user0).upgradeTool(user0.address, 2);
    await factory.connect(user0).upgradeTool(user0.address, 3);
  });

  it("User0 upgrades building0", async function () {
    console.log("******************************************************");
    await expect(
      factory.connect(user0).upgradeTool(user0.address, 0)
    ).to.be.revertedWith("Factory__LevelMaxed");
  });

  it("User0 state", async function () {
    console.log("******************************************************");
    console.log("USER0 STATE");
    console.log(await multicall.getFactory(user0.address));
    console.log(await multicall.getUpgrades(user0.address));
    console.log(await multicall.getTools(user0.address));
  });

  it("User0 state", async function () {
    console.log("******************************************************");
    console.log("USER0 STATE");
    console.log(await multicall.getFactory(user0.address));
    console.log(await multicall.getUpgrades(user0.address));
    console.log(await multicall.getTools(user0.address));
  });

  it("User0 state", async function () {
    console.log("******************************************************");
    console.log("USER0 STATE");
    console.log(await multicall.getFactory(user0.address));
  });

  it("Forward 700 seconds", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [700]);
    await network.provider.send("evm_mine");
  });

  it("User0 clicks cookie", async function () {
    console.log("******************************************************");

    await multicall
      .connect(user0)
      .click(user0.address, 100, "this is a message", {
        value: price100,
      });

    await multicall
      .connect(user0)
      .click(user0.address, 100, "this is a message", {
        value: price100,
      });

    await multicall
      .connect(user0)
      .click(user0.address, 100, "this is a message", {
        value: price100,
      });
  });

  it("Queue Data 2", async function () {
    console.log("******************************************************");
    console.log(await plugin.getQueueSize());
  });

  it("Forward 5 hours", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [5 * 3600]);
    await network.provider.send("evm_mine");
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall
      .connect(user0)
      .click(user0.address, 100, "this is a message", {
        value: price100,
      });
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall
      .connect(user1)
      .click(user1.address, 100, "this is a message", {
        value: price100,
      });
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall
      .connect(user2)
      .click(user2.address, 100, "this is a message", {
        value: price100,
      });
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall
      .connect(user0)
      .click(user0.address, 100, "this is a message", {
        value: price100,
      });
  });

  // queue data
  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall
      .connect(user1)
      .click(user1.address, 100, "this is a message", {
        value: price100,
      });
  });

  it("Max Power Testing", async function () {
    await factory.setMaxPower(oneHundred);
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall
      .connect(user2)
      .click(user2.address, 100, "this is a message", {
        value: price100,
      });
  });

  it("Queue Data 2", async function () {
    console.log("******************************************************");
    console.log(await plugin.getQueueSize());
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall
      .connect(user0)
      .click(user0.address, 1, "this is a message", {
        value: price,
      });
    await multicall
      .connect(user1)
      .click(user1.address, 1, "this is a message", {
        value: price,
      });
    await multicall
      .connect(user2)
      .click(user2.address, 1, "this is a message", {
        value: price,
      });
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall
      .connect(user0)
      .click(user0.address, 10, "this is a message", {
        value: price10,
      });
    await multicall
      .connect(user1)
      .click(user1.address, 10, "this is a message", {
        value: price10,
      });
    await multicall
      .connect(user2)
      .click(user2.address, 10, "this is a message", {
        value: price10,
      });
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall
      .connect(user0)
      .click(user0.address, 10, "this is a message", {
        value: price10,
      });
    await multicall
      .connect(user1)
      .click(user1.address, 10, "this is a message", {
        value: price10,
      });
    await multicall
      .connect(user2)
      .click(user2.address, 10, "this is a message", {
        value: price10,
      });
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall
      .connect(user0)
      .click(user0.address, 10, "this is a message", {
        value: price10,
      });
    await multicall
      .connect(user1)
      .click(user1.address, 10, "this is a message", {
        value: price10,
      });
    await multicall
      .connect(user2)
      .click(user2.address, 10, "this is a message", {
        value: price10,
      });
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall
      .connect(user0)
      .click(user0.address, 10, "this is a message", {
        value: price10,
      });
    await multicall
      .connect(user1)
      .click(user1.address, 10, "this is a message", {
        value: price10,
      });
    await multicall
      .connect(user2)
      .click(user2.address, 10, "this is a message", {
        value: price10,
      });
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall
      .connect(user0)
      .click(user0.address, 10, "this is a message", {
        value: price10,
      });
    await multicall
      .connect(user1)
      .click(user1.address, 10, "this is a message", {
        value: price10,
      });
    await multicall
      .connect(user2)
      .click(user2.address, 10, "this is a message", {
        value: price10,
      });
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall
      .connect(user0)
      .click(user0.address, 10, "this is a message", {
        value: price10,
      });
    await multicall
      .connect(user1)
      .click(user1.address, 10, "this is a message", {
        value: price10,
      });
    await multicall
      .connect(user2)
      .click(user2.address, 10, "this is a message", {
        value: price10,
      });
  });

  it("Max Power Testing", async function () {
    await factory.setMaxPower(one);
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall
      .connect(user0)
      .click(user0.address, 10, "this is a message", {
        value: price10,
      });
    await multicall
      .connect(user1)
      .click(user1.address, 10, "this is a message", {
        value: price10,
      });
    await multicall
      .connect(user2)
      .click(user2.address, 10, "this is a message", {
        value: price10,
      });
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall
      .connect(user0)
      .click(user0.address, 10, "this is a message", {
        value: price10,
      });
    await multicall
      .connect(user1)
      .click(user1.address, 10, "this is a message", {
        value: price10,
      });
    await multicall
      .connect(user2)
      .click(user2.address, 10, "this is a message", {
        value: price10,
      });
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall
      .connect(user0)
      .click(user0.address, 10, "this is a message", {
        value: price10,
      });
    await multicall
      .connect(user1)
      .click(user1.address, 10, "this is a message", {
        value: price10,
      });
    await multicall
      .connect(user2)
      .click(user2.address, 10, "this is a message", {
        value: price10,
      });
  });

  it("Max Power Testing", async function () {
    await factory.setMaxPower(ten);
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall
      .connect(user0)
      .click(user0.address, 10, "this is a message", {
        value: price10,
      });
    await multicall
      .connect(user1)
      .click(user1.address, 10, "this is a message", {
        value: price10,
      });
    await multicall
      .connect(user2)
      .click(user2.address, 10, "this is a message", {
        value: price10,
      });
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("User0 mints a clicker", async function () {
    console.log("******************************************************");
    await bullas.connect(user4).mint();
  });

  it("User0 mints a clicker", async function () {
    console.log("******************************************************");
    await bullas.connect(user4).mint();
  });

  it("Connect new Factory and Moola", async function () {
    console.log("******************************************************");
    await plugin.setFactory(factory2.address);
    await plugin.setUnits(moola2.address);
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall2
      .connect(user0)
      .click(user0.address, 10, "this is a message", {
        value: price10,
      });
    await multicall2
      .connect(user1)
      .click(user1.address, 10, "this is a message", {
        value: price10,
      });
    await multicall2
      .connect(user2)
      .click(user2.address, 10, "this is a message", {
        value: price10,
      });
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall2
      .connect(user0)
      .click(user0.address, 10, "this is a message", {
        value: price10,
      });
    await multicall2
      .connect(user1)
      .click(user1.address, 10, "this is a message", {
        value: price10,
      });
    await multicall2
      .connect(user2)
      .click(user2.address, 10, "this is a message", {
        value: price10,
      });
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("Owner sets tools", async function () {
    console.log("******************************************************");
    await factory2
      .connect(owner)
      .setTool(
        [
          ethers.utils.parseUnits("0.0000001", 18),
          ethers.utils.parseUnits("0.000001", 18),
          ethers.utils.parseUnits("0.000008", 18),
          ethers.utils.parseUnits("0.000047", 18),
          ethers.utils.parseUnits("0.00026", 18),
          ethers.utils.parseUnits("0.0014", 18),
        ],
        [
          ethers.utils.parseUnits("0.000015", 18),
          ethers.utils.parseUnits("0.0001", 18),
          ethers.utils.parseUnits("0.0011", 18),
          ethers.utils.parseUnits("0.012", 18),
          ethers.utils.parseUnits("0.13", 18),
          ethers.utils.parseUnits("1.4", 18),
        ]
      );
  });

  it("Owner sets tool multipliers", async function () {
    console.log("******************************************************");
    await factory2.connect(owner).setToolMultipliers([
      "1000000000000000000", // 1
      "1150000000000000000", // 2
      "1322500000000000000", // 3
      "1520875000000000000", // 4
      "1749006250000000000", // 5
      "2011357187500000000", // 6
      "2313060768750000000", // 7
      "2660019884062500000", // 8
      "3059022867265625000", // 9
      "3517876297355468750", // 10
      "4045557736969289062",
      "4652391392514672421",
      "5350250105891873285",
      "6152787621674654277",
      "7075705764925852415",
      "8137061629665738723",
      "9357620874116591137",
      "10761264009734079868",
      "12375453609734181844",
      "14231771647954150830", // 20
      "16366537393147273455",
      "18821517902019348493",
      "21644745787322255767",
      "24891457556820594132",
      "28625176193143683252",
      "32918952612105216229",
      "37856795515121028664",
      "43535314841394182944",
      "50065612067598320385",
      "57575453877633198463", // 30
      "66211771960298198222",
      "76143537754252997955",
      "87565068417320947649",
      "10069982869941708939",
      "11580480300432965283",
      "13317552345497960076",
      "15315185197222654087",
      "17612462976706053100",
      "20254332423211961060",
      "23292482286663755219", // 40
    ]);
  });

  it("Owner sets levels", async function () {
    console.log("******************************************************");
    await factory2
      .connect(owner)
      .setLvl(["0", "10", "50", "500"], [0, 1, 5, 25]);
  });

  it("User0 purchases tool", async function () {
    console.log("******************************************************");
    await factory2.connect(user0).purchaseTool(user0.address, 0, 1);
  });

  it("User0 claims moola", async function () {
    console.log("******************************************************");
    await factory2.connect(user0).claim(user0.address);
  });

  it("User0 purchases tool", async function () {
    console.log("******************************************************");
    await factory2.connect(user0).purchaseTool(user0.address, 0, 5);
  });

  it("User0 building1 state", async function () {
    console.log("******************************************************");
    console.log("USER0 STATE");
    console.log(await multicall2.getFactory(user0.address));
    console.log(await multicall2.getUpgrades(user0.address));
    console.log(await multicall2.getTools(user0.address));
  });

  it("User0 upgrades building0", async function () {
    console.log("******************************************************");
    await factory2.connect(user0).upgradeTool(user0.address, 0);
  });

  it("User0 purchases building", async function () {
    console.log("******************************************************");
    await factory2.connect(user0).purchaseTool(user0.address, 0, 4);
  });

  it("Forward 2 hour", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [7200]);
    await network.provider.send("evm_mine");
  });

  it("User0 upgrades building0", async function () {
    console.log("******************************************************");
    await factory2.connect(user0).upgradeTool(user0.address, 0);
  });

  it("Get id of owner", async function () {
    console.log("******************************************************");
    console.log(await bullas.tokenOfOwnerByIndex(user0.address, 0));
  });

  it("Forward 2 hour", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [7200]);
    await network.provider.send("evm_mine");
  });

  it("User0 upgrades building0", async function () {
    console.log("******************************************************");
    await factory2.connect(user0).purchaseTool(user0.address, 3, 1);
  });

  it("Forward 2 hour", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [7200]);
    await network.provider.send("evm_mine");
  });

  it("User0 building id 1 costs", async function () {
    console.log("******************************************************");
    console.log(await factory2.getMultipleToolCost(0, 10, 15));
    console.log(await multicall2.getMultipleToolCost(user0.address, 0, 5));
    console.log(await factory2.getMultipleToolCost(0, 10, 27));
    console.log(await multicall2.getMultipleToolCost(user0.address, 0, 17));
  });

  it("Forward 8 hour", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [4 * 7200]);
    await network.provider.send("evm_mine");
  });

  it("Forward Time 8 hours", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [4 * 7200]);
  });

  it("User0 purchases building1", async function () {
    console.log("******************************************************");
    await factory2.connect(user0).purchaseTool(user0.address, 1, 10);
  });

  it("Forward Time 8 hours", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [4 * 7200]);
  });

  it("User0 purchases building4", async function () {
    console.log("******************************************************");
    await factory2.connect(user0).purchaseTool(user0.address, 4, 10);
  });

  it("Forward Time 8 hours", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [4 * 7200]);
  });

  it("User0 purchases building5", async function () {
    console.log("******************************************************");
    await factory2.connect(user0).purchaseTool(user0.address, 5, 10);
  });

  it("User0 purchases building0", async function () {
    console.log("******************************************************");
    await factory2.connect(user0).purchaseTool(user0.address, 0, 20);
  });

  it("User0 purchases building0", async function () {
    console.log("******************************************************");
    await factory2.connect(user0).purchaseTool(user0.address, 1, 10);
  });

  it("User0 purchases building0", async function () {
    console.log("******************************************************");
    await factory2.connect(user0).purchaseTool(user0.address, 1, 10);
  });

  it("User0 purchases building0", async function () {
    console.log("******************************************************");
    await factory2.connect(user0).purchaseTool(user0.address, 2, 8);
  });

  it("User0 building1 state", async function () {
    console.log("******************************************************");
    console.log("USER0 STATE");
    console.log(await multicall2.getFactory(user0.address));
    console.log(await multicall2.getUpgrades(user0.address));
    console.log(await multicall2.getTools(user0.address));
  });

  it("User0 building1 state", async function () {
    console.log("******************************************************");
    console.log("USER0 STATE");
    console.log(await multicall2.getFactory(user0.address));
  });

  it("Forward 8 hour", async function () {
    console.log("******************************************************");
    await network.provider.send("evm_increaseTime", [4 * 7200]);
    await network.provider.send("evm_mine");
  });

  it("User0 clicks cookie", async function () {
    console.log("******************************************************");

    await multicall2
      .connect(user0)
      .click(user0.address, 1, "this is a message", {
        value: price,
      });

    await multicall2
      .connect(user0)
      .click(user0.address, 1, "this is a message", {
        value: price,
      });

    await multicall2
      .connect(user0)
      .click(user0.address, 1, "this is a message", {
        value: price,
      });
  });

  it("Max Power Testing", async function () {
    await factory.setMaxPower(one);
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall2
      .connect(user0)
      .click(user0.address, 10, "this is a message", {
        value: price10,
      });
    await multicall2
      .connect(user1)
      .click(user1.address, 10, "this is a message", {
        value: price10,
      });
    await multicall2
      .connect(user2)
      .click(user2.address, 10, "this is a message", {
        value: price10,
      });
  });

  it("Claim and Distribute", async function () {
    console.log("******************************************************");
    await plugin.claimAndDistribute();
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall2
      .connect(user0)
      .click(user0.address, 10, "this is a message", {
        value: price10,
      });
    await multicall2
      .connect(user1)
      .click(user1.address, 10, "this is a message", {
        value: price10,
      });
    await multicall2
      .connect(user2)
      .click(user2.address, 10, "this is a message", {
        value: price10,
      });
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall2
      .connect(user0)
      .click(user0.address, 10, "this is a message", {
        value: price10,
      });
    await multicall2
      .connect(user1)
      .click(user1.address, 10, "this is a message", {
        value: price10,
      });
    await multicall2
      .connect(user2)
      .click(user2.address, 10, "this is a message", {
        value: price10,
      });
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("set entry price", async function () {
    console.log("******************************************************");
    await plugin.setEntryFee(one);
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall2
      .connect(user0)
      .click(user0.address, 10, "this is a message", {
        value: ten,
      });
    await multicall2
      .connect(user1)
      .click(user1.address, 10, "this is a message", {
        value: ten,
      });
    await multicall2
      .connect(user2)
      .click(user2.address, 10, "this is a message", {
        value: ten,
      });
  });

  it("Claim and Distribute", async function () {
    console.log("******************************************************");
    await plugin.claimAndDistribute();
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall2
      .connect(user0)
      .click(user0.address, 100, "this is a message", {
        value: oneHundred,
      });
    await multicall2
      .connect(user1)
      .click(user1.address, 100, "this is a message", {
        value: oneHundred,
      });
    await multicall2
      .connect(user2)
      .click(user2.address, 100, "this is a message", {
        value: oneHundred,
      });
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("Moola Testing", async function () {
    await expect(
      moola2.connect(user0).transfer(user1.address, one)
    ).to.be.revertedWith("Moola__NonTransferable()");
    await moola2.setTransferWhitelist(user0.address, true);
    await moola2.connect(user0).transfer(user1.address, one);
    await moola2.setTransferWhitelist(user0.address, false);
    await expect(
      moola2.connect(user0).transfer(user1.address, one)
    ).to.be.revertedWith("Moola__NonTransferable()");
    await moola2.setTransferable(true);
    await moola2.connect(user0).transfer(user1.address, one);
    await moola2.setTransferable(false);
    await expect(
      moola2.connect(user0).transfer(user1.address, one)
    ).to.be.revertedWith("Moola__NonTransferable()");
  });

  it("Max Power Testing", async function () {
    await factory.setMaxPower(ten);
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall2
      .connect(user0)
      .click(user0.address, 100, "this is a message", {
        value: oneHundred,
      });
    await multicall2
      .connect(user1)
      .click(user1.address, 100, "this is a message", {
        value: oneHundred,
      });
    await multicall2
      .connect(user2)
      .click(user2.address, 100, "this is a message", {
        value: oneHundred,
      });
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall2
      .connect(user0)
      .click(user0.address, 100, "this is a message", {
        value: oneHundred,
      });
    await multicall2
      .connect(user1)
      .click(user1.address, 100, "this is a message", {
        value: oneHundred,
      });
    await multicall2
      .connect(user2)
      .click(user2.address, 100, "this is a message", {
        value: oneHundred,
      });
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall2
      .connect(user0)
      .click(user0.address, 100, "this is a message", {
        value: oneHundred,
      });
    await multicall2
      .connect(user1)
      .click(user1.address, 100, "this is a message", {
        value: oneHundred,
      });
    await multicall2
      .connect(user2)
      .click(user2.address, 100, "this is a message", {
        value: oneHundred,
      });
  });

  it("Claim and Distribute", async function () {
    console.log("******************************************************");
    await plugin.claimAndDistribute();
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall2
      .connect(user0)
      .click(user0.address, 100, "this is a message", {
        value: oneHundred,
      });
    await multicall2
      .connect(user1)
      .click(user1.address, 100, "this is a message", {
        value: oneHundred,
      });
    await multicall2
      .connect(user2)
      .click(user2.address, 100, "this is a message", {
        value: oneHundred,
      });
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("Max Power Testing", async function () {
    await factory.setMaxPower(ten);
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall2
      .connect(user0)
      .click(user0.address, 100, "this is a message", {
        value: oneHundred,
      });
    await multicall2
      .connect(user1)
      .click(user1.address, 100, "this is a message", {
        value: oneHundred,
      });
    await multicall2
      .connect(user2)
      .click(user2.address, 100, "this is a message", {
        value: oneHundred,
      });
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("everyone clicks cookie", async function () {
    console.log("******************************************************");

    await multicall2
      .connect(user0)
      .click(user0.address, 100, "this is a message", {
        value: oneHundred,
      });
    await multicall2
      .connect(user1)
      .click(user1.address, 100, "this is a message", {
        value: oneHundred,
      });
    await multicall2
      .connect(user2)
      .click(user2.address, 100, "this is a message", {
        value: oneHundred,
      });
  });

  it("Claim and Distribute", async function () {
    console.log("******************************************************");
    await plugin.claimAndDistribute();
  });

  it("Queue Data", async function () {
    console.log("******************************************************");
    console.log("Head: ", await plugin.head());
    console.log("Tail: ", await plugin.tail());
    console.log("Size: ", await plugin.count());
  });

  it("Disable Spanker", async function () {
    console.log("******************************************************");
    await factory2.setDisabled(user0.address, true);
    await expect(
      multicall2.connect(user0).click(user0.address, 100, "this is a message", {
        value: oneHundred,
      })
    ).to.be.revertedWith("Factory__AccountDisabled");
  });

  it("Enable Spanker", async function () {
    console.log("******************************************************");
    await factory2.setDisabled(user0.address, false);
    await multicall2
      .connect(user0)
      .click(user0.address, 100, "this is a message", {
        value: oneHundred,
      });
  });
});
