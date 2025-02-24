// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Moola is ERC20, Ownable {

    bool public transferrable = false;
    mapping(address => bool) public minters;
    mapping(address => bool) public transferWhitelist;

    error Moola__NotAuthorized();
    error Moola__NonTransferable();

    event Moola__MinterSet(address minter, bool flag);
    event Moola__TransferrableSet(bool transferrable);
    event Moola__Minted(address account, uint256 amount);
    event Moola__Burned(address account, uint256 amount);
    event Moola__TransferWhitelisted(address account, bool flag);

    modifier onlyMinter() {
        if (!minters[msg.sender]) revert Moola__NotAuthorized();
        _;
    }

    constructor() ERC20("Moola", "MOOLA") {}

    function mint(address account, uint256 amount) external onlyMinter {
        _mint(account, amount);
        emit Moola__Minted(account, amount);
    }

    function burn(address account, uint256 amount) external onlyMinter {
        _burn(account, amount);
        emit Moola__Burned(account, amount);
    }

    function setMinter(address minter, bool flag) external onlyOwner {
        minters[minter] = flag;
        emit Moola__MinterSet(minter, flag);
    }

    function setTransferrable(bool _transferrable) external onlyOwner {
        transferrable = _transferrable;
        emit Moola__TransferrableSet(_transferrable);
    }

    function setTransferWhitelisted(address account, bool flag) external onlyOwner {
        transferWhitelist[account] = flag;
        emit Moola__TransferWhitelisted(account, flag);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20)
    {
        super._beforeTokenTransfer(from, to, amount);
        if (from != address(0) && to != address(0)) {
            if (!transferrable && !transferWhitelist[from]) {
                revert Moola__NonTransferable();
            }
        }
    }
}