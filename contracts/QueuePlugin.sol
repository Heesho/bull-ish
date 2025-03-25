// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

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
    function tokenId_Ups(uint256 tokenId) external view returns (uint256);
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

contract VaultToken is ERC20, Ownable {
    constructor() ERC20("BULL ISH V2", "BULL ISH V2") {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}

/**
 * @title QueuePlugin
 * @author heesho
*/
contract QueuePlugin is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /*----------  CONSTANTS  --------------------------------------------*/

    uint256 public constant BASE_UPC = 1 ether;
    uint256 public constant QUEUE_SIZE = 300;
    uint256 public constant DURATION = 7 days;
    uint256 public constant MESSAGE_LENGTH = 69;
    
    string public constant NAME = "BULL ISH V2";
    string public constant PROTOCOL = "Bullas";

    /*----------  STATE VARIABLES  --------------------------------------*/

    IERC20 private immutable token;
    address private immutable OTOKEN;
    address private immutable voter;
    address private gauge;
    address private bribe;
    address[] private assetTokens;
    address[] private bribeTokens;

    address public immutable key;
    address public immutable vaultToken;
    address public immutable rewardVault;

    address public factory;
    address public units;
    address public treasury;
    address public developer;

    uint256 public maxPower = 1 ether;
    uint256 public entryFee = 0.04269 ether;
    bool public autoBribe = true;

    struct Click {
        uint256 tokenId;
        uint256 power;
        address account;
        string message;
    }

    mapping(uint256 => Click) public queue;
    uint256 public head = 0;
    uint256 public tail = 0;
    uint256 public count = 0;

    /*----------  ERRORS ------------------------------------------------*/

    error Plugin__InvalidZeroInput();
    error Plugin__NotAuthorizedVoter();
    error Plugin__NotAuthorized();
    error Plugin__InvalidTokenId();
    error Plugin__InvalidMessage();

    /*----------  EVENTS ------------------------------------------------*/

    event Plugin__ClaimedAndDistributed(uint256 bribeFee, uint256 treasuryFee, uint256 developerFee);
    event Plugin__ClickAdded(uint256 tokenId, address author, uint256 mintAmount, uint256 power, string message);
    event Plugin__ClickRemoved(uint256 tokenId, address author, uint256 power, string message);
    event Plugin__TreasurySet(address treasury);
    event Plugin__DeveloperSet(address developer);
    event Plugin__FactorySet(address factory);
    event Plugin__UnitsSet(address units);
    event Plugin__EntryFeeSet(uint256 fee);
    event Plugin__AutoBribeSet(bool autoBribe);
    event Plugin__MaxPowerSet(uint256 maxPower);

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
        address _key,
        address _vaultFactory
    ) {
        token = IERC20(_token);
        voter = _voter;
        assetTokens = _assetTokens;
        bribeTokens = _bribeTokens;
        treasury = _treasury;
        developer = _developer;
        factory = _factory;
        units = _units;
        key = _key;
        OTOKEN = IVoter(_voter).OTOKEN();
        
        vaultToken = address(new VaultToken());
        rewardVault = IBerachainRewardVaultFactory(_vaultFactory).createRewardVault(address(vaultToken));
    }

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
                token.safeTransfer(treasury, balance - fee);
                emit Plugin__ClaimedAndDistributed(0, balance + treasuryFee - fee, developerFee);
            }
        }
    }

    function click(uint256 tokenId, string calldata message)
        public
        nonReentrant
        returns (uint256)
    {
        if (bytes(message).length == 0) revert Plugin__InvalidMessage();
        if (bytes(message).length > MESSAGE_LENGTH) revert Plugin__InvalidMessage();

        uint256 currentIndex = tail % QUEUE_SIZE;
        address account = IERC721(key).ownerOf(tokenId);
        if (account == address(0)) revert Plugin__InvalidTokenId();

        if (count == QUEUE_SIZE) {
            IGauge(gauge)._withdraw(queue[head].account, queue[head].power);

            // Berachain Rewards Vault Delegate Stake
            IRewardVault(rewardVault).delegateWithdraw(queue[head].account, queue[head].power);
            VaultToken(vaultToken).burn(address(this), queue[head].power);

            emit Plugin__ClickRemoved(queue[head].tokenId, queue[head].account, queue[head].power, queue[head].message);
            head = (head + 1) % QUEUE_SIZE;
        }

        (uint256 upc, uint256 power) = getPower(tokenId);

        queue[currentIndex] = Click(tokenId, power, account, message);
        tail = (tail + 1) % QUEUE_SIZE;
        count = count < QUEUE_SIZE ? count + 1 : count;
        emit Plugin__ClickAdded(tokenId, account, upc, queue[currentIndex].power, message);

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

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
        emit Plugin__TreasurySet(_treasury);
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

    function setMaxPower(uint256 _maxPower) external onlyOwner {
        maxPower = _maxPower;
        emit Plugin__MaxPowerSet(_maxPower);
    }

    function setEntryFee(uint256 _entryFee) external onlyOwner {
        entryFee = _entryFee;
        emit Plugin__EntryFeeSet(_entryFee);
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

    function getPrice() external view returns (uint256) {
        return entryFee;
    }

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

    function getPower(uint256 tokenId) public view returns (uint256 upc, uint256 power) {
        upc = BASE_UPC + IFactory(factory).tokenId_Ups(tokenId);
        power = (upc * 1e18).sqrt();
        if (power > maxPower) {
            power = maxPower;
        }
    }

    function getQueueSize() public view returns (uint256) {
        return count;
    }

    function getClick(uint256 index) public view returns (Click memory) {
        return queue[(head + index) % QUEUE_SIZE];
    }

    function getQueueFragment(uint256 start, uint256 end) public view returns (Click[] memory) {
        Click[] memory result = new Click[](end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = queue[(head + i) % QUEUE_SIZE];
        }
        return result;
    }

    function getQueue() public view returns (Click[] memory) {
        Click[] memory result = new Click[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = queue[(head + i) % QUEUE_SIZE];
        }
        return result;
    }

}