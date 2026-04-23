// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IFactory {
    function getPower(address account) external view returns (uint256 upc, uint256 power);
    function account_Ups(address account) external view returns (uint256);
    function account_Last(address account) external view returns (uint256);
    function account_toolId_Amount(address account, uint256 toolId) external view returns (uint256);
    function account_toolId_Lvl(address account, uint256 toolId) external view returns (uint256);

    function toolId_BaseCost(uint256 toolId) external view returns (uint256);
    function lvl_CostMultiplier(uint256 lvl) external view returns (uint256);
    function lvl_Unlock(uint256 lvl) external view returns (uint256);
    function toolIndex() external view returns (uint256);
    function amountIndex() external view returns (uint256);

    function getToolCost(uint256 toolId, uint256 amount) external view returns (uint256);
    function getMultipleToolCost(uint256 toolId, uint256 initialAmount, uint256 finalAmount)
        external
        view
        returns (uint256);
    function getToolUps(uint256 toolId, uint256 lvl) external view returns (uint256);
}

interface IWheel {
    function playPrice() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

/// @title Multicall — Read-Only Aggregator for Bull-ish Frontend
/// @notice Batches multiple cross-contract view calls into single responses, reducing
///         RPC round-trips for the game UI. Purely read-only — never mutates state.
/// @dev Each getter returns a packed struct so the frontend can hydrate a full page
///      state in one `eth_call`.
contract Multicall {
    using SafeERC20 for IERC20;

    /// @dev 8 hours in seconds — mirrors Factory.DURATION for claimable calculations.
    uint256 constant DURATION = 28800; // 8 hours

    address public immutable base;
    address public immutable units;
    address public immutable factory;
    address public immutable wheel;

    /// @notice Aggregates a player's delegate-staked power and the total staked across all players.
    struct VaultState {
        uint256 balance;
        uint256 totalSupply;
    }

    /// @notice Full snapshot of a player's Factory state: balances, production rates, and claim status.
    struct FactoryState {
        uint256 unitsBalance;
        uint256 ups;
        uint256 upc;
        uint256 power;
        uint256 capacity;
        uint256 claimable;
        bool full;
    }

    /// @notice Per-tool upgrade info: MOOLA cost for the next level and whether the player qualifies.
    struct ToolUpgradeState {
        uint256 id;
        uint256 cost;
        bool upgradeable;
    }

    /// @notice Per-tool production snapshot: copies owned, next-copy cost, per-unit and total UPS,
    ///         share of the player's total production, and whether the copy cap is reached.
    struct ToolState {
        uint256 id;
        uint256 amount;
        uint256 cost;
        uint256 ups;
        uint256 upsTotal;
        uint256 percentOfProduction;
        bool maxed;
    }

    error Multicall__InvalidPayment();

    constructor(address _base, address _units, address _factory, address _wheel) {
        base = _base;
        units = _units;
        factory = _factory;
        wheel = _wheel;
    }

    /// @notice Calculate the total MOOLA cost to buy `purchaseAmount` additional copies of a tool.
    /// @dev Delegates to Factory.getMultipleToolCost, starting from the player's current amount.
    /// @param account        The player whose current tool count is used as the starting point.
    /// @param toolId         Tool type identifier.
    /// @param purchaseAmount Number of additional copies to price.
    /// @return Total MOOLA cost for the bulk purchase.
    function getMultipleToolCost(address account, uint256 toolId, uint256 purchaseAmount)
        external
        view
        returns (uint256)
    {
        uint256 currentAmount = IFactory(factory).account_toolId_Amount(account, toolId);
        return IFactory(factory).getMultipleToolCost(toolId, currentAmount, currentAmount + purchaseAmount);
    }

    /// @notice Snapshot of a player's Wheel reward vault position.
    /// @param account Player address.
    /// @return vaultState Struct with delegated-stake balance and vault-wide total supply.
    function getVault(address account) external view returns (VaultState memory vaultState) {
        vaultState.balance = IWheel(wheel).balanceOf(account);
        vaultState.totalSupply = IWheel(wheel).totalSupply();
    }

    /// @notice Full Factory dashboard for a player: MOOLA balance, UPS, UPC, power,
    ///         claimable MOOLA, max capacity, and whether the 8-hour cap has been reached.
    /// @param account Player address.
    /// @return factoryState Packed struct with all Factory-derived metrics.
    function getFactory(address account) external view returns (FactoryState memory factoryState) {
        factoryState.unitsBalance = IERC20(units).balanceOf(account);
        factoryState.ups = IFactory(factory).account_Ups(account);
        (factoryState.upc, factoryState.power) = IFactory(factory).getPower(account);
        uint256 amount = factoryState.ups * (block.timestamp - IFactory(factory).account_Last(account));
        factoryState.capacity = factoryState.ups * DURATION;
        factoryState.claimable = amount >= factoryState.capacity ? factoryState.capacity : amount;
        factoryState.full = amount >= factoryState.capacity;
    }

    /// @notice Returns upgrade cost and eligibility for every tool type.
    /// @dev `upgradeable` is false if the player lacks enough copies or the next level is unconfigured.
    /// @param account Player address.
    /// @return toolUpgradeState Array of ToolUpgradeState for each configured tool.
    function getUpgrades(address account) external view returns (ToolUpgradeState[] memory toolUpgradeState) {
        uint256 toolCount = IFactory(factory).toolIndex();
        toolUpgradeState = new ToolUpgradeState[](toolCount);
        for (uint256 i = 0; i < toolCount; i++) {
            uint256 lvl = IFactory(factory).account_toolId_Lvl(account, i);
            uint256 amount = IFactory(factory).account_toolId_Amount(account, i);
            uint256 amountRequired = IFactory(factory).lvl_Unlock(lvl + 1);
            toolUpgradeState[i].id = i;
            toolUpgradeState[i].cost =
                IFactory(factory).toolId_BaseCost(i) * IFactory(factory).lvl_CostMultiplier(lvl + 1);
            toolUpgradeState[i].upgradeable = amount < amountRequired || toolUpgradeState[i].cost == 0 ? false : true;
        }
    }

    /// @notice Returns full tool state for every tool type: copies owned, next-copy cost,
    ///         per-unit UPS, total UPS contribution, percentage of total production, and max status.
    /// @param account Player address.
    /// @return toolState Array of ToolState for each configured tool.
    function getTools(address account) external view returns (ToolState[] memory toolState) {
        uint256 toolCount = IFactory(factory).toolIndex();
        toolState = new ToolState[](toolCount);
        for (uint256 i = 0; i < toolCount; i++) {
            toolState[i].id = i;
            toolState[i].amount = IFactory(factory).account_toolId_Amount(account, i);
            toolState[i].maxed = IFactory(factory).account_toolId_Amount(account, i) == IFactory(factory).amountIndex();
            toolState[i].cost = toolState[i].maxed ? 0 : IFactory(factory).getToolCost(i, toolState[i].amount);
            uint256 lvl = IFactory(factory).account_toolId_Lvl(account, i);
            toolState[i].ups = IFactory(factory).getToolUps(i, lvl);
            toolState[i].upsTotal = toolState[i].ups * toolState[i].amount;
            toolState[i].percentOfProduction = IFactory(factory).account_Ups(account) == 0
                ? 0
                : toolState[i].upsTotal * 1e18 * 100 / IFactory(factory).account_Ups(account);
        }
    }
}
