// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @dev An interface for an ERC20-like token (the in-game Units/Moola),
 *      enabling minting and burning by authorized contracts.
 */
interface IUnits {
    function mint(address account, uint256 amount) external;
    function burn(address account, uint256 amount) external;
}

/**
 * @title Factory
 * @author heesho
 * @notice The Factory contract handles:
 *         - Storing/updating each player's passive generation rate (units per second).
 *         - Allowing players to purchase "tools" that increase their production rate.
 *         - Allowing players to upgrade those tools, further boosting production.
 *         - Token-based claim functionality (players claim the units they've accumulated over time).
 * @dev The contract references:
 *      1. An ERC721 `key` contract (e.g., player's "Weapon Inventory" NFT).
 *      2. A `units` contract (ERC20-like) for minting/burning in-game currency.
 */
contract Factory is ReentrancyGuard, Ownable {

    /*----------  CONSTANTS  --------------------------------------------*/

    /**
     * @dev Used to ensure multiplication is precise when calculating cost multipliers.
     *      For instance, cost might be baseCost * costMultiplier / PRECISION.
     */
    uint256 constant PRECISION = 1e18;   
    /**
     * @dev The maximum number of seconds for which production can be claimed at once.
     *      If a user hasn't claimed for a very long time, we cap the claimable period
     *      to prevent extremely large claims.
     */
    uint256 constant DURATION = 28800;

    /*----------  STATE VARIABLES  --------------------------------------*/

    /**
     * @notice Address of the IUnits (Moola) contract.  
     *         Used for minting and burning the in-game currency.
     */
    address immutable public units;
    /**
     * @notice Address of the ERC721 "key" contract (e.g. player's Bullas NFT).
     *         We check ownership of this NFT to ensure only valid players can interact.
     */
    address immutable public key;

    /**
     * @notice Tracks the current highest "level index."
     *         Each level requires a cost multiplier and an unlock threshold.
     */
    uint256 public lvlIndex;
    /**
     * @notice For each level, how many tools are required to unlock that level upgrade.
     *         Example: `lvl_Unlock[level] = 5` means the user needs 5 of the tool
     *         before they can upgrade to that level.
     */
    mapping(uint256 => uint256) public lvl_Unlock;          // level => amount required to unlock
    /**
     * @notice For each level, what cost multiplier is applied when upgrading a tool to that level.
     *         e.g., `lvl_CostMultiplier[level] = 2 * 1e18` would mean a base cost * 2 at that level.
     */
    mapping(uint256 => uint256) public lvl_CostMultiplier;  // level => cost multiplier

    /**
     * @notice Tracks how many different tool IDs have been registered.
     */
    uint256 public toolIndex;
    /**
     * @notice Tracks how many distinct "amount multipliers" have been registered.
     *         For instance, if the user buys 1st, 2nd, 3rd copy of a tool, each can have a different cost multiplier.
     */
    uint256 public amountIndex;
    /**
     * @notice For each tool ID, the base cost of that tool before multipliers are applied.
     *         Example: If `toolId_BaseCost[5] = 100e18`, then the starting cost for tool #5 is 100 Moola.
     */
    mapping(uint256 => uint256) public toolId_BaseCost;         // tool id => base cost
    /**
     * @notice For each tool ID, the base production rate (units/second) at level 0.
     *         The final production rate for level L is `baseUps * 2^L` (exponential growth).
     */
    mapping(uint256 => uint256) public toolId_BaseUps;          // tool id => base units per second
    /**
     * @notice For each number of tools purchased so far, there's a cost multiplier.
     *         If `amount_CostMultiplier[3] = 150e16` (1.5x in 1e18 format),
     *         buying the 4th tool might cost an additional 1.5 * baseCost.
     */
    mapping(uint256 => uint256) public amount_CostMultiplier;   // tool amount => cost multiplier
    
    /**
     * @notice For each token ID (player inventory), how many units per second it currently generates.
     *         This is the sum of the production from all tools the player owns/levels they have upgraded.
     */
    mapping(uint256 => uint256) public tokenId_Ups;         // token id => units per second
    /**
     * @notice For each token ID (player inventory), the last time they claimed their production.
     *         On claiming, we calculate the difference between the current block time and `tokenId_Last`,
     *         multiplied by `tokenId_Ups[tokenId]`.
     */
    mapping(uint256 => uint256) public tokenId_Last;        // token id => last time claimed

    /**
     * @notice Tracks how many copies of each tool a player has purchased.
     *         e.g. `tokenId_toolId_Amount[tokenId][toolId]` = 3 means the player has 3 copies of that tool ID.
     */
    mapping(uint256 => mapping(uint256 => uint256)) public tokenId_toolId_Amount; // token id => tool id => amount
    /**
     * @notice Tracks the upgrade level for a particular tool on a specific token ID.
     *         e.g. `tokenId_toolId_Lvl[tokenId][toolId]` = 2 means the user’s tool is at level 2.
     */
    mapping(uint256 => mapping(uint256 => uint256)) public tokenId_toolId_Lvl;    // token id => tool id => level

    /*----------  ERRORS ------------------------------------------------*/

    error Factory__AmountMaxed();
    error Factory__LevelMaxed();
    error Factory__InvalidInput();
    error Factory__NotAuthorized();
    error Factory__UpgradeLocked();
    error Factory__InvalidTokenId();
    error Factory__InvalidLength();
    error Factory__CannotEvolve();
    error Factory__ToolDoesNotExist();

    /*----------  EVENTS ------------------------------------------------*/

    event Factory__ToolPurchased(uint256 indexed tokenId, uint256 toolId, uint256 newAmount, uint256 cost, uint256 ups);
    event Factory__ToolUpgraded(uint256 indexed tokenId, uint256 toolId, uint256 newLevel, uint256 cost, uint256 ups);
    event Factory__Claimed(uint256 indexed tokenId, uint256 amount);
    event Factory__LvlSet(uint256 lvl, uint256 cost, uint256 unlock);
    event Factory__ToolSet(uint256 toolId, uint256 baseUps, uint256 baseCost);
    event Factory__ToolMultiplierSet(uint256 index, uint256 multiplier);

    /*----------  MODIFIERS  --------------------------------------------*/

    /**
     * @dev Ensures that the NFT with this tokenId actually exists (owned by someone).
     */
    modifier tokenExists(uint256 tokenId) {
        if (IERC721(key).ownerOf(tokenId) == address(0)) revert Factory__InvalidTokenId();
        _;
    }

    /*----------  FUNCTIONS  --------------------------------------------*/

    /**
     * @notice Initializes the Factory contract.
     * @param _units The address of the Moola (Units) contract.
     * @param _key The address of the NFT contract representing the player's "Weapon Inventory."
     */
    constructor(address _units, address _key) {
        units = _units;
        key = _key;
    }

    /**
     * @notice Claims production for a specific tokenId (player).
     *         Calculates how many units have accrued since the last claim, 
     *         subject to the maximum claim duration (8 hours).
     * @param tokenId The NFT ID representing the player’s inventory.
     */
    function claim(uint256 tokenId) public tokenExists(tokenId) {
        uint256 amount = tokenId_Ups[tokenId] * (block.timestamp - tokenId_Last[tokenId]);
        uint256 maxAmount = tokenId_Ups[tokenId] * DURATION;
        if (amount > maxAmount) amount = maxAmount;
        tokenId_Last[tokenId] = block.timestamp;
        emit Factory__Claimed(tokenId, amount);
        IUnits(units).mint(IERC721(key).ownerOf(tokenId), amount);
    }

    /**
     * @notice Allows a player to purchase multiple copies of a specific tool at once.
     *         Each copy increases their total production rate.
     * @param tokenId The NFT ID representing the player.
     * @param toolId The tool being purchased.
     * @param toolAmount How many copies of the tool to buy this transaction.
     */
    function purchaseTool(uint256 tokenId, uint256 toolId, uint256 toolAmount) external nonReentrant tokenExists(tokenId) {
        if (toolAmount == 0) revert Factory__InvalidInput();
        claim(tokenId);
        uint256 cost = 0;
        for (uint256 i = 0; i < toolAmount; i++) {
            uint256 currentAmount = tokenId_toolId_Amount[tokenId][toolId];
            if (currentAmount == amountIndex) revert Factory__AmountMaxed();
            uint256 unitCost = getToolCost(toolId, currentAmount);
            cost += unitCost;
            if (unitCost == 0) revert Factory__ToolDoesNotExist();
            tokenId_toolId_Amount[tokenId][toolId]++;
            tokenId_Ups[tokenId] += getToolUps(toolId, tokenId_toolId_Lvl[tokenId][toolId]);
            emit Factory__ToolPurchased(tokenId, toolId, tokenId_toolId_Amount[tokenId][toolId], unitCost, tokenId_Ups[tokenId]);
        }
        IUnits(units).burn(msg.sender, cost);
    }

    /**
     * @notice Upgrades a specific tool for a given player to the next level.
     *         Requires enough copies of the tool in place to meet the unlock requirement,
     *         and burns the required Moola.
     * @param tokenId The NFT ID representing the player.
     * @param toolId The tool being upgraded.
     */
    function upgradeTool(uint256 tokenId, uint256 toolId) external nonReentrant tokenExists(tokenId) {
        uint256 currentLvl = tokenId_toolId_Lvl[tokenId][toolId];
        uint256 cost = toolId_BaseCost[toolId] * lvl_CostMultiplier[currentLvl + 1];
        if (cost == 0) revert Factory__LevelMaxed();
        if (tokenId_toolId_Amount[tokenId][toolId] < lvl_Unlock[currentLvl + 1]) revert Factory__UpgradeLocked();
        claim(tokenId); 
        tokenId_toolId_Lvl[tokenId][toolId]++;
        tokenId_Ups[tokenId] += (getToolUps(toolId, currentLvl + 1) - getToolUps(toolId, currentLvl)) * tokenId_toolId_Amount[tokenId][toolId];
        emit Factory__ToolUpgraded(tokenId, toolId, tokenId_toolId_Lvl[tokenId][toolId], cost, tokenId_Ups[tokenId]);
        IUnits(units).burn(msg.sender, cost);
    }

    /*----------  RESTRICTED FUNCTIONS  ---------------------------------*/

    /**
     * @notice Owner can configure new levels, specifying their cost multipliers and unlock thresholds.
     *         For example, level 1 might have costMultiplier=2*1e18, unlock=2 copies required, etc.
     * @param cost An array of cost multipliers in 1e18 precision for new levels.
     * @param unlock An array of how many copies of a tool are required to unlock that level upgrade.
     */
    function setLvl(uint256[] calldata cost, uint256[] calldata unlock) external onlyOwner {
        if (cost.length != unlock.length) revert Factory__InvalidInput();
        for (uint256 i = lvlIndex; i < lvlIndex + cost.length; i++) {
            uint256 arrayIndex = i - lvlIndex;
            lvl_CostMultiplier[i] = cost[arrayIndex];
            lvl_Unlock[i] = unlock[arrayIndex];
            emit Factory__LvlSet(i, cost[i], unlock[i]);
        }
        lvlIndex += cost.length;
    }

    /**
     * @notice Owner can register new tools, specifying their base production (Ups) and base cost.
     * @param baseUps An array of production rates (units per second) for each new tool (level 0).
     * @param baseCost An array of base costs in Moola for each new tool (quantity=0).
     */
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

    /**
     * @notice Owner can define or extend the cost multipliers based on how many copies of the tool have been bought.
     *         e.g., [1e18, 11e17, 12e17] => multipliers for the 1st, 2nd, 3rd tool, etc.
     * @param multipliers An array of new multipliers to register, each in 1e18 precision.
     */
    function setToolMultipliers(uint256[] calldata multipliers) external onlyOwner {
        for (uint256 i = amountIndex; i < amountIndex + multipliers.length; i++) {
            uint256 arrayIndex = i - amountIndex;
            amount_CostMultiplier[i] = multipliers[arrayIndex];
            emit Factory__ToolMultiplierSet(i, multipliers[arrayIndex]);
        }
        amountIndex += multipliers.length;
    }

    /*----------  VIEW FUNCTIONS  ---------------------------------------*/

    /**
     * @notice Computes how many units per second a single copy of a given tool contributes at a certain level.
     * @param toolId The tool’s ID.
     * @param lvl The level to consider.
     * @return Amount of ups = `baseUps * 2^lvl`.
     */
    function getToolUps(uint256 toolId, uint256 lvl) public view returns (uint256) {
        return toolId_BaseUps[toolId] * 2 ** lvl;
    }
 
     /**
     * @notice Computes the purchase cost for the N-th copy of a given tool (before leveling).
     * @param toolId The tool’s ID.
     * @param amount How many copies of the tool the user already owns (0-based).
     * @return The Moola cost for buying copy #(amount+1).
     */
    function getToolCost(uint256 toolId, uint256 amount) public view returns (uint256) {
        if (amount >= amountIndex) revert Factory__AmountMaxed();
        return toolId_BaseCost[toolId] * amount_CostMultiplier[amount] / PRECISION;
    }

    /**
     * @notice Computes the total cost for buying multiple copies of a tool in a single transaction:
     *         from `initialAmount` to `finalAmount - 1` inclusive.
     *         e.g. if the user is going from 2 copies to 5 copies, it sums cost of the 3rd, 4th, and 5th copy.
     * @param toolId The tool’s ID.
     * @param initialAmount The user’s current number of copies.
     * @param finalAmount How many copies the user will have after purchase.
     * @return The total Moola cost for buying those additional copies.
     */
    function getMultipleToolCost(uint256 toolId, uint256 initialAmount, uint256 finalAmount) external view returns (uint256){
        uint256 cost = 0;
        for (uint256 i = initialAmount; i < finalAmount; i++) {
            cost += getToolCost(toolId, i);
        }
        return cost;
    }

}