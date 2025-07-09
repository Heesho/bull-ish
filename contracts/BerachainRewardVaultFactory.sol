// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract RewardVault {

    address public vaultToken;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    constructor(address _vaultToken) {
        vaultToken = _vaultToken;
    }

    function delegateStake(address account, uint256 amount) external {
        balanceOf[account] += amount;
        totalSupply += amount;
    }

    function delegateWithdraw(address account, uint256 amount) external {
        balanceOf[account] -= amount;
        totalSupply -= amount;
    }

}

contract BerachainRewardVaultFactory {
    
    constructor() {
    }

    function createRewardVault(address vaultToken) external returns (address) {
        return address(new RewardVault(vaultToken));
    }

}