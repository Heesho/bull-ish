// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import { IEntropyConsumer } from "@pythnetwork/entropy-sdk-solidity/IEntropyConsumer.sol";
import { IEntropy } from "@pythnetwork/entropy-sdk-solidity/IEntropy.sol";

interface IGauge {
    function _deposit(address account, uint256 amount) external;
    function _withdraw(address account, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

interface IBribe {
    function notifyRewardAmount(address token, uint amount) external;
}

interface IVoter {
    function OTOKEN() external view returns (address);
}

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

contract WheelPlugin is IEntropyConsumer, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /*----------  CONSTANTS  --------------------------------------------*/

    uint256 public constant QUEUE_SIZE = 300;
    uint256 public constant DURATION = 7 days;
    uint256 public constant MESSAGE_LENGTH = 69;
    string public constant NAME = "BULL ISH V3";
    string public constant PROTOCOL = "Bullas";

    /*----------  STATE VARIABLES  --------------------------------------*/

    IERC20 private immutable token;
    address private immutable OTOKEN;
    address private immutable voter;
    address private gauge;
    address private bribe;
    address[] private assetTokens;
    address[] private bribeTokens;
    address public immutable vaultToken;
    address public immutable rewardVault;

    address public factory;
    address public units;

    address public treasury;
    address public incentives;
    address public developer;

    bool public autoBribe = true;

    struct Slot {
        address account;
        uint256 power;
    }

    IEntropy public entropy;
    uint256 public playPrice = 0.69 ether;
    uint256 public wheelSize = 100;
    mapping(uint256 => Slot) public wheel_Slot;
    mapping(uint64 => address) public sequence_Account;

    /*----------  ERRORS ------------------------------------------------*/

    error Plugin__InvalidAccount();
    error Plugin__InvalidZeroInput();
    error Plugin__NotAuthorizedVoter();
    error Plugin__NotAuthorized();
    error Plugin__InvalidWheelSize();
    error Plugin__InsufficientPayment();
    error Plugin__InvalidSequence();

    /*----------  EVENTS ------------------------------------------------*/

    event Plugin__ClaimedAndDistributed(uint256 bribeFee, uint256 treasuryFee, uint256 developerFee);
    event Plugin__PlayRequested(uint64 sequenceNumber, address indexed account);
    event Plugin__Played(address indexed account, uint256 upc, uint256 power);
    event Plugin__SlotAdded(address indexed account, uint256 power);
    event Plugin__SlotRemoved(address indexed account, uint256 power);
    event Plugin__WheelSizeSet(uint256 wheelSize);
    event Plugin__TreasurySet(address treasury);
    event Plugin__IncentivesSet(address incentives);
    event Plugin__DeveloperSet(address developer);
    event Plugin__FactorySet(address factory);
    event Plugin__UnitsSet(address units);
    event Plugin__PlayPriceSet(uint256 playPrice);
    event Plugin__AutoBribeSet(bool autoBribe);

    /*----------  MODIFIERS  --------------------------------------------*/

    modifier nonZeroInput(uint256 _amount) {
        if (_amount == 0) revert Plugin__InvalidZeroInput();
        _;
    }

    modifier onlyVoter() {
        if (msg.sender != voter) revert Plugin__NotAuthorizedVoter();
        _;
    }

    /*----------  FUNCTIONS  --------------------------------------------*/

    constructor(
        address _token,
        address _voter,
        address[] memory _assetTokens,
        address[] memory _bribeTokens,
        address _treasury,
        address _developer,
        address _factory,
        address _units,
        address _vaultFactory,
        address _entropy
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
        entropy = IEntropy(_entropy);
        OTOKEN = IVoter(_voter).OTOKEN();
        
        vaultToken = address(new VaultToken());
        rewardVault = IBerachainRewardVaultFactory(_vaultFactory).createRewardVault(address(vaultToken));
    }

    function claimAndDistribute() 
        external 
        nonReentrant
    {
        uint256 balance = address(this).balance;
        if (balance > DURATION) {
            uint256 fee = balance / 5;
            uint256 treasuryFee = fee * 3 / 5;
            uint256 developerFee = fee - treasuryFee;
            IWBERA(address(token)).deposit{value: balance}();

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

    function play(address account, bytes32 userRandomNumber) external payable nonReentrant {
        if (account == address(0)) revert Plugin__InvalidAccount();
        if (msg.value < playPrice) revert Plugin__InsufficientPayment();

        if (address(entropy) != address(0)) {
            address entropyProvider = entropy.getDefaultProvider();
            uint256 fee = entropy.getFee(entropyProvider);
            if (msg.value < playPrice + fee) revert Plugin__InsufficientPayment();
            uint64 sequenceNumber = entropy.requestWithCallback{value: fee}(entropyProvider, userRandomNumber);
            sequence_Account[sequenceNumber] = account;
            emit Plugin__PlayRequested(sequenceNumber, account);
        } else {
            userRandomNumber = keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender));
            mockCallback(account, userRandomNumber);
            emit Plugin__PlayRequested(0, account);
        }

    }

    receive() external payable {}

    /*----------  RESTRICTED FUNCTIONS  ---------------------------------*/

    function entropyCallback(uint64 sequenceNumber, address, bytes32 randomNumber) internal override {
        address player = sequence_Account[sequenceNumber];
        if (player == address(0)) revert Plugin__InvalidSequence();

        uint256 wheelIndex = uint256(randomNumber) % wheelSize;
        Slot memory slot = wheel_Slot[wheelIndex];
        if (slot.account != address(0)) {
            IGauge(gauge)._withdraw(slot.account, slot.power);
            IRewardVault(rewardVault).delegateWithdraw(slot.account, slot.power);
            VaultToken(vaultToken).burn(address(this), slot.power);
            emit Plugin__SlotRemoved(slot.account, slot.power);
        }

        (uint256 upc, uint256 power) = IFactory(factory).getPower(player);

        wheel_Slot[wheelIndex] = Slot(player, power);
        emit Plugin__SlotAdded(player, power);

        IGauge(gauge)._deposit(player, power);
        VaultToken(vaultToken).mint(address(this), power);
        IERC20(vaultToken).safeApprove(rewardVault, 0);
        IERC20(vaultToken).safeApprove(rewardVault, power);
        IRewardVault(rewardVault).delegateStake(player, power);

        IUnits(units).mint(player, upc);

        delete sequence_Account[sequenceNumber];
        emit Plugin__Played(player, upc, power);
    }

    function mockCallback(address player, bytes32 randomNumber) internal {
        uint256 wheelIndex = uint256(randomNumber) % wheelSize;
        Slot memory slot = wheel_Slot[wheelIndex];
        if (slot.account != address(0)) {
            IGauge(gauge)._withdraw(slot.account, slot.power);
            IRewardVault(rewardVault).delegateWithdraw(slot.account, slot.power);
            VaultToken(vaultToken).burn(address(this), slot.power);
            emit Plugin__SlotRemoved(slot.account, slot.power);
        }

        (uint256 upc, uint256 power) = IFactory(factory).getPower(player);

        wheel_Slot[wheelIndex] = Slot(player, power);
        emit Plugin__SlotAdded(player, power);
        
        IGauge(gauge)._deposit(player, power);
        VaultToken(vaultToken).mint(address(this), power);
        IERC20(vaultToken).safeApprove(rewardVault, 0);
        IERC20(vaultToken).safeApprove(rewardVault, power);
        IRewardVault(rewardVault).delegateStake(player, power);

        IUnits(units).mint(player, upc);
        emit Plugin__Played(player, upc, power);
    }

    function setWheelSize(uint256 _wheelSize) external onlyOwner {
        if (_wheelSize <= wheelSize) revert Plugin__InvalidWheelSize();
        wheelSize = _wheelSize;
        emit Plugin__WheelSizeSet(_wheelSize);
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
        emit Plugin__TreasurySet(_treasury);
    }
    
    function setIncentives(address _incentives) external onlyOwner {
        incentives = _incentives;
        emit Plugin__IncentivesSet(_incentives);
    }

    function setDeveloper(address _developer) external {
        if (msg.sender != developer) revert Plugin__NotAuthorized();
        developer = _developer;
        emit Plugin__DeveloperSet(_developer);
    }

    function setFactory(address _factory) external onlyOwner {
        factory = _factory;
        emit Plugin__FactorySet(_factory);
    }

    function setUnits(address _units) external onlyOwner {
        units = _units;
        emit Plugin__UnitsSet(_units);
    }

    function setPlayPrice(uint256 _playPrice) external onlyOwner {
        playPrice = _playPrice;
        emit Plugin__PlayPriceSet(_playPrice);
    }

    function setAutoBribe(bool _autoBribe) external onlyOwner {
        autoBribe = _autoBribe;
        emit Plugin__AutoBribeSet(_autoBribe);
    }

    function setGauge(address _gauge) external onlyVoter {
        gauge = _gauge;
    }

    function setBribe(address _bribe) external onlyVoter {
        bribe = _bribe;
    }

    /*----------  VIEW FUNCTIONS  ---------------------------------------*/

    function balanceOf(address account) public view returns (uint256) {
        return IGauge(gauge).balanceOf(account);
    }

    function totalSupply() public view returns (uint256) {
        return IGauge(gauge).totalSupply();
    }

    function getToken() public view virtual returns (address) {
        return address(token);
    }

    function getProtocol() public view virtual returns (string memory) {
        return PROTOCOL;
    }

    function getName() public view virtual returns (string memory) {
        return NAME;
    }

    function getVoter() public view returns (address) {
        return voter;
    }

    function getGauge() public view returns (address) {
        return gauge;
    }

    function getBribe() public view returns (address) {
        return bribe;
    }

    function getAssetTokens() public view virtual returns (address[] memory) {
        return assetTokens;
    }

    function getBribeTokens() public view returns (address[] memory) {
        return bribeTokens;
    }

    function getVaultToken() public view returns (address) {
        return vaultToken;
    }

    function getRewardVault() public view returns (address) {
        return rewardVault;
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