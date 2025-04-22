// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.17;

/**
 * @title IMinter1155
 * @notice Interface for minter contracts that can be used with CoopCreator1155
 */
interface IMinter1155 {
    /**
     * @notice Struct for defining a command to execute as part of minting
     */
    struct Command {
        CreatorActions method;
        bytes args;
    }

    /**
     * @notice Struct for the set of commands to execute for minting
     */
    struct CommandSet {
        Command[] commands;
    }

    /**
     * @notice Enum of possible actions that can be executed during minting
     */
    enum CreatorActions {
        MINT,
        SEND_ETH,
        NO_OP
    }

    /**
     * @notice Request minting of tokens, returning the command set to execute
     * @param sender The address requesting the mint
     * @param tokenId The token ID to mint
     * @param quantity The quantity to mint
     * @param ethValueSent The amount of ETH sent with the mint request
     * @param minterArguments Additional arguments for minting
     * @return commands The commands to execute to complete the mint
     */
    function requestMint(
        address sender,
        uint256 tokenId,
        uint256 quantity,
        uint256 ethValueSent,
        bytes calldata minterArguments
    ) external returns (CommandSet memory commands);
}
