// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import { IEntropyConsumer } from "@pythnetwork/entropy-sdk-solidity/IEntropyConsumer.sol";
import { IEntropy } from "@pythnetwork/entropy-sdk-solidity/IEntropy.sol";

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

contract VaultToken is ERC20, Ownable {

    constructor() ERC20("BULL ISH V3", "BULL ISH V3") {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}

contract Wheel is IEntropyConsumer, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant QUEUE_SIZE = 300;
    uint256 public constant MESSAGE_LENGTH = 69;
    uint256 public constant MAX_FEE_SPLIT = 50;
    uint256 public constant MIN_FEE_SPLIT = 4;
    uint256 public constant DIVISOR = 100;

    address public immutable base;
    address public immutable vaultToken;
    address public immutable rewardVault;

    address public factory;
    address public units;

    address public incentives;
    address public treasury;
    address public developer;
    address public community;

    IEntropy public entropy;
    uint256 public playPrice = 0.69 ether;
    uint256 public wheelSize = 100;
    uint256 public feeSplit = 20;
    
    mapping(uint256 => Slot) public wheel_Slot;
    mapping(uint64 => address) public sequence_Account;
    mapping(address => bool) public account_Disqualified;

    struct Slot {
        address account;
        uint256 power;
    }

    error Wheel__InvalidAccount();
    error Wheel__InvalidZeroInput();
    error Wheel__NotAuthorized();
    error Wheel__InsufficientPayment();
    error Wheel__InvalidSequence();
    error Wheel__InvalidWheelSize();
    error Wheel__InvalidFeeSplit();
    error Wheel__Disqualified();

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

    modifier nonZeroInput(uint256 _amount) {
        if (_amount == 0) revert Wheel__InvalidZeroInput();
        _;
    }

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

    function distribute() 
        external 
        nonReentrant
    {
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

    function setWheelSize(uint256 _wheelSize) external onlyOwner {
        if (_wheelSize <= wheelSize) revert Wheel__InvalidWheelSize();
        wheelSize = _wheelSize;
        emit Wheel__WheelSizeSet(_wheelSize);
    }

    function setIncentives(address _incentives) external onlyOwner {
        incentives = _incentives;
        emit Wheel__IncentivesSet(_incentives);
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
        emit Wheel__TreasurySet(_treasury);
    }
    
    function setDeveloper(address _developer) external {
        if (msg.sender != developer) revert Wheel__NotAuthorized();
        developer = _developer;
        emit Wheel__DeveloperSet(_developer);
    }

    function setCommunity(address _community) external onlyOwner {
        community = _community;
        emit Wheel__CommunitySet(_community);
    }

    function setFactory(address _factory) external onlyOwner {
        factory = _factory;
        emit Wheel__FactorySet(_factory);
    }

    function setUnits(address _units) external onlyOwner {
        units = _units;
        emit Wheel__UnitsSet(_units);
    }

    function setPlayPrice(uint256 _playPrice) external onlyOwner {
        playPrice = _playPrice;
        emit Wheel__PlayPriceSet(_playPrice);
    }

    function setFeeSplit(uint256 _feeSplit) external onlyOwner {
        if (_feeSplit > MAX_FEE_SPLIT || _feeSplit < MIN_FEE_SPLIT) revert Wheel__InvalidFeeSplit();
        feeSplit = _feeSplit;
        emit Wheel__FeeSplitSet(_feeSplit);
    }

    function setDisqualified(address account, bool _disqualified) external onlyOwner {
        account_Disqualified[account] = _disqualified;
        emit Wheel__DisqualifiedSet(account, _disqualified);
    }

    function balanceOf(address account) public view returns (uint256) {
        return IRewardVault(rewardVault).getDelegateStake(account, address(this));
    }

    function totalSupply() public view returns (uint256) {
        return IRewardVault(rewardVault).getTotalDelegateStaked(address(this));
    }

    function getSlot(uint256 index) public view returns (Slot memory) {
        return wheel_Slot[index];
    }

    function getWheelFragment(uint256 start, uint256 end) public view returns (Slot[] memory) {
        Slot[] memory result = new Slot[](end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = wheel_Slot[i];
        }
        return result;
    }

    function getWheel() public view returns (Slot[] memory) {
        Slot[] memory result = new Slot[](wheelSize);
        for (uint256 i = 0; i < wheelSize; i++) {
            result[i] = wheel_Slot[i];
        }
        return result;
    }

    function getEntropy() internal view override returns (address) {
        return address(entropy);
    }

}