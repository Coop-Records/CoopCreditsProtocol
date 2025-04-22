// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.17;

import {IMinter1155} from "./IMinter1155.sol";

/**
 * @title ICoopCreator1155
 * @notice Simplified interface for the CoopCreator1155 contract to use for integration
 */
interface ICoopCreator1155 {
    /**
     * @notice Mint tokens using a configured minter for the contract
     * @param minter The minter contract to use for minting
     * @param tokenId The token ID to mint
     * @param quantity The quantity of tokens to mint
     * @param rewardsRecipients Array of reward recipients (index 0 is typically mint referral)
     * @param minterArguments Additional arguments needed by the minter contract
     */
    function mint(
        IMinter1155 minter,
        uint256 tokenId,
        uint256 quantity,
        address[] calldata rewardsRecipients,
        bytes calldata minterArguments
    ) external payable;

    /**
     * @notice Get the mint fee required per token
     * @return The mint fee amount in wei
     */
    function mintFee() external view returns (uint256);

    /**
     * @notice Returns info about a specific token
     * @param tokenId The token ID to query
     */
    function getTokenInfo(uint256 tokenId) external view returns (TokenData memory);

    /**
     * @notice The data structure containing token information
     */
    struct TokenData {
        string uri;
        uint256 maxSupply;
        uint256 totalMinted;
    }
}
