// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {IEntropyConsumer} from "@pythnetwork/entropy-sdk-solidity/IEntropyConsumer.sol";
import {IEntropy} from "@pythnetwork/entropy-sdk-solidity/IEntropy.sol";

interface IFactory {
    function getPower(address account) external view returns (uint256 upc, uint256 power);
}

interface IUnits {
    function mint(address account, uint256 amount) external;
}

interface IBerachainRewardVaultFactory {
    function createRewardVault(address _vaultToken) external returns (address);
}

interface IRewardVault {
    function getDelegateStake(address account, address delegate) external view returns (uint256);
    function getTotalDelegateStaked(address account) external view returns (uint256);
    function delegateStake(address account, uint256 amount) external;
    function delegateWithdraw(address account, uint256 amount) external;
}

interface IWBERA {
    function deposit() external payable;
}

/// @title VaultToken — Internal Staking Receipt for Wheel
/// @notice ERC-20 minted/burned exclusively by the Wheel contract to represent a player's
///         staked power in the Berachain reward vault. Not intended for direct user interaction.
/// @dev Ownership is transferred to the Wheel at deploy time so only it can mint/burn.
contract VaultToken is ERC20, Ownable {
    constructor() ERC20("BULL ISH V3", "BULL ISH V3") {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}

/// @title Wheel — Spin-to-Earn with Berachain PoL Delegation
/// @notice Players pay BERA to spin a randomized wheel. The winning slot is determined by
///         Pyth VRF (or a mock fallback), and the player's Factory-derived power score is
///         delegate-staked into a Berachain reward vault for BGT yield.
/// @dev The wheel has a fixed number of slots. Each spin randomly picks a slot; if it is
///      already occupied, the previous occupant's stake is withdrawn before the new player
///      is placed. BERA revenue is split between protocol incentives (80% default) and
///      team wallets (20% default, subdivided 40/40/20 among treasury/dev/community).
contract Wheel is IEntropyConsumer, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /// @notice Upper bound for `feeSplit` — team can take at most 30% of BERA revenue.
    uint256 public constant MAX_FEE_SPLIT = 30;

    /// @notice Lower bound for `feeSplit` — team must take at least 4% of BERA revenue.
    uint256 public constant MIN_FEE_SPLIT = 4;

    /// @notice Percentage base (100) for fee arithmetic.
    uint256 public constant DIVISOR = 100;

    /// @notice WBERA (or WETH on testnet) address. BERA is wrapped before distribution.
    address public immutable base;

    /// @notice Internal ERC-20 receipt token minted/burned to track power staked in the vault.
    address public immutable vaultToken;

    /// @notice Berachain native reward vault where VaultTokens are delegate-staked for BGT.
    address public immutable rewardVault;

    /// @notice Factory contract used to read a player's UPC and power score.
    address public factory;

    /// @notice MOOLA token. Minted as a reward to the spinner.
    address public units;

    /// @notice Recipient of the incentives portion of BERA fees (~80%).
    address public incentives;

    /// @notice Recipient of the treasury portion of the team fee (40% of feeSplit).
    address public treasury;

    /// @notice Recipient of the developer portion of the team fee (40% of feeSplit).
    address public developer;

    /// @notice Recipient of the community portion of the team fee (20% of feeSplit).
    address public community;

    /// @notice Pyth Entropy contract for verifiable randomness. address(0) enables mock fallback.
    IEntropy public immutable entropy;

    /// @notice BERA cost per spin (default 0.69 BERA).
    uint256 public playPrice = 0.69 ether;

    /// @notice Total number of slots on the wheel. Can only be increased.
    uint256 public wheelSize = 100;

    /// @notice Percentage of BERA revenue allocated to the team (remainder goes to incentives).
    uint256 public feeSplit = 20;

    /// @notice Mapping from slot index to occupant address and their staked power.
    mapping(uint256 => Slot) public wheel_Slot;

    /// @notice Maps Pyth sequence numbers to the player who initiated the spin.
    mapping(uint64 => address) public sequence_Account;

    /// @notice Disqualified accounts are blocked from spinning (anti-abuse).
    mapping(address => bool) public account_Disqualified;

    /// @dev Represents a single wheel slot: the occupant and the amount of power they have staked.
    struct Slot {
        address account;
        uint256 power;
    }

    error Wheel__InvalidAccount();
    error Wheel__NotAuthorized();
    error Wheel__InsufficientPayment();
    error Wheel__InvalidSequence();
    error Wheel__InvalidWheelSize();
    error Wheel__InvalidFeeSplit();
    error Wheel__Disqualified();
    error Wheel__ZeroAddress();

    event Wheel__Distribute(uint256 incentivesFee, uint256 treasuryFee, uint256 developerFee, uint256 communityFee);
    event Wheel__PlayRequested(uint64 sequenceNumber, address indexed account);
    event Wheel__Played(address indexed account, uint256 upc, uint256 power);
    event Wheel__SlotAdded(address indexed account, uint256 power);
    event Wheel__SlotRemoved(address indexed account, uint256 power);
    event Wheel__TreasurySet(address treasury);
    event Wheel__IncentivesSet(address incentives);
    event Wheel__DeveloperSet(address developer);
    event Wheel__CommunitySet(address community);
    event Wheel__FactorySet(address factory);
    event Wheel__UnitsSet(address units);
    event Wheel__WheelSizeSet(uint256 wheelSize);
    event Wheel__PlayPriceSet(uint256 playPrice);
    event Wheel__FeeSplitSet(uint256 feeSplit);
    event Wheel__DisqualifiedSet(address account, bool disqualified);

    modifier notZeroAddress(address _address) {
        if (_address == address(0)) revert Wheel__ZeroAddress();
        _;
    }

    /// @param _base         WBERA / WETH address.
    /// @param _incentives   Address receiving the incentives share of BERA fees.
    /// @param _treasury     Address receiving the treasury share.
    /// @param _developer    Address receiving the developer share.
    /// @param _community    Address receiving the community share.
    /// @param _factory      Factory contract for power lookups.
    /// @param _units        MOOLA token to mint as spin rewards.
    /// @param _vaultFactory Berachain RewardVaultFactory to create the staking vault.
    /// @param _entropy      Pyth Entropy contract (address(0) for mock mode).
    constructor(
        address _base,
        address _incentives,
        address _treasury,
        address _developer,
        address _community,
        address _factory,
        address _units,
        address _vaultFactory,
        address _entropy
    ) {
        base = _base;
        incentives = _incentives;
        treasury = _treasury;
        developer = _developer;
        community = _community;
        factory = _factory;
        units = _units;
        entropy = IEntropy(_entropy);

        vaultToken = address(new VaultToken());
        rewardVault = IBerachainRewardVaultFactory(_vaultFactory).createRewardVault(address(vaultToken));
    }

    /// @notice Wrap all accumulated BERA to WBERA and distribute to protocol wallets.
    /// @dev Split: `feeSplit`% goes to the team (40% treasury, 40% developer, 20% community),
    ///      the remainder goes to `incentives` for Berachain PoL reward gauges.
    ///      Callable by anyone — acts on the contract's entire BERA balance.
    function distribute() external nonReentrant {
        uint256 balance = address(this).balance;
        uint256 fee = balance * feeSplit / DIVISOR;
        uint256 treasuryFee = fee * 2 / 5;
        uint256 developerFee = fee * 2 / 5;
        uint256 communityFee = fee * 1 / 5;
        uint256 incentivesFee = balance - fee;
        IWBERA(base).deposit{value: balance}();

        IERC20(base).safeTransfer(treasury, treasuryFee);
        IERC20(base).safeTransfer(developer, developerFee);
        IERC20(base).safeTransfer(incentives, incentivesFee);
        IERC20(base).safeTransfer(community, communityFee);

        emit Wheel__Distribute(incentivesFee, treasuryFee, developerFee, communityFee);
    }

    /// @notice Pay BERA to spin the wheel. Requests Pyth VRF for the random slot index.
    /// @dev If Pyth Entropy is configured (address != 0), a VRF callback is requested and
    ///      the result arrives asynchronously in `entropyCallback`. Otherwise falls through
    ///      to `mockCallback` with pseudo-random data for local/testnet use.
    ///      msg.value must cover `playPrice` + Pyth provider fee (if applicable).
    /// @param account          The player to credit (must not be address(0) or disqualified).
    /// @param userRandomNumber Player-supplied entropy seed mixed into the Pyth request.
    function play(address account, bytes32 userRandomNumber) external payable nonReentrant {
        if (account == address(0)) revert Wheel__InvalidAccount();
        if (msg.value < playPrice) revert Wheel__InsufficientPayment();
        if (account_Disqualified[account]) revert Wheel__Disqualified();

        if (address(entropy) != address(0)) {
            address entropyProvider = entropy.getDefaultProvider();
            uint256 fee = entropy.getFee(entropyProvider);
            if (msg.value < playPrice + fee) revert Wheel__InsufficientPayment();
            uint64 sequenceNumber = entropy.requestWithCallback{value: fee}(entropyProvider, userRandomNumber);
            sequence_Account[sequenceNumber] = account;
            emit Wheel__PlayRequested(sequenceNumber, account);
        } else {
            userRandomNumber = keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender));
            mockCallback(account, userRandomNumber);
            emit Wheel__PlayRequested(0, account);
        }
    }

    receive() external payable {}

    /// @dev Pyth Entropy callback — invoked by the Entropy contract with the verified random number.
    ///      Picks a slot via `randomNumber % wheelSize`. If the slot is occupied, the previous
    ///      occupant's power is unstaked from the reward vault. The new player's power is then
    ///      delegate-staked and they receive UPC worth of MOOLA as a spin reward.
    /// @param sequenceNumber Pyth request identifier used to look up the player address.
    /// @param randomNumber   Verified random value from Pyth VRF.
    function entropyCallback(uint64 sequenceNumber, address, bytes32 randomNumber) internal override {
        address player = sequence_Account[sequenceNumber];
        if (player == address(0)) revert Wheel__InvalidSequence();

        uint256 wheelIndex = uint256(randomNumber) % wheelSize;
        Slot memory slot = wheel_Slot[wheelIndex];
        if (slot.account != address(0)) {
            IRewardVault(rewardVault).delegateWithdraw(slot.account, slot.power);
            VaultToken(vaultToken).burn(address(this), slot.power);
            emit Wheel__SlotRemoved(slot.account, slot.power);
        }

        (uint256 upc, uint256 power) = IFactory(factory).getPower(player);

        wheel_Slot[wheelIndex] = Slot(player, power);
        emit Wheel__SlotAdded(player, power);

        VaultToken(vaultToken).mint(address(this), power);
        IERC20(vaultToken).safeApprove(rewardVault, 0);
        IERC20(vaultToken).safeApprove(rewardVault, power);
        IRewardVault(rewardVault).delegateStake(player, power);

        IUnits(units).mint(player, upc);

        delete sequence_Account[sequenceNumber];

        emit Wheel__Played(player, upc, power);
    }

    /// @dev Mock version of the entropy callback for local/testnet environments where
    ///      Pyth Entropy is unavailable. Same slot-replacement and staking logic.
    /// @param player       The player to place on the wheel.
    /// @param randomNumber Pseudo-random value generated from block data.
    function mockCallback(address player, bytes32 randomNumber) internal {
        uint256 wheelIndex = uint256(randomNumber) % wheelSize;
        Slot memory slot = wheel_Slot[wheelIndex];
        if (slot.account != address(0)) {
            IRewardVault(rewardVault).delegateWithdraw(slot.account, slot.power);
            VaultToken(vaultToken).burn(address(this), slot.power);
            emit Wheel__SlotRemoved(slot.account, slot.power);
        }

        (uint256 upc, uint256 power) = IFactory(factory).getPower(player);

        wheel_Slot[wheelIndex] = Slot(player, power);
        emit Wheel__SlotAdded(player, power);

        VaultToken(vaultToken).mint(address(this), power);
        IERC20(vaultToken).safeApprove(rewardVault, 0);
        IERC20(vaultToken).safeApprove(rewardVault, power);
        IRewardVault(rewardVault).delegateStake(player, power);

        IUnits(units).mint(player, upc);
        emit Wheel__Played(player, upc, power);
    }

    /// @notice Increase the number of wheel slots. Cannot decrease to prevent losing occupied slots.
    /// @param _wheelSize New wheel size (must be strictly greater than the current size).
    function setWheelSize(uint256 _wheelSize) external onlyOwner {
        if (_wheelSize <= wheelSize) revert Wheel__InvalidWheelSize();
        wheelSize = _wheelSize;
        emit Wheel__WheelSizeSet(_wheelSize);
    }

    /// @notice Update the incentives wallet (receives the majority of BERA revenue).
    /// @param _incentives New incentives address.
    function setIncentives(address _incentives) external notZeroAddress(_incentives) onlyOwner {
        incentives = _incentives;
        emit Wheel__IncentivesSet(_incentives);
    }

    /// @notice Update the treasury wallet.
    /// @param _treasury New treasury address.
    function setTreasury(address _treasury) external notZeroAddress(_treasury) onlyOwner {
        treasury = _treasury;
        emit Wheel__TreasurySet(_treasury);
    }

    /// @notice Update the developer wallet. Only callable by the current developer (self-custody).
    /// @param _developer New developer address.
    function setDeveloper(address _developer) external notZeroAddress(_developer) {
        if (msg.sender != developer) revert Wheel__NotAuthorized();
        developer = _developer;
        emit Wheel__DeveloperSet(_developer);
    }

    /// @notice Update the community wallet.
    /// @param _community New community address.
    function setCommunity(address _community) external notZeroAddress(_community) onlyOwner {
        community = _community;
        emit Wheel__CommunitySet(_community);
    }

    /// @notice Point to a new Factory contract for power lookups.
    /// @param _factory New Factory address.
    function setFactory(address _factory) external notZeroAddress(_factory) onlyOwner {
        factory = _factory;
        emit Wheel__FactorySet(_factory);
    }

    /// @notice Point to a new MOOLA token contract.
    /// @param _units New MOOLA address.
    function setUnits(address _units) external notZeroAddress(_units) onlyOwner {
        units = _units;
        emit Wheel__UnitsSet(_units);
    }

    /// @notice Update the BERA cost per spin.
    /// @param _playPrice New price in wei.
    function setPlayPrice(uint256 _playPrice) external onlyOwner {
        playPrice = _playPrice;
        emit Wheel__PlayPriceSet(_playPrice);
    }

    /// @notice Adjust the team vs. incentives fee split percentage.
    /// @dev Bounded by MIN_FEE_SPLIT (4%) and MAX_FEE_SPLIT (30%) to protect players.
    /// @param _feeSplit New team percentage (remainder goes to incentives).
    function setFeeSplit(uint256 _feeSplit) external onlyOwner {
        if (_feeSplit > MAX_FEE_SPLIT || _feeSplit < MIN_FEE_SPLIT) revert Wheel__InvalidFeeSplit();
        feeSplit = _feeSplit;
        emit Wheel__FeeSplitSet(_feeSplit);
    }

    /// @notice Ban or unban an account from spinning the wheel.
    /// @param account       Address to disqualify or re-qualify.
    /// @param _disqualified `true` to ban, `false` to allow.
    function setDisqualified(address account, bool _disqualified) external onlyOwner {
        account_Disqualified[account] = _disqualified;
        emit Wheel__DisqualifiedSet(account, _disqualified);
    }

    /// @notice Returns total power delegate-staked on behalf of `account` in the reward vault.
    /// @param account Player address.
    /// @return Staked power balance.
    function balanceOf(address account) public view returns (uint256) {
        return IRewardVault(rewardVault).getDelegateStake(account, address(this));
    }

    /// @notice Returns total power delegate-staked across all players in the reward vault.
    /// @return Aggregate staked power.
    function totalSupply() public view returns (uint256) {
        return IRewardVault(rewardVault).getTotalDelegateStaked(address(this));
    }

    /// @notice Read a single wheel slot by index.
    /// @param index Slot position on the wheel.
    /// @return The Slot struct (account + power) at the given index.
    function getSlot(uint256 index) public view returns (Slot memory) {
        return wheel_Slot[index];
    }

    /// @notice Read a contiguous range of wheel slots. Useful for paginated frontend rendering.
    /// @param start Start index (inclusive).
    /// @param end   End index (exclusive).
    /// @return Array of Slot structs in the [start, end) range.
    function getWheelFragment(uint256 start, uint256 end) public view returns (Slot[] memory) {
        Slot[] memory result = new Slot[](end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = wheel_Slot[i];
        }
        return result;
    }

    /// @notice Read all wheel slots in a single call.
    /// @return Array of all `wheelSize` Slot structs.
    function getWheel() public view returns (Slot[] memory) {
        Slot[] memory result = new Slot[](wheelSize);
        for (uint256 i = 0; i < wheelSize; i++) {
            result[i] = wheel_Slot[i];
        }
        return result;
    }

    /// @dev Required by IEntropyConsumer — returns the Pyth Entropy contract address.
    function getEntropy() internal view override returns (address) {
        return address(entropy);
    }
}
