// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Base — Mock WBERA / WETH for Local Testing
/// @notice Minimal wrapped-native-token implementation used exclusively in Hardhat / local
///         fork environments. NOT deployed on-chain. Follows the standard WETH9 deposit/withdraw
///         pattern so that Wheel.distribute() can wrap and transfer BERA identically.
/// @dev On Berachain mainnet / testnet, replace this address with the canonical WBERA contract.
contract Base is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") {}

    /// @notice Wrap native ETH/BERA into the ERC-20 representation.
    /// @dev Mints 1:1 to msg.sender.
    function deposit() public payable {
        _mint(msg.sender, msg.value);
    }

    /// @notice Unwrap ERC-20 back to native ETH/BERA.
    /// @param amount Amount to withdraw (burns ERC-20, sends native).
    function withdraw(uint256 amount) public {
        require(balanceOf(msg.sender) >= amount, "MockWETH: Insufficient balance");
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }

    /// @dev Auto-wraps any native ETH/BERA sent directly to the contract.
    receive() external payable {
        deposit();
    }
}
