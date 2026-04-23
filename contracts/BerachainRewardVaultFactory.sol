// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// @title RewardVault — Mock Berachain Reward Vault for Local Testing
/// @notice Simplified stand-in for Berachain's native PoL reward vault. Tracks delegate-staked
///         balances per account but does NOT distribute BGT rewards — that logic lives in the
///         real Berachain implementation.
/// @dev On mainnet, the Wheel interacts with the canonical Berachain RewardVault which handles
///      BGT reward accrual proportional to delegated stake.
contract RewardVault {
    /// @notice The ERC-20 token accepted for staking (VaultToken deployed by Wheel).
    address public vaultToken;

    /// @notice Sum of all delegate-staked amounts.
    uint256 public totalSupply;

    /// @notice Delegate-staked balance per account.
    mapping(address => uint256) public balanceOf;

    /// @param _vaultToken Address of the VaultToken ERC-20 used as the staking receipt.
    constructor(address _vaultToken) {
        vaultToken = _vaultToken;
    }

    /// @notice Record a delegate stake for `account`.
    /// @dev In the real vault this would also transfer the staking token. The mock
    ///      skips the transfer since VaultToken is minted directly to the Wheel.
    /// @param account Address credited with the stake.
    /// @param amount  Power units to stake.
    function delegateStake(address account, uint256 amount) external {
        balanceOf[account] += amount;
        totalSupply += amount;
    }

    /// @notice Record a delegate withdrawal for `account`.
    /// @param account Address debited.
    /// @param amount  Power units to unstake.
    function delegateWithdraw(address account, uint256 amount) external {
        balanceOf[account] -= amount;
        totalSupply -= amount;
    }
}

/// @title BerachainRewardVaultFactory — Mock Factory for Local Testing
/// @notice Deploys RewardVault instances. Mirrors the Berachain-native factory interface
///         so the Wheel constructor works identically in local and mainnet environments.
contract BerachainRewardVaultFactory {
    constructor() {}

    /// @notice Deploy a new RewardVault bound to the given staking token.
    /// @param vaultToken The ERC-20 token that the vault will track.
    /// @return Address of the newly deployed RewardVault.
    function createRewardVault(address vaultToken) external returns (address) {
        return address(new RewardVault(vaultToken));
    }
}
