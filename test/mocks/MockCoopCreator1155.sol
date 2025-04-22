// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ICoopCreator1155} from "../../src/interfaces/ICoopCreator1155.sol";
import {IMinter1155} from "../../src/interfaces/IMinter1155.sol";

/**
 * @title MockCoopCreator1155
 * @notice A mock implementation of the CoopCreator1155 contract for testing
 */
contract MockCoopCreator1155 is ICoopCreator1155 {
    // Token data storage
    mapping(uint256 => TokenData) public tokens;

    // Token balances
    mapping(address => mapping(uint256 => uint256)) public balances;

    // Constant mint fee
    uint256 public constant MINT_FEE = 0.0004 ether;

    // Mock events for testing
    event MintExecuted(address recipient, uint256 tokenId, uint256 quantity);
    event ETHTransferred(address recipient, uint256 amount);

    // Error messages
    error InvalidTokenId();
    error CannotMintMoreTokens(uint256 tokenId, uint256 quantity, uint256 totalMinted, uint256 maxSupply);

    /**
     * @notice Set up a token with initial data
     */
    function setupNewToken(uint256 tokenId, string memory uri, uint256 maxSupply) external {
        tokens[tokenId] = TokenData({uri: uri, maxSupply: maxSupply, totalMinted: 0});
    }

    /**
     * @notice Implements the mint function from ICoopCreator1155
     */
    function mint(
        IMinter1155 minter,
        uint256 tokenId,
        uint256 quantity,
        address[] calldata,
        bytes calldata minterArguments
    ) external payable override {
        // Validate token exists
        if (bytes(tokens[tokenId].uri).length == 0) {
            revert InvalidTokenId();
        }

        // Check supply limit
        if (tokens[tokenId].maxSupply > 0 && tokens[tokenId].totalMinted + quantity > tokens[tokenId].maxSupply) {
            revert CannotMintMoreTokens(tokenId, quantity, tokens[tokenId].totalMinted, tokens[tokenId].maxSupply);
        }

        // Request minting commands from the minter contract
        IMinter1155.CommandSet memory commands =
            minter.requestMint(msg.sender, tokenId, quantity, msg.value, minterArguments);

        // Execute commands
        for (uint256 i = 0; i < commands.commands.length; i++) {
            IMinter1155.Command memory cmd = commands.commands[i];

            if (cmd.method == IMinter1155.CreatorActions.MINT) {
                (address recipient, uint256 mintTokenId, uint256 mintQuantity) =
                    abi.decode(cmd.args, (address, uint256, uint256));

                // Update balances
                balances[recipient][mintTokenId] += mintQuantity;
                tokens[mintTokenId].totalMinted += mintQuantity;

                emit MintExecuted(recipient, mintTokenId, mintQuantity);
            } else if (cmd.method == IMinter1155.CreatorActions.SEND_ETH) {
                (address recipient, uint256 amount) = abi.decode(cmd.args, (address, uint256));

                // Transfer ETH
                (bool success,) = recipient.call{value: amount}("");
                require(success, "ETH transfer failed");

                emit ETHTransferred(recipient, amount);
            }
        }
    }

    /**
     * @notice Returns the mint fee
     */
    function mintFee() external pure override returns (uint256) {
        return MINT_FEE;
    }

    /**
     * @notice Returns token information
     */
    function getTokenInfo(uint256 tokenId) external view override returns (TokenData memory) {
        return tokens[tokenId];
    }

    /**
     * @notice Returns balance of a token for an address
     */
    function balanceOf(address account, uint256 tokenId) external view returns (uint256) {
        return balances[account][tokenId];
    }

    /**
     * @notice Function to receive ETH
     */
    receive() external payable {}
}
