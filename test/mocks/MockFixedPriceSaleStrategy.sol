// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IMinter1155} from "../../src/interfaces/IMinter1155.sol";
import {ICreatorCommands} from "../../src/interfaces/ICreatorCommands.sol";
/**
 * @title MockFixedPriceSaleStrategy
 * @notice A mock implementation of the FixedPriceSaleStrategy for testing
 */

contract MockFixedPriceSaleStrategy is IMinter1155 {
    // Token price
    uint256 public pricePerToken;

    // Sale configuration
    struct SalesConfig {
        uint64 saleStart;
        uint64 saleEnd;
        uint64 maxTokensPerAddress;
        uint96 pricePerToken;
        address fundsRecipient;
        bool exists;
    }

    // Storage for sales configurations
    mapping(address => mapping(uint256 => SalesConfig)) public salesConfigs;

    // Sale validation error messages
    error SaleNotActive();
    error InvalidSalesConfig();
    error PriceNotMet(uint256 expected, uint256 sent);

    // Events for testing
    event SaleSet(address indexed mediaContract, uint256 indexed tokenId, SalesConfig salesConfig);
    event MintExecuted(address sender, uint256 tokenId, uint256 quantity, uint256 totalPrice);

    /**
     * @notice Constructor to set default price
     */
    constructor(uint256 _pricePerToken) {
        pricePerToken = _pricePerToken;
    }

    /**
     * @notice Set up a sale configuration for a token
     * @param target The target contract address
     * @param tokenId The token ID
     * @param config The sale configuration
     */
    function setSale(address target, uint256 tokenId, SalesConfig memory config) external {
        salesConfigs[target][tokenId] = config;
        salesConfigs[target][tokenId].exists = true;

        emit SaleSet(target, tokenId, config);
    }

    /**
     * @notice Set an inactive sale for testing
     */
    function setInactiveSale(address target, uint256 tokenId) external {
        SalesConfig memory config = SalesConfig({
            saleStart: uint64(block.timestamp + 1000),
            saleEnd: uint64(block.timestamp + 2000),
            maxTokensPerAddress: 0,
            pricePerToken: uint96(pricePerToken),
            fundsRecipient: address(this),
            exists: true
        });

        salesConfigs[target][tokenId] = config;
        emit SaleSet(target, tokenId, config);
    }

    /**
     * @notice Check if a sale is active
     */
    function isSaleActive(address target, uint256 tokenId) public view returns (bool) {
        SalesConfig memory config = salesConfigs[target][tokenId];

        return config.exists && block.timestamp >= config.saleStart
            && (config.saleEnd == 0 || block.timestamp <= config.saleEnd);
    }

    /**
     * @notice Implement the requestMint function for IMinter1155
     */
    function requestMint(
        address sender,
        uint256 tokenId,
        uint256 quantity,
        uint256 ethValueSent,
        bytes calldata minterArguments
    ) external override returns (CommandSet memory commands) {
        address mintTo;
        string memory comment = "";
        if (minterArguments.length == 32) {
            mintTo = abi.decode(minterArguments, (address));
        } else {
            (mintTo, comment) = abi.decode(minterArguments, (address, string));
        }

        // Calculate expected price
        SalesConfig storage config = salesConfigs[msg.sender][tokenId];

        uint256 expectedPrice = uint256(config.pricePerToken) * quantity;

        // Check if enough ETH was sent
        if (ethValueSent < expectedPrice) {
            revert PriceNotMet(expectedPrice, ethValueSent);
        }

        // Emit event for testing purposes
        emit MintExecuted(sender, tokenId, quantity, expectedPrice);

        // Create commands array directly instead of using setSize
        Command[] memory commandsArray = new Command[](1);

        // Create mint command
        commandsArray[0] = Command({method: CreatorActions.MINT, args: abi.encode(mintTo, tokenId, quantity)});

        // Set commands array in the CommandSet
        commands.commands = commandsArray;
    }
}
