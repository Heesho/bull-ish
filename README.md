# Bull-ish

A gamified idle-clicker DeFi protocol on Berachain. Players earn MOOLA tokens by purchasing and upgrading tools that generate passive Units Per Second (UPS), then compete on a spin-to-earn wheel that stakes their power into Berachain's Proof-of-Liquidity reward vaults.

## Table of Contents

- [Architecture](#architecture)
- [Contracts](#contracts)
  - [Moola.sol](#moolasol)
  - [Factory.sol](#factorysol)
  - [Wheel.sol](#wheelsol)
  - [Multicall.sol](#multicallsol)
  - [Bullas.sol](#bullassol)
  - [Base.sol](#basesol)
  - [BerachainRewardVaultFactory.sol](#berachainrewardvaultfactorysol)
- [Game Mechanics](#game-mechanics)
- [Fee Structure](#fee-structure)
- [Deployment](#deployment)
  - [Prerequisites](#prerequisites)
  - [Deployment Order](#deployment-order)
  - [Post-Deploy Setup](#post-deploy-setup)
  - [Contract Verification](#contract-verification)
- [Deployed Addresses](#deployed-addresses)
- [Testing](#testing)
- [Access Control](#access-control)
- [Game Reset Handoff](#game-reset-handoff)

---

## Architecture

```
+------------------+         mint          +------------------+
|                  |<----------------------|                  |
|    Moola.sol     |<-----------+          |   Factory.sol    |
|   (ERC20 token)  |            |          |  (Game engine)   |
|                  |--burn----->|          |                  |
+------------------+            |          +--------+---------+
        ^                       |                   |
        |  mint                 |  mint        getPower()
        |                      |                   |
+-------+----------+           |          +--------v---------+
|                  |-----------+          |                  |
|    Wheel.sol     |                      |   Bullas.sol     |
| (Spin-to-earn)   |-----balanceOf()----->|  (NFT booster)   |
|                  |                      |   +10% UPC       |
+-------+----------+                      +------------------+
        |
        |  delegateStake / delegateWithdraw
        v
+------------------+       creates        +------------------+
|                  |<---------------------|                  |
|   RewardVault    |                      |   VaultToken     |
| (Berachain PoL)  |                      |   (ERC20)        |
+------------------+                      +------------------+
        ^
        |  createRewardVault()
+-------+----------+
|  RewardVault     |
|  Factory         |
| (Berachain)      |
+------------------+

+------------------+       reads          +------------------+
|                  |--------------------->| Factory, Wheel,  |
|  Multicall.sol   |                      | Moola            |
| (View aggregator)|                      | (All view calls) |
+------------------+                      +------------------+

External Dependencies:
  - WBERA (0x6969...6969)            -- Wrapped BERA for fee distribution
  - Pyth Entropy (0x3682...e320)     -- Verifiable randomness for wheel spins
  - RewardVault Factory (0x94Ad...2a8) -- Berachain PoL vault creation
```

---

## Contracts

### Moola.sol

In-game ERC20 currency used to purchase and upgrade tools in the Factory.

| Property | Value |
|---|---|
| Name / Symbol | Moola / MOOLA |
| Transferable | No (by default) |
| Minting | Restricted to whitelisted minters (Factory, Wheel) |

Key features:
- **Minter whitelist** -- only addresses flagged via `setMinter()` can call `mint()` and `burn()`.
- **Transfer restrictions** -- tokens are non-transferable unless the global `transferable` flag is enabled or the sender is on the `transferWhitelist`.
- Owner can toggle `transferable`, manage the minter whitelist, and whitelist individual addresses for transfers.

### Factory.sol

Core game engine where players accumulate UPS (Units Per Second) by purchasing and upgrading tools.

| Constant | Value |
|---|---|
| `BASE_UPC` | 1 ether (1e18) |
| `DURATION` | 28800 seconds (8 hours) |
| `PRECISION` | 1 ether (1e18) |

**Tools:**
- 20 tools available, each with a `baseUps` and `baseCost`.
- Tool costs scale with quantity owned via a 15% compounding multiplier table (100 levels of multipliers).
- Cost formula: `baseCost * amount_CostMultiplier[currentAmount] / PRECISION`
- Players can purchase multiple units of a tool in a single transaction.

**Upgrades:**
- Each tool can be upgraded through 6 levels (0-5).
- UPS output doubles per level: `baseUps * 2^level`
- Upgrades require owning a minimum number of that tool (`lvl_Unlock` threshold).
- Upgrade cost: `baseCost * lvl_CostMultiplier[nextLevel]`

**Claiming:**
- Accumulated MOOLA is auto-claimed before every purchase or upgrade.
- Production is capped at 8 hours (`DURATION = 28800` seconds). Anything beyond that is forfeited.

**Power:**
- `getPower(account)` returns `upc` (units per click) and `power`.
- `upc = BASE_UPC + account_Ups`
- Bullas NFT holders receive a 10% bonus: `upc = upc * 11 / 10`
- `power = sqrt(upc * 1e18)`, capped at `maxPower`
- Disabled accounts revert on `getPower()` (anti-cheat).

### Wheel.sol

Spin-to-earn mechanism that integrates with Berachain's Proof-of-Liquidity system.

| Parameter | Default |
|---|---|
| `playPrice` | 0.69 BERA |
| `wheelSize` | 100 slots (only expandable) |
| `feeSplit` | 20% (bounded 4-30%) |

**Spin flow:**
1. Player calls `play()` with `playPrice` BERA (+ Pyth Entropy fee).
2. Pyth Entropy provides a verifiable random number (or mock fallback for testing).
3. A random wheel slot is selected (`randomNumber % wheelSize`).
4. If the slot is occupied, the previous occupant's power is unstaked via `delegateWithdraw`.
5. Player's `power` (from `Factory.getPower()`) is staked via `delegateStake` into the Berachain RewardVault.
6. Player receives `upc` amount of MOOLA as an instant reward.

**VaultToken:**
- An internal ERC20 ("BULL ISH V3") is deployed at construction.
- This token is minted/burned to represent staked power in the RewardVault.

**Revenue distribution** (`distribute()`):
- All accumulated BERA is wrapped to WBERA.
- `(100 - feeSplit)%` goes to the incentives address (default 80%).
- `feeSplit%` goes to the team (default 20%), subdivided as:
  - 40% to treasury
  - 40% to developer
  - 20% to community

### Multicall.sol

Read-only view aggregator for frontend efficiency. Batches multiple contract reads into single calls.

| Function | Returns |
|---|---|
| `getFactory(account)` | MOOLA balance, UPS, UPC, power, claimable, capacity, full status |
| `getTools(account)` | All 20 tool states: amount, cost, ups, maxed, percentOfProduction |
| `getUpgrades(account)` | Upgrade availability and cost for each tool |
| `getVault(account)` | User's vault balance and total supply |
| `getMultipleToolCost(account, toolId, amount)` | Bulk purchase cost calculation |

### Bullas.sol

Free-mint ERC721 NFT collection. Holding at least one Bullas NFT grants a 10% UPC bonus in `Factory.getPower()`.

- Auto-incrementing token IDs starting from 1.
- No supply cap, no mint restrictions.
- Uses `ERC721Enumerable` for on-chain enumeration.

### Base.sol

Mock WBERA (Wrapped BERA) contract for local Hardhat testing. Implements `deposit()`, `withdraw()`, and `receive()`. Not deployed on mainnet -- mainnet uses the native WBERA at `0x6969696969696969696969696969696969696969`.

### BerachainRewardVaultFactory.sol

Mock of Berachain's native RewardVault system for local testing. Creates simple `RewardVault` instances that track `delegateStake` and `delegateWithdraw` balances. Not deployed on mainnet -- mainnet uses the Berachain RewardVault Factory at `0x94Ad6Ac84f6C6FbA8b8CCbD71d9f4f101def52a8`.

---

## Game Mechanics

```
1. Player clicks  -->  earns BASE_UPC (1 MOOLA) + accumulated UPS as MOOLA
2. Player buys tools  -->  increases UPS (passive income rate)
3. Player upgrades tools  -->  doubles tool UPS output per level
4. Player claims  -->  collects up to 8 hours of MOOLA production
5. Player spins wheel  -->  pays 0.69 BERA, stakes power in PoL vault, earns MOOLA
6. Player holds Bullas NFT  -->  gets 10% UPC bonus
```

**Tool Pricing Curve:**

Tools use a 15% compounding cost multiplier. The first unit costs `baseCost`, the second costs `baseCost * 1.15`, the third `baseCost * 1.3225`, and so on up to 100 units.

**Power Calculation:**

```
upc = 1e18 + account_Ups
if (holds Bullas NFT): upc = upc * 1.1
power = sqrt(upc * 1e18)
if (power > maxPower): power = maxPower
```

---

## Fee Structure

```
Player pays 0.69 BERA to spin
            |
            v
      +-----+------+
      | distribute()|
      +-----+------+
            |
    wrap all BERA -> WBERA
            |
    +-------+--------+
    |                |
    v                v
  80% to          20% to team
  incentives         |
                +----+----+
                |    |    |
                v    v    v
              40%  40%  20%
            treas  dev  comm
```

- `feeSplit` is bounded between 4% and 30% (set by owner).
- Incentives address receives the remainder (100% - feeSplit).
- Team split is hardcoded: 2/5 treasury, 2/5 developer, 1/5 community.

---

## Deployment

### Prerequisites

Create a `.env` file in the project root:

```
PRIVATE_KEY=<deployer-wallet-private-key>
SCAN_API_KEY=<berascan-api-key>
RPC_URL=<berachain-rpc-endpoint>
```

Install dependencies:

```bash
yarn install
```

### Deployment Order

Contracts must be deployed in sequence due to constructor dependencies:

```
1. Moola        (no constructor args)
2. Factory      (moola)
3. Wheel        (wbera, incentives, treasury, developer, community, factory, moola, vaultFactory, pythEntropy)
4. Multicall    (wbera, moola, factory, wheel)
```

Deploy to mainnet:

```bash
npx hardhat run ./scripts/deploy.js --network mainnet
```

Deploy to Bepolia testnet:

```bash
npx hardhat run ./scripts/deployBepolia.js --network mainnet
```

### Post-Deploy Setup

After all contracts are deployed, the following configuration transactions must be executed by the deployer:

```javascript
// 1. Authorize Factory and Wheel to mint MOOLA
await moola.setMinter(factory.address, true);
await moola.setMinter(wheel.address, true);

// 2. Configure 20 tools with UPS rates and costs
await factory.setTool(buildingUps, buildingCost);

// 3. Set 100 cost multipliers (15% compounding)
await factory.setToolMultipliers(buildingMultipliers);

// 4. Set 6 upgrade levels with costs and unlock thresholds
await factory.setLvl(
  ["0", "10", "50", "500", "50000", "5000000"],  // cost multipliers
  [0, 1, 5, 25, 50, 100]                          // unlock thresholds
);

// 5. Set max power cap
await factory.setMaxPower(maxPowerValue);

// 6. Transfer ownership to multisig
await moola.transferOwnership(TREASURY_ADDRESS);
await factory.transferOwnership(TREASURY_ADDRESS);
await wheel.transferOwnership(TREASURY_ADDRESS);
```

### Contract Verification

Contracts are verified on Berascan via `@nomicfoundation/hardhat-verify`:

```bash
npx hardhat verify --network mainnet <CONTRACT_ADDRESS> [constructor args...]
```

---

## Deployed Addresses

### Mainnet -- Current (V3, Berachain, chainId 80094)

| Contract | Address | Status |
|---|---|---|
| Moola | `0xBdb8B9acd9063Cb75B6E64aEc566530cB85c2cF9` | Deployed, configured, ownership transferred to treasury |
| Factory | `0xA5db7214F7cc61c8b01AE05bD0042F50BEb46647` | Deployed, configured, ownership transferred to treasury |
| Wheel | `0xA00c4b869d2645D1aF132881c32dcD07c3AbaEd2` | **Needs multisig to call `setFactory` + `setUnits`** (see [Game Reset Handoff](#game-reset-handoff)) |
| Multicall | `0xfd8653E380b4028cA9bf2e03b3E4f4B37cC0B385` | Deployed, ready |

### Mainnet -- Previous (V2, deprecated)

| Contract | Address |
|---|---|
| Moola | `0xed8ffa14cD0664e39CC3bD64e81AB1904A90c21E` |
| Factory | `0xd4A0d12e82675bcb29F72e79D76C6d18a727e6dD` |
| Multicall | `0xF7433dB258f9363C426C2A9105A942932FDa49E6` |

### Testnet (Bepolia, chainId 80069)

| Contract | Address |
|---|---|
| Bullas | `0xa54D15bD0D3Dd39C1Cfa05C6Cd285A34B4a69BE7` |
| Moola | `0x699ce67D64b4A62EADAdfA40196FFdFF31B63dBe` |
| Factory | `0x86Fe6FCA762434BCD336c18bf8b1866C7033099A` |
| Wheel | `0x2c2014C37A749434377955Bde51579A002Fbb3F1` |
| Multicall | `0x92c222bDfC6dE0d386fe8DdAEF00869c4248b21C` |

### External Dependencies

| Dependency | Address |
|---|---|
| WBERA | `0x6969696969696969696969696969696969696969` |
| Berachain RewardVault Factory | `0x94Ad6Ac84f6C6FbA8b8CCbD71d9f4f101def52a8` |
| Pyth Entropy | `0x36825bf3Fbdf5a29E2d5148bfe7Dcf7B5639e320` |

### Mainnet Fee Recipients

| Role | Address |
|---|---|
| Incentives | `0xf99E36dcec7893e056a515cD160B007cCb1ED32E` |
| Treasury (multisig) | `0x372791b58d4b38104b106c39cc824e14c7638aac` |
| Developer | `0x2e4c3da66Da4100185Ed0Afdd059865aC1e787C3` |
| Community | `0xc8584d6c507cd4cc6bbe568251ac4ee65a27caaa` |

---

## Testing

Tests are located in `tests/test0.js` and run on a local Hardhat network using mock contracts (`Base.sol` for WBERA and `BerachainRewardVaultFactory.sol` for the vault system).

```bash
# Install dependencies
yarn install

# Run full test suite
npx hardhat test

# Run with gas reporting
npx hardhat test --gas-reporter

# Run with coverage
npx hardhat coverage
```

The test suite covers:
- Moola minting, burning, and transfer restrictions
- Factory tool purchasing, upgrading, and claiming
- Wheel spinning, slot replacement, and power staking
- Fee distribution and revenue splitting
- Multicall view aggregation
- Bullas NFT minting and UPC bonus verification
- Access control and edge cases

---

## Access Control

### Moola (Owner)
- `setMinter(address, bool)` -- add/remove minters
- `setTransferable(bool)` -- toggle global transferability
- `setTransferWhitelist(address, bool)` -- whitelist individual addresses for transfers
- `transferOwnership(address)` -- transfer contract ownership

### Factory (Owner)
- `setTool(uint256[], uint256[])` -- configure tool UPS rates and base costs
- `setToolMultipliers(uint256[])` -- set cost scaling multipliers
- `setLvl(uint256[], uint256[])` -- configure upgrade levels (costs and unlock thresholds)
- `setMaxPower(uint256)` -- set the power cap
- `setBooster(address)` -- set the NFT booster contract (Bullas)
- `setDisabled(address, bool)` -- disable/enable accounts (anti-cheat)
- `transferOwnership(address)` -- transfer contract ownership

### Wheel (Owner)
- `setPlayPrice(uint256)` -- change the BERA cost to spin
- `setWheelSize(uint256)` -- expand wheel slot count (only increases allowed)
- `setFeeSplit(uint256)` -- adjust team fee percentage (bounded 4-30%)
- `setIncentives(address)` -- change incentives recipient
- `setTreasury(address)` -- change treasury recipient
- `setCommunity(address)` -- change community recipient
- `setFactory(address)` -- update Factory contract reference
- `setUnits(address)` -- update Moola contract reference
- `setDisqualified(address, bool)` -- disqualify/requalify accounts
- `transferOwnership(address)` -- transfer contract ownership

### Wheel (Developer only)
- `setDeveloper(address)` -- self-managed; only the current developer can change this

### Post-Deploy
All ownership is transferred to the treasury multisig (`0x372791b58d4b38104b106c39cc824e14c7638aac`).

---

## Game Reset Handoff

A new Moola, Factory, and Multicall have been deployed and fully configured (tools, multipliers, levels, minter permissions, ownership transferred). The Wheel contract is **reused** -- it just needs to be pointed at the new contracts.

### What's already done

- New Moola (`0xBdb8B9acd9063Cb75B6E64aEc566530cB85c2cF9`) deployed and configured
- New Factory (`0xA5db7214F7cc61c8b01AE05bD0042F50BEb46647`) deployed with all 20 tools, 100 multipliers, and 6 levels
- New Multicall (`0xfd8653E380b4028cA9bf2e03b3E4f4B37cC0B385`) deployed, pointing to new Moola/Factory + existing Wheel
- Minter permissions granted: Factory and Wheel can both mint the new Moola
- Ownership of new Moola and new Factory transferred to treasury multisig

### What the multisig needs to do

The treasury multisig (`0x372791b58d4b38104b106c39cc824e14c7638aac`) must execute **2 transactions** on the existing Wheel contract (`0xA00c4b869d2645D1aF132881c32dcD07c3AbaEd2`):

**Transaction 1 -- Point Wheel to new Factory:**
```
Contract: 0xA00c4b869d2645D1aF132881c32dcD07c3AbaEd2 (Wheel)
Function: setFactory(address)
Argument: 0xA5db7214F7cc61c8b01AE05bD0042F50BEb46647
```

**Transaction 2 -- Point Wheel to new Moola:**
```
Contract: 0xA00c4b869d2645D1aF132881c32dcD07c3AbaEd2 (Wheel)
Function: setUnits(address)
Argument: 0xBdb8B9acd9063Cb75B6E64aEc566530cB85c2cF9
```

### What happens after these 2 transactions

- The Wheel will read player power scores from the **new Factory** (all players start at zero)
- The Wheel will mint **new Moola** tokens as spin rewards
- All player progress on the old Factory/Moola is effectively reset
- The Wheel's existing slot occupants remain, but their power scores will be recalculated from the new Factory on their next spin
- The RewardVault and VaultToken are unchanged -- existing BGT delegations stay intact

### Frontend update

After the multisig executes the two transactions, update the frontend to use:

| Contract | New Address |
|---|---|
| Moola | `0xBdb8B9acd9063Cb75B6E64aEc566530cB85c2cF9` |
| Factory | `0xA5db7214F7cc61c8b01AE05bD0042F50BEb46647` |
| Multicall | `0xfd8653E380b4028cA9bf2e03b3E4f4B37cC0B385` |
| Wheel | `0xA00c4b869d2645D1aF132881c32dcD07c3AbaEd2` (unchanged) |

---

## Tech Stack

- **Solidity** 0.8.19
- **Hardhat** (compilation, testing, deployment, verification)
- **OpenZeppelin** 4.8.x (ERC20, ERC721, Ownable, ReentrancyGuard, Math)
- **Pyth Entropy SDK** (verifiable randomness)
- **Ethers.js** v5 (deployment scripts and tests)
- **Chai** + **Waffle** (testing)

---

## License

MIT
