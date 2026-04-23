// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

/// @title Bullas — Bull-ish Booster NFT
/// @notice Free-mint ERC-721 that grants a 10% UPC production bonus in the Factory.
///         Holding at least one Bullas NFT is checked by `Factory.getPower` to apply the boost.
/// @dev No supply cap, no mint restrictions — anyone can mint at any time. Uses a simple
///      auto-incrementing counter for token IDs (starts at 1).
contract Bullas is ERC721Enumerable {
    /// @notice Auto-incrementing token ID counter. Next mint will use `currentTokenId + 1`.
    uint256 public currentTokenId;

    constructor() ERC721("Bullas", "BULLAS") {}

    /// @notice Mint a single Bullas NFT to the caller.
    /// @return The newly minted token ID.
    function mint() external returns (uint256) {
        uint256 newTokenId = ++currentTokenId;
        _mint(msg.sender, newTokenId);
        return newTokenId;
    }
}
