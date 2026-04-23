// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

interface IUnits {
    function mint(address account, uint256 amount) external;
    function burn(address account, uint256 amount) external;
}

/// @title Factory — Bull-ish Idle-Clicker Game Engine
/// @notice Core progression contract. Players purchase tools that passively generate MOOLA (UPS),
///         claim accumulated MOOLA, and upgrade tools to double their output.
/// @dev UPS (Units Per Second) accrues linearly. Claiming is capped at DURATION seconds
///      to prevent indefinite AFK accumulation. Tool costs follow a configurable multiplier
///      table so each successive copy is more expensive. Upgrades require owning enough
///      copies of a tool before the next level unlocks.
contract Factory is ReentrancyGuard, Ownable {
    /// @dev Fixed-point scaling factor (1e18) used for cost multiplier arithmetic.
    uint256 constant PRECISION = 1 ether;

    /// @dev Base Units-Per-Click — every player starts with 1 MOOLA base production.
    uint256 constant BASE_UPC = 1 ether;

    /// @dev Maximum seconds of idle accumulation (8 hours = 28 800 s). Claims beyond this are capped.
    uint256 constant DURATION = 28800;

    /// @notice MOOLA token address used for minting rewards and burning purchase costs.
    address public immutable units;

    /// @notice Bullas NFT contract. Holders receive a 10% bonus to UPC.
    address public booster;

    /// @notice Ceiling on the power score returned by `getPower`. Prevents excessive delegation weight.
    uint256 public maxPower = 1 ether;

    /// @notice Number of upgrade levels that have been configured so far.
    uint256 public lvlIndex;

    /// @notice Minimum tool copies a player needs before unlocking upgrade to this level.
    mapping(uint256 => uint256) public lvl_Unlock; // level => amount required to unlock

    /// @notice Multiplier applied to a tool's base cost to determine the upgrade price at this level.
    mapping(uint256 => uint256) public lvl_CostMultiplier; // level => cost multiplier

    /// @notice Number of distinct tools configured so far.
    uint256 public toolIndex;

    /// @notice Number of cost multiplier entries configured (also the max copies of any tool).
    uint256 public amountIndex;

    /// @notice Base MOOLA cost for the first copy of a tool (before multiplier).
    mapping(uint256 => uint256) public toolId_BaseCost; // tool id => base cost

    /// @notice Base UPS contribution of one copy of a tool at level 0.
    mapping(uint256 => uint256) public toolId_BaseUps; // tool id => base units per second

    /// @notice Cost scaling table: amount_CostMultiplier[n] is the 1e18-scaled multiplier for the (n+1)th copy.
    mapping(uint256 => uint256) public amount_CostMultiplier; // tool amount => cost multiplier

    /// @notice Aggregate UPS for an account across all owned tools and levels.
    mapping(address => uint256) public account_Ups; // account => units per second

    /// @notice Timestamp of the last claim (used to calculate accrued MOOLA).
    mapping(address => uint256) public account_Last; // account => last time claimed

    /// @notice Number of copies of each tool owned by an account.
    mapping(address => mapping(uint256 => uint256)) public account_toolId_Amount; // account => tool id => amount

    /// @notice Current upgrade level of each tool for an account.
    mapping(address => mapping(uint256 => uint256)) public account_toolId_Lvl; // account => tool id => level

    /// @notice Disabled accounts are blocked from participating in getPower (anti-abuse).
    mapping(address => bool) public account_Disabled;

    error Factory__AmountMaxed();
    error Factory__LevelMaxed();
    error Factory__InvalidInput();
    error Factory__NotAuthorized();
    error Factory__UpgradeLocked();
    error Factory__ToolDoesNotExist();
    error Factory__AccountDisabled();

    event Factory__ToolPurchased(address indexed account, uint256 toolId, uint256 newAmount, uint256 cost, uint256 ups);
    event Factory__ToolUpgraded(address indexed account, uint256 toolId, uint256 newLevel, uint256 cost, uint256 ups);
    event Factory__Claimed(address indexed account, uint256 amount);
    event Factory__LvlSet(uint256 lvl, uint256 cost, uint256 unlock);
    event Factory__ToolSet(uint256 toolId, uint256 baseUps, uint256 baseCost);
    event Factory__ToolMultiplierSet(uint256 index, uint256 multiplier);
    event Factory__MaxPowerSet(uint256 maxPower);
    event Factory__BoosterSet(address booster);
    event Factory__DisabledSet(address account, bool disabled);

    modifier onlyAccount(address account) {
        if (msg.sender != account) revert Factory__NotAuthorized();
        _;
    }

    constructor(address _units) {
        units = _units;
    }

    /// @notice Mint the MOOLA that `account` has accrued since their last claim.
    /// @dev Accrual = UPS * elapsed, capped at UPS * DURATION (8 hrs).
    ///      Called internally before every purchase/upgrade so balances are always fresh.
    /// @param account The player whose MOOLA is claimed.
    function claim(address account) public {
        uint256 amount = account_Ups[account] * (block.timestamp - account_Last[account]);
        uint256 maxAmount = account_Ups[account] * DURATION;
        if (amount > maxAmount) amount = maxAmount;
        account_Last[account] = block.timestamp;
        emit Factory__Claimed(account, amount);
        IUnits(units).mint(account, amount);
    }

    /// @notice Buy one or more copies of a tool, burning MOOLA for each.
    /// @dev Auto-claims before purchasing so pending MOOLA is not lost.
    ///      Each successive copy costs more via the `amount_CostMultiplier` table.
    ///      Reverts if the tool does not exist or the copy cap (`amountIndex`) is reached.
    /// @param account    Must equal `msg.sender` (enforced by `onlyAccount`).
    /// @param toolId     Identifier of the tool type to purchase.
    /// @param toolAmount Number of copies to buy in this transaction.
    function purchaseTool(address account, uint256 toolId, uint256 toolAmount)
        external
        nonReentrant
        onlyAccount(account)
    {
        if (toolAmount == 0) revert Factory__InvalidInput();
        claim(account);
        uint256 cost = 0;
        for (uint256 i = 0; i < toolAmount; i++) {
            uint256 currentAmount = account_toolId_Amount[account][toolId];
            if (currentAmount == amountIndex) revert Factory__AmountMaxed();
            uint256 unitCost = getToolCost(toolId, currentAmount);
            cost += unitCost;
            if (unitCost == 0) revert Factory__ToolDoesNotExist();
            account_toolId_Amount[account][toolId]++;
            account_Ups[account] += getToolUps(toolId, account_toolId_Lvl[account][toolId]);
            emit Factory__ToolPurchased(
                account, toolId, account_toolId_Amount[account][toolId], unitCost, account_Ups[account]
            );
        }
        IUnits(units).burn(account, cost);
    }

    /// @notice Level up a tool, doubling its UPS contribution for every copy owned.
    /// @dev The upgrade cost is `baseCost * lvl_CostMultiplier[nextLvl]`. The player must own
    ///      at least `lvl_Unlock[nextLvl]` copies to be eligible. Auto-claims before upgrading.
    ///      UPS delta = (newToolUps - oldToolUps) * copiesOwned.
    /// @param account Must equal `msg.sender`.
    /// @param toolId  Identifier of the tool type to upgrade.
    function upgradeTool(address account, uint256 toolId) external nonReentrant onlyAccount(account) {
        uint256 currentLvl = account_toolId_Lvl[account][toolId];
        uint256 cost = toolId_BaseCost[toolId] * lvl_CostMultiplier[currentLvl + 1];
        if (cost == 0) revert Factory__LevelMaxed();
        if (account_toolId_Amount[account][toolId] < lvl_Unlock[currentLvl + 1]) revert Factory__UpgradeLocked();
        claim(account);
        account_toolId_Lvl[account][toolId]++;
        account_Ups[account] += (getToolUps(toolId, currentLvl + 1) - getToolUps(toolId, currentLvl))
            * account_toolId_Amount[account][toolId];
        emit Factory__ToolUpgraded(account, toolId, account_toolId_Lvl[account][toolId], cost, account_Ups[account]);
        IUnits(units).burn(account, cost);
    }

    /// @notice Append new upgrade levels to the level configuration table.
    /// @dev Levels are appended starting at `lvlIndex`; existing levels are never overwritten.
    /// @param cost   Array of cost multipliers (1e18-scaled) for each new level.
    /// @param unlock Array of tool-copy thresholds required to unlock each new level.
    function setLvl(uint256[] calldata cost, uint256[] calldata unlock) external onlyOwner {
        if (cost.length != unlock.length) revert Factory__InvalidInput();
        for (uint256 i = lvlIndex; i < lvlIndex + cost.length; i++) {
            uint256 arrayIndex = i - lvlIndex;
            lvl_CostMultiplier[i] = cost[arrayIndex];
            lvl_Unlock[i] = unlock[arrayIndex];
            emit Factory__LvlSet(i, cost[arrayIndex], unlock[arrayIndex]);
        }
        lvlIndex += cost.length;
    }

    /// @notice Append new tool types to the tool configuration table.
    /// @dev Tools are appended starting at `toolIndex`; existing tools are never overwritten.
    /// @param baseUps  Array of base UPS values (at level 0) for each new tool.
    /// @param baseCost Array of base MOOLA costs for each new tool.
    function setTool(uint256[] calldata baseUps, uint256[] calldata baseCost) external onlyOwner {
        if (baseUps.length != baseCost.length) revert Factory__InvalidInput();
        for (uint256 i = toolIndex; i < toolIndex + baseUps.length; i++) {
            uint256 arrayIndex = i - toolIndex;
            toolId_BaseUps[i] = baseUps[arrayIndex];
            toolId_BaseCost[i] = baseCost[arrayIndex];
            emit Factory__ToolSet(i, baseUps[arrayIndex], baseCost[arrayIndex]);
        }
        toolIndex += baseUps.length;
    }

    /// @notice Append new entries to the cost multiplier table that governs per-copy pricing.
    /// @dev `amountIndex` also serves as the max number of copies any player can own of a single tool.
    /// @param multipliers Array of 1e18-scaled multipliers to append.
    function setToolMultipliers(uint256[] calldata multipliers) external onlyOwner {
        for (uint256 i = amountIndex; i < amountIndex + multipliers.length; i++) {
            uint256 arrayIndex = i - amountIndex;
            amount_CostMultiplier[i] = multipliers[arrayIndex];
            emit Factory__ToolMultiplierSet(i, multipliers[arrayIndex]);
        }
        amountIndex += multipliers.length;
    }

    /// @notice Set the ceiling on the power score used for Wheel delegation.
    /// @param _maxPower New cap value (1e18-scaled).
    function setMaxPower(uint256 _maxPower) external onlyOwner {
        maxPower = _maxPower;
        emit Factory__MaxPowerSet(_maxPower);
    }

    /// @notice Set the Bullas NFT contract address used for the 10% UPC bonus.
    /// @param _booster Address of the Bullas ERC-721 contract (or address(0) to disable).
    function setBooster(address _booster) external onlyOwner {
        booster = _booster;
        emit Factory__BoosterSet(_booster);
    }

    /// @notice Ban or unban an account from `getPower`, effectively blocking Wheel participation.
    /// @param account  Address to disable or re-enable.
    /// @param disabled `true` to block, `false` to allow.
    function setDisabled(address account, bool disabled) external onlyOwner {
        account_Disabled[account] = disabled;
        emit Factory__DisabledSet(account, disabled);
    }

    /// @notice Calculate the UPS of a single tool copy at a given level.
    /// @dev Each level doubles the output: `baseUps * 2^lvl`.
    /// @param toolId The tool type identifier.
    /// @param lvl    The upgrade level.
    /// @return UPS contribution of one copy at this level.
    function getToolUps(uint256 toolId, uint256 lvl) public view returns (uint256) {
        return toolId_BaseUps[toolId] * 2 ** lvl;
    }

    /// @notice Calculate the MOOLA cost to purchase the (amount+1)th copy of a tool.
    /// @dev cost = baseCost * costMultiplier[amount] / 1e18.
    /// @param toolId The tool type identifier.
    /// @param amount The player's current number of copies (0-indexed).
    /// @return MOOLA cost for the next copy.
    function getToolCost(uint256 toolId, uint256 amount) public view returns (uint256) {
        if (amount >= amountIndex) revert Factory__AmountMaxed();
        return toolId_BaseCost[toolId] * amount_CostMultiplier[amount] / PRECISION;
    }

    /// @notice Sum the MOOLA cost of purchasing copies from `initialAmount` to `finalAmount - 1`.
    /// @dev Used by Multicall for bulk-buy cost previews.
    /// @param toolId       The tool type identifier.
    /// @param initialAmount Starting copy index (inclusive).
    /// @param finalAmount   Ending copy index (exclusive).
    /// @return Total MOOLA cost across all copies in the range.
    function getMultipleToolCost(uint256 toolId, uint256 initialAmount, uint256 finalAmount)
        external
        view
        returns (uint256)
    {
        uint256 cost = 0;
        for (uint256 i = initialAmount; i < finalAmount; i++) {
            cost += getToolCost(toolId, i);
        }
        return cost;
    }

    /// @notice Compute an account's UPC (Units Per Click) and power score for Wheel delegation.
    /// @dev UPC = BASE_UPC + total UPS, boosted by 10% if the account holds a Bullas NFT.
    ///      Power = sqrt(UPC * 1e18), capped at `maxPower`. The square-root curve rewards
    ///      broad progression over whale-dominated linear scaling.
    /// @param account The player address.
    /// @return upc   The player's effective units-per-click.
    /// @return power The player's delegation weight for the Wheel reward vault.
    function getPower(address account) public view returns (uint256 upc, uint256 power) {
        if (account_Disabled[account]) revert Factory__AccountDisabled();
        upc = BASE_UPC + account_Ups[account];
        if (booster != address(0)) {
            if (IERC721(booster).balanceOf(account) > 0) {
                upc = upc * 11 / 10;
            }
        }
        power = Math.sqrt(upc * 1e18);
        if (power > maxPower) {
            power = maxPower;
        }
    }
}
