// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Credits1155} from "../src/Credits1155.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

// Import our mock implementations
import {MockCoopCreator1155} from "./mocks/MockCoopCreator1155.sol";
import {MockFixedPriceSaleStrategy} from "./mocks/MockFixedPriceSaleStrategy.sol";

/**
 * @title Credits1155IsolationTest
 * @dev Tests focused on ensuring the mintWithCredits function handles different
 * collectibles contracts in isolation, without persisting state between calls
 */
contract Credits1155IsolationTest is Test {
    Credits1155 public implementation;
    Credits1155 public credits;
    ProxyAdmin public proxyAdmin;
    MockFixedPriceSaleStrategy public saleStrategy;

    // Multiple mock collectibles contracts for cross-contract testing
    MockCoopCreator1155 public collectibles1;
    MockCoopCreator1155 public collectibles2;

    address public owner;
    address public user;
    uint256 public constant TOKEN_ID = 123;

    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");
        vm.deal(user, 100 ether);

        vm.startPrank(owner);

        // Deploy implementation
        implementation = new Credits1155();

        // Deploy ProxyAdmin with owner
        proxyAdmin = new ProxyAdmin(owner);

        // Deploy mock implementations
        collectibles1 = new MockCoopCreator1155();
        collectibles2 = new MockCoopCreator1155();
        saleStrategy = new MockFixedPriceSaleStrategy(0.0004 ether);

        // Set up test tokens in both collectibles contracts
        collectibles1.setupNewToken(TOKEN_ID, "ipfs://test/token1", 1000);
        collectibles2.setupNewToken(TOKEN_ID, "ipfs://test/token2", 1000);

        // Set up sales in the strategy for both collectibles
        MockFixedPriceSaleStrategy.SalesConfig memory config = MockFixedPriceSaleStrategy.SalesConfig({
            saleStart: uint64(0),
            saleEnd: uint64(block.timestamp + 1000),
            maxTokensPerAddress: 0,
            pricePerToken: uint96(0.0004 ether),
            fundsRecipient: payable(owner),
            exists: true
        });

        saleStrategy.setSale(address(collectibles1), TOKEN_ID, config);
        saleStrategy.setSale(address(collectibles2), TOKEN_ID, config);

        // Initialize and deploy the proxy with our implementation
        bytes memory initData =
            abi.encodeWithSelector(Credits1155.initialize.selector, "ipfs://test", address(saleStrategy), address(0));

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), initData);

        // Setup proxy interface
        credits = Credits1155(payable(address(proxy)));

        vm.stopPrank();

        // Buy credits for the user
        uint256 creditsAmount = 100; // Enough for multiple mints
        uint256 cost = credits.getEthCostForCredits(creditsAmount);
        vm.prank(user);
        credits.buyCredits{value: cost}(user, creditsAmount);
    }

    /**
     * @notice Tests the isolation property of mintWithCredits with multiple collectibles contracts
     * @dev Verifies that:
     *      1. Minting works correctly with an initial collectibles contract
     *      2. Minting with a different collectibles contract also succeeds
     *      3. Returning to the first contract works without issues
     *      This confirms mintWithCredits doesn't maintain harmful state between calls
     */
    function test_MintWithCredits_MaintainsIsolationBetweenCalls() public {
        uint256 tokenQuantity = 1;

        // First mint with collectibles1
        vm.prank(user);
        credits.mintWithCredits(address(collectibles1), TOKEN_ID, tokenQuantity, user, payable(address(0)));

        // Verify mint worked with collectibles1
        uint256 balance1 = collectibles1.balanceOf(user, TOKEN_ID);
        assertEq(balance1, tokenQuantity, "First mint with collectibles1 failed");
        console.log("First mint with collectibles1 successful");

        // Mint with collectibles2
        vm.prank(user);
        credits.mintWithCredits(address(collectibles2), TOKEN_ID, tokenQuantity, user, payable(address(0)));

        // Verify mint worked with collectibles2
        uint256 balance2 = collectibles2.balanceOf(user, TOKEN_ID);
        assertEq(balance2, tokenQuantity, "Second mint with collectibles2 failed");
        console.log("Second mint with collectibles2 successful");

        // Verify we can mint again with collectibles1 without issues
        vm.prank(user);
        credits.mintWithCredits(address(collectibles1), TOKEN_ID, tokenQuantity, user, payable(address(0)));

        // Verify the additional tokens were minted from collectibles1
        uint256 newBalance1 = collectibles1.balanceOf(user, TOKEN_ID);
        assertEq(newBalance1, balance1 + tokenQuantity, "Third mint with collectibles1 failed");
        console.log("Third mint with collectibles1 successful");

        // Test passes if all mints work correctly, confirming proper isolation
        console.log("All sequential mints completed successfully without state interference");
    }
}
