// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Moola — Bull-ish In-Game Currency
/// @notice ERC-20 token used as the sole unit of account in the Bull-ish idle-clicker game.
/// @dev Non-transferable by default. Only whitelisted minters (Factory, Wheel) can mint/burn.
///      Transfers between players are blocked until the owner explicitly enables them or
///      whitelists specific sender addresses.
contract Moola is ERC20, Ownable {
    /// @notice When false, peer-to-peer transfers revert (mints and burns still succeed).
    bool public transferable = false;

    /// @notice Addresses authorized to call `mint` and `burn` (expected: Factory and Wheel contracts).
    mapping(address => bool) public minters;

    /// @notice Addresses exempt from the transfer lock regardless of the global `transferable` flag.
    mapping(address => bool) public transferWhitelist;

    error Moola__NotAuthorized();
    error Moola__NonTransferable();

    event Moola__MinterSet(address minter, bool flag);
    event Moola__TransferableSet(bool transferable);
    event Moola__Minted(address account, uint256 amount);
    event Moola__Burned(address account, uint256 amount);
    event Moola__TransferWhitelisted(address account, bool flag);

    modifier onlyMinter() {
        if (!minters[msg.sender]) revert Moola__NotAuthorized();
        _;
    }

    constructor() ERC20("Moola", "MOOLA") {}

    /// @notice Mint MOOLA to `account`. Only callable by whitelisted minters.
    /// @param account Recipient of the newly minted tokens.
    /// @param amount  Amount to mint (18 decimals).
    function mint(address account, uint256 amount) external onlyMinter {
        _mint(account, amount);
        emit Moola__Minted(account, amount);
    }

    /// @notice Burn MOOLA from `account`. Only callable by whitelisted minters.
    /// @param account Address whose tokens are burned (e.g. when purchasing tools).
    /// @param amount  Amount to burn (18 decimals).
    function burn(address account, uint256 amount) external onlyMinter {
        _burn(account, amount);
        emit Moola__Burned(account, amount);
    }

    /// @notice Grant or revoke minting/burning rights for an address.
    /// @dev Typically called once during deployment to authorize Factory and Wheel.
    /// @param minter Address to authorize or deauthorize.
    /// @param flag   `true` to grant, `false` to revoke.
    function setMinter(address minter, bool flag) external onlyOwner {
        minters[minter] = flag;
        emit Moola__MinterSet(minter, flag);
    }

    /// @notice Toggle the global transfer lock for all holders.
    /// @dev When enabled, any holder can freely transfer MOOLA. Use with caution —
    ///      enabling transfers makes the in-game currency tradeable.
    /// @param _transferable `true` to allow free transfers, `false` to re-lock.
    function setTransferable(bool _transferable) external onlyOwner {
        transferable = _transferable;
        emit Moola__TransferableSet(_transferable);
    }

    /// @notice Exempt or un-exempt a specific address from the transfer lock.
    /// @dev Useful for allowing DEX routers or vesting contracts to move tokens
    ///      while keeping the global lock in place.
    /// @param account Address to whitelist or remove.
    /// @param flag    `true` to whitelist, `false` to remove.
    function setTransferWhitelist(address account, bool flag) external onlyOwner {
        transferWhitelist[account] = flag;
        emit Moola__TransferWhitelisted(account, flag);
    }

    /// @dev Enforces transfer restrictions. Mints (from == 0) and burns (to == 0) always pass.
    ///      Peer-to-peer transfers are blocked unless the global `transferable` flag is set
    ///      or the sender is individually whitelisted.
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override(ERC20) {
        super._beforeTokenTransfer(from, to, amount);
        if (from != address(0) && to != address(0)) {
            if (!transferable && !transferWhitelist[from]) {
                revert Moola__NonTransferable();
            }
        }
    }
}
