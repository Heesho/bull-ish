// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MoolaClaim is Ownable {
    IERC20 public moola;
    
    mapping(address => uint256) public account_Claimable;
    
    event MoolaClaim__ClaimableSet(address indexed user, uint256 amount);
    event MoolaClaim__Claimed(address indexed user, uint256 amount);
    
    error MoolaClaim__NoClaimableAmount();
    error MoolaClaim__TransferFailed();
    error MoolaClaim__LengthMismatch();
    
    constructor(address _moola) {
        moola = IERC20(_moola);
    }
    
    function setClaims(
        address[] calldata users,
        uint256[] calldata amounts
    ) external onlyOwner {
        if (users.length != amounts.length) revert MoolaClaim__LengthMismatch();
        
        for (uint256 i = 0; i < users.length; i++) {
            account_Claimable[users[i]] = amounts[i];
            emit MoolaClaim__ClaimableSet(users[i], amounts[i]);
        }
    }
    
    function claim() external {
        uint256 amount = account_Claimable[msg.sender];
        if (amount == 0) revert MoolaClaim__NoClaimableAmount();
        
        account_Claimable[msg.sender] = 0;
        
        bool success = moola.transfer(msg.sender, amount);
        if (!success) revert MoolaClaim__TransferFailed();
        
        emit MoolaClaim__Claimed(msg.sender, amount);
    }

}