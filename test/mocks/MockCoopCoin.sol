// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Mock COOP WOW Token contract for testing
contract MockCoopCoin {
    function buy(address, address, address, string memory, uint8, uint256 minOrderSize, uint160)
        external
        payable
        returns (uint256)
    {
        // Mock implementation - just return a token amount
        return minOrderSize;
    }
}
