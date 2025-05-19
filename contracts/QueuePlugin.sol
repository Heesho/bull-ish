// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @notice Interface to interact with a Gauge contract.
 *         Typically, Gauges manage deposits/withdrawals of tokens and track user balances
 *         for liquidity mining or other incentives.
 */
interface IGauge {
    function _deposit(address account, uint256 amount) external;
    function _withdraw(address account, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/**
 * @notice Interface to interact with a Bribe contract.
 *         The `notifyRewardAmount` function signals that new rewards are available for distribution.
 */
interface IBribe {
    function notifyRewardAmount(address token, uint amount) external;
}

/**
 * @notice Interface for the "voter" system that the plugin hooks into.
 *         The plugin needs to know the address of the "oTOKEN" for bribes/rewards.
 */
interface IVoter {
    function OTOKEN() external view returns (address);
}

/**
 * @notice Interface for a factory that records how many “ups” each account has.
 *         This is used to calculate a player’s spank power (based on `account_Ups`).
 */
interface IFactory {
    function getPower(address account) external view returns (uint256 upc, uint256 power);
}

/**
 * @notice Interface to the “Units” system that can mint additional in-game currency/units for the user.
 */
interface IUnits {
    function mint(address account, uint256 amount) external;
}

/**
 * @notice Interface to a factory responsible for creating reward vaults.
 *         Each vault is specialized for a given vaultToken (like our `VaultToken`).
 */
interface IBerachainRewardVaultFactory {
    function createRewardVault(address _vaultToken) external returns (address);
}

/**
 * @notice Interface to a reward vault where we can delegate staking and withdrawals.
 *         Ties into Berachain’s PoL system for distributing extra rewards.
 */
interface IRewardVault {
    function delegateStake(address account, uint256 amount) external;
    function delegateWithdraw(address account, uint256 amount) external;
}

/**
 * @title VaultToken
 * @notice A simple ERC20 token used to represent staked positions in the QueuePlugin.
 *         The QueuePlugin contract mints and burns this token on demand to track
 *         how much power each user is staking in the breadline.
 */
contract VaultToken is ERC20, Ownable {

    /**
     * @notice Initializes the ERC20 token with a name and symbol.
     */
    constructor() ERC20("BULL ISH V3", "BULL ISH V3") {}

    /**
     * @dev Mints new tokens to a specified address.
     *      Only the owner (QueuePlugin contract) can call this.
     * @param to The address that will receive the newly minted tokens.
     * @param amount The number of tokens to mint.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @dev Burns tokens from a specified address.
     *      Only the owner (QueuePlugin contract) can call this.
     * @param from The address from which tokens will be burned.
     * @param amount The number of tokens to burn.
     */
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}

/**
 * @title QueuePlugin
 * @author heesho
 * @notice This contract manages the “breadline” mechanic: players pay a fee to join a queue (spanking the Bera).
 *         While in the queue, players earn “oBERO” rewards through the Gauge system. Once the queue is at capacity,
 *         new spankers displace the oldest ones. Displaced players are withdrawn from the Gauge and lose the spot.
 * @dev In addition to handling the queue, this contract automates bribing to hiBERO voters using 80% of spank fees.
 */
contract QueuePlugin is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20; // Safe wrappers around ERC20 ops that throw on failure

    /*----------  CONSTANTS  --------------------------------------------*/
    // Maximum number of clicks (spankers) in the queue 
    uint256 public constant QUEUE_SIZE = 300;
    // Duration for which the plugin collects fees
    uint256 public constant DURATION = 7 days;
    // Maximum length of the optional message in a spank transaction
    uint256 public constant MESSAGE_LENGTH = 69;
    // Display strings for the plugin
    string public constant NAME = "BULL ISH V3";
    string public constant PROTOCOL = "Bullas";

    /*----------  STATE VARIABLES  --------------------------------------*/

    // The token used for paying the spank fee (BERA)
    IERC20 private immutable token;
    // The oTOKEN address, derived from the voter contract
    address private immutable OTOKEN;
    // The voter contract address (Beradrome Voter)
    address private immutable voter;
    // The Gauge contract linked to this plugin for staking and rewards
    address private gauge;
    // The Bribe contract linked to this plugin for bribe distribution
    address private bribe;
    // Array of addresses for asset tokens (WBERA)
    address[] private assetTokens;
    // Array of addresses for bribe tokens (WBERA)
    address[] private bribeTokens;
    // The VaultToken contract representing staked positions (minted/burned by this contract)
    address public immutable vaultToken;
    // The RewardVault contract created for this specific VaultToken
    address public immutable rewardVault;

    // Factory contract for weapons inventory for a key
    address public factory;
    // The “Units” contract that can mint in-game currency (Moola) for the user
    address public units;

    // Receivers for fee distribution
    address public treasury;
    address public incentives;
    address public developer;

    // The fee (in BERA) required to spank
    uint256 public entryFee = 0.69 ether;
    // Whether or not fees are automatically sent to the bribe contract
    bool public autoBribe = true;

    /**
     * @notice Represents a single player’s spot in the breadline (queue).
     *         - `account`: the account that caused this spank.
     *         - `power`: the power derived from the NFT’s “ups” used to stake in the Gauge.
     *         - `message`: optional short message from the user (onchain).
     */
    struct Click {
        address account;
        uint256 power;
        string message;
    }

    // Circular queue to store the 300 players currently in the breadline
    mapping(uint256 => Click) public queue;
    // Indices for the circular queue: `head` is the oldest occupant, `tail` is where new occupants are added.
    uint256 public head = 0;
    uint256 public tail = 0;
    uint256 public count = 0;

    /*----------  ERRORS ------------------------------------------------*/

    error Plugin__InvalidAccount();
    error Plugin__InvalidZeroInput();
    error Plugin__NotAuthorizedVoter();
    error Plugin__NotAuthorized();
    error Plugin__InvalidMessage();

    /*----------  EVENTS ------------------------------------------------*/

    event Plugin__ClaimedAndDistributed(uint256 bribeFee, uint256 treasuryFee, uint256 developerFee);
    event Plugin__ClickAdded(address indexed account, uint256 mintAmount, uint256 power, string message);
    event Plugin__ClickRemoved(address indexed account, uint256 power, string message);
    event Plugin__TreasurySet(address treasury);
    event Plugin__IncentivesSet(address incentives);
    event Plugin__DeveloperSet(address developer);
    event Plugin__FactorySet(address factory);
    event Plugin__UnitsSet(address units);
    event Plugin__EntryFeeSet(uint256 fee);
    event Plugin__AutoBribeSet(bool autoBribe);

    /*----------  MODIFIERS  --------------------------------------------*/

    /**
     * @dev Throws if the input amount is zero. Prevents useless transactions.
     */
    modifier nonZeroInput(uint256 _amount) {
        if (_amount == 0) revert Plugin__InvalidZeroInput();
        _;
    }

    /**
     * @dev Restricts certain calls (like gauge or bribe updates) to the voter contract only.
     */
    modifier onlyVoter() {
        if (msg.sender != voter) revert Plugin__NotAuthorizedVoter();
        _;
    }

    /*----------  FUNCTIONS  --------------------------------------------*/

    /**
     * @notice Deploys the QueuePlugin contract and sets key addresses, creates a vault token and a reward vault.
     * @param _token The BERA (or main ERC20) token used for fees.
     * @param _voter The Voter contract (to fetch OTOKEN, set gauge/bribe).
     * @param _assetTokens Potentially multiple tokens that represent underlying assets for the plugin.
     * @param _bribeTokens The token(s) used for bribe distribution.
     * @param _treasury Where a portion of the fees will be directed.
     * @param _developer The developer address receiving a portion of the fees.
     * @param _factory The factory contract used to compute "ups" for each NFT token ID.
     * @param _units The contract that mints in-game currency (Moola).
     * @param _vaultFactory The factory that creates a specialized reward vault for `vaultToken`.
     */
    constructor(
        address _token,
        address _voter,
        address[] memory _assetTokens,
        address[] memory _bribeTokens,
        address _treasury,
        address _developer,
        address _factory,
        address _units,
        address _vaultFactory
    ) {
        token = IERC20(_token);
        voter = _voter;
        assetTokens = _assetTokens;
        bribeTokens = _bribeTokens;
        treasury = _treasury;
        incentives = _treasury;
        developer = _developer;
        factory = _factory;
        units = _units;
        OTOKEN = IVoter(_voter).OTOKEN();
        
        vaultToken = address(new VaultToken());
        rewardVault = IBerachainRewardVaultFactory(_vaultFactory).createRewardVault(address(vaultToken));
    }

    /**
     * @notice Claims the fees accumulated in this contract, and distributes them:
     *         - 80% of the fee is used for bribes if `autoBribe == true`.
     *         - 20% of the fee is split between the treasury and developer.
     *         If `autoBribe` is disabled, the fee is simply sent to the treasury.
     */
    function claimAndDistribute() 
        external 
        nonReentrant
    {
        uint256 balance = token.balanceOf(address(this));
        if (balance > DURATION) {
            uint256 fee = balance / 5;
            uint256 treasuryFee = fee * 3 / 5;
            uint256 developerFee = fee - treasuryFee;
            token.safeTransfer(treasury, treasuryFee);
            token.safeTransfer(developer, developerFee);
            if (autoBribe) {
                token.safeApprove(bribe, 0);
                token.safeApprove(bribe, balance - fee);
                IBribe(bribe).notifyRewardAmount(address(token), balance - fee);
                emit Plugin__ClaimedAndDistributed(balance - fee, treasuryFee, developerFee);
            } else {
                token.safeTransfer(incentives, balance - fee);
                emit Plugin__ClaimedAndDistributed(balance - fee, treasuryFee, developerFee);
            }
        }
    }

    /**
     * @notice A user "clicks" by paying the spank fee. This attempts to place them at the tail of the queue.
     *         If the queue is full, it removes the user at the head. The user’s NFT ID is used to calculate spank power.
     * @param account The account that caused this spank.
     * @param message A short message from the user, stored on-chain for fun.
     * @return upc The amount of "Ups" minted to the user as well as used to track in-game currency.
     */
    function click(address account, string calldata message)
        public
        nonReentrant
        returns (uint256)
    {
        if (account == address(0)) revert Plugin__InvalidAccount();
        if (bytes(message).length == 0) revert Plugin__InvalidMessage();
        if (bytes(message).length > MESSAGE_LENGTH) revert Plugin__InvalidMessage();

        uint256 currentIndex = tail % QUEUE_SIZE;

        if (count == QUEUE_SIZE) {
            IGauge(gauge)._withdraw(queue[head].account, queue[head].power);

            // Berachain Rewards Vault Delegate Stake
            IRewardVault(rewardVault).delegateWithdraw(queue[head].account, queue[head].power);
            VaultToken(vaultToken).burn(address(this), queue[head].power);

            emit Plugin__ClickRemoved(queue[head].account, queue[head].power, queue[head].message);
            head = (head + 1) % QUEUE_SIZE;
        }

        (uint256 upc, uint256 power) = IFactory(factory).getPower(account);

        queue[currentIndex] = Click(account, power, message);
        tail = (tail + 1) % QUEUE_SIZE;
        count = count < QUEUE_SIZE ? count + 1 : count;
        emit Plugin__ClickAdded(account, upc, queue[currentIndex].power, message);

        token.safeTransferFrom(msg.sender, address(this), entryFee);
        
        IGauge(gauge)._deposit(account, queue[currentIndex].power);

        VaultToken(vaultToken).mint(address(this), queue[currentIndex].power);
        IERC20(vaultToken).safeApprove(rewardVault, 0);
        IERC20(vaultToken).safeApprove(rewardVault, queue[currentIndex].power);
        IRewardVault(rewardVault).delegateStake(account, queue[currentIndex].power);

        IUnits(units).mint(account, upc);
        return upc;
    }

    /*----------  RESTRICTED FUNCTIONS  ---------------------------------*/

    /**
     * @notice Owner can update the treasury address.
     * @param _treasury The new treasury address.
     */
    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
        emit Plugin__TreasurySet(_treasury);
    }
    
    /**
     * @notice Owner can update the incentives address.
     * @param _incentives The new incentives address.
     */
    function setIncentives(address _incentives) external onlyOwner {
        incentives = _incentives;
        emit Plugin__IncentivesSet(_incentives);
    }

    /**
     * @notice Only the current developer can set a new developer address.
     * @param _developer The new developer address.
     */
    function setDeveloper(address _developer) external {
        if (msg.sender != developer) revert Plugin__NotAuthorized();
        developer = _developer;
        emit Plugin__DeveloperSet(_developer);
    }

    /**
     * @notice Owner can update the factory used to look up “ups” for NFTs.
     * @param _factory The new factory.
     */
    function setFactory(address _factory) external onlyOwner {
        factory = _factory;
        emit Plugin__FactorySet(_factory);
    }

    /**
     * @notice Owner can update the units contract.
     * @param _units The new units contract.
     */
    function setUnits(address _units) external onlyOwner {
        units = _units;
        emit Plugin__UnitsSet(_units);
    }

    /**
     * @notice Owner can update the spank entry fee.
     * @param _entryFee The new entry fee.
     */
    function setEntryFee(uint256 _entryFee) external onlyOwner {
        entryFee = _entryFee;
        emit Plugin__EntryFeeSet(_entryFee);
    }

    /**
     * @notice Owner can switch off/on auto-bribing functionality.
     * @param _autoBribe Whether or not to auto-bribe.
     */
    function setAutoBribe(bool _autoBribe) external onlyOwner {
        autoBribe = _autoBribe;
        emit Plugin__AutoBribeSet(_autoBribe);
    }

    /**
     * @notice Only the voter contract can set the gauge address.
     * @param _gauge The address of the gauge contract.
     */
    function setGauge(address _gauge) external onlyVoter {
        gauge = _gauge;
    }

    /**
     * @notice Only the voter contract can set the bribe address.
     * @param _bribe The address of the bribe contract.
     */
    function setBribe(address _bribe) external onlyVoter {
        bribe = _bribe;
    }

    /*----------  VIEW FUNCTIONS  ---------------------------------------*/

    /**
     * @return The cost (in BERA) to spank/join the queue.
     */
    function getPrice() external view returns (uint256) {
        return entryFee;
    }

    /**
     * @notice Queries how much power a particular address has staked in the gauge.
     */
    function balanceOf(address account) public view returns (uint256) {
        return IGauge(gauge).balanceOf(account);
    }

    /**
     * @notice Returns the total staked power in the gauge.
     */
    function totalSupply() public view returns (uint256) {
        return IGauge(gauge).totalSupply();
    }

    /**
     * @return Address of the ERC20 token used for spank fees.
     */
    function getToken() public view virtual returns (address) {
        return address(token);
    }

    /**
     * @return Returns a protocol name string for display in the UI.
     */
    function getProtocol() public view virtual returns (string memory) {
        return PROTOCOL;
    }

    /**
     * @return Returns a plugin name string.
     */
    function getName() public view virtual returns (string memory) {
        return NAME;
    }

    /**
     * @return The voter contract address.
     */
    function getVoter() public view returns (address) {
        return voter;
    }

    /**
     * @return The gauge contract address used for staking power.
     */
    function getGauge() public view returns (address) {
        return gauge;
    }

    /**
     * @return The bribe contract address used to distribute bribes to hiBERO voters.
     */
    function getBribe() public view returns (address) {
        return bribe;
    }

    /**
     * @return The list of asset tokens associated with this plugin.
     */
    function getAssetTokens() public view virtual returns (address[] memory) {
        return assetTokens;
    }

    /**
     * @return The list of bribe tokens used when calling `notifyRewardAmount`.
     */
    function getBribeTokens() public view returns (address[] memory) {
        return bribeTokens;
    }

    /**
     * @return The address of the VaultToken contract used in this plugin.
     */
    function getVaultToken() public view returns (address) {
        return vaultToken;
    }

    /**
     * @return The address of the specialized RewardVault contract tied to our vaultToken.
     */
    function getRewardVault() public view returns (address) {
        return rewardVault;
    }

    /**
     * @return How many occupants are currently in the queue.
     */
    function getQueueSize() public view returns (uint256) {
        return count;
    }

    /**
     * @notice Returns the Click struct for a given index in the circular buffer.
     * @param index The queue index (0-based from the head).
     */
    function getClick(uint256 index) public view returns (Click memory) {
        return queue[(head + index) % QUEUE_SIZE];
    }

    /**
     * @notice Returns a slice of the queue from `start` to `end` (exclusive).
     * @param start The starting index (0-based from head).
     * @param end The end index (exclusive, 0-based from head).
     * @return An array of Click structs in the specified range.
     */
    function getQueueFragment(uint256 start, uint256 end) public view returns (Click[] memory) {
        Click[] memory result = new Click[](end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = queue[(head + i) % QUEUE_SIZE];
        }
        return result;
    }

    /**
     * @notice Returns the entire queue (all `count` occupants) as an array of Click structs.
     */
    function getQueue() public view returns (Click[] memory) {
        Click[] memory result = new Click[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = queue[(head + i) % QUEUE_SIZE];
        }
        return result;
    }

}