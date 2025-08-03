// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Base is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") {}

    // Deposit ETH and mint WETH
    function deposit() public payable {
        _mint(msg.sender, msg.value);
    }

    // Withdraw ETH and burn WETH
    function withdraw(uint256 amount) public {
        require(balanceOf(msg.sender) >= amount, "MockWETH: Insufficient balance");
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }

    // Receive function to accept ETH
    receive() external payable {
        deposit();
    }
}
