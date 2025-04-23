// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Credits1155} from "../src/Credits1155.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

// Import our mock implementations
import {MockFixedPriceSaleStrategy} from "./mocks/MockFixedPriceSaleStrategy.sol";
import {MockCoopCreator1155} from "./mocks/MockCoopCreator1155.sol";

contract Credits1155InitializerTest is Test {
    Credits1155 public implementation;
    Credits1155 public credits;
    ProxyAdmin public proxyAdmin;
    MockFixedPriceSaleStrategy public saleStrategy;
    MockCoopCreator1155 public coopCollectibles;

    address public owner;
    address public user;
    uint256 public constant TOKEN_ID = 123;

    // Event definition for testing
    event MintWithCreditsFromFixedPriceSale(
        uint256 indexed tokenId,
        address indexed tokenRecipient,
        address indexed referrer,
        uint256 tokenQuantity,
        uint256 creditsCost,
        uint256 ethCost
    );

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
        coopCollectibles = new MockCoopCreator1155();
        saleStrategy = new MockFixedPriceSaleStrategy(0.0004 ether);

        // Set up test token
        coopCollectibles.setupNewToken(TOKEN_ID, "ipfs://test/token", 1000);

        // Set up a valid sale for TOKEN_ID
        MockFixedPriceSaleStrategy.SalesConfig memory config = MockFixedPriceSaleStrategy.SalesConfig({
            saleStart: uint64(0),
            saleEnd: uint64(block.timestamp + 1000),
            maxTokensPerAddress: 0,
            pricePerToken: uint96(0.0004 ether),
            fundsRecipient: payable(owner),
            exists: true
        });
        saleStrategy.setSale(address(coopCollectibles), TOKEN_ID, config);

        vm.stopPrank();
    }

    function test_Initialize_WithFixedPriceSaleStrategy() public {
        vm.startPrank(owner);

        // Encode initialization data with the strategy
        bytes memory initData =
            abi.encodeWithSelector(Credits1155.initialize.selector, "ipfs://test", address(saleStrategy));

        // Deploy and initialize proxy
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), initData);

        // Setup proxy interface
        credits = Credits1155(payable(address(proxy)));

        vm.stopPrank();

        // Verify the strategy was set during initialization
        assertEq(
            address(credits.fixedPriceSaleStrategy()),
            address(saleStrategy),
            "FixedPriceSaleStrategy not set during initialization"
        );
    }

    function test_Initialize_WithZeroAddressStrategy() public {
        vm.startPrank(owner);

        // Encode initialization data with zero address strategy
        bytes memory initData = abi.encodeWithSelector(
            Credits1155.initialize.selector,
            "ipfs://test",
            address(0) // Zero address for strategy
        );

        // Deploy and initialize proxy
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), initData);

        // Setup proxy interface
        credits = Credits1155(payable(address(proxy)));

        vm.stopPrank();

        // Verify the strategy was not set (should be zero address)
        assertEq(address(credits.fixedPriceSaleStrategy()), address(0), "FixedPriceSaleStrategy should be zero address");
    }

    function test_Initialize_WithInvalidContractAddress() public {
        vm.startPrank(owner);

        // Use an EOA (not a contract) for the strategy
        address nonContractAddress = makeAddr("nonContract");

        // Encode initialization data with invalid address
        bytes memory initData =
            abi.encodeWithSelector(Credits1155.initialize.selector, "ipfs://test", nonContractAddress);

        // This should revert when trying to initialize with a non-contract address
        vm.expectRevert(Credits1155.Credits1155_Contract_Address_Is_Not_A_Contract.selector);

        // Deploy and initialize proxy
        new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), initData);

        vm.stopPrank();
    }

    function test_MintWithCredits_WorksImmediatelyAfterInitialization() public {
        // Deploy with strategy set during initialization
        vm.startPrank(owner);

        // Encode initialization data with the strategy
        bytes memory initData =
            abi.encodeWithSelector(Credits1155.initialize.selector, "ipfs://test", address(saleStrategy));

        // Deploy and initialize proxy
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), initData);

        // Setup proxy interface
        credits = Credits1155(payable(address(proxy)));

        vm.stopPrank();

        // Buy some credits for the user
        uint256 creditsAmount = 10;
        uint256 cost = credits.getEthCostForCredits(creditsAmount);
        vm.prank(user);
        credits.buyCredits{value: cost}(user, creditsAmount);

        // Verify the user actually has credits before proceeding
        uint256 actualBalance = credits.balanceOf(user, credits.CREDITS_TOKEN_ID());
        console.log("User credit balance:", actualBalance);
        assertEq(actualBalance, creditsAmount, "Credits were not minted correctly");

        // Mint tokens with credits immediately after initialization
        // We should be able to mint without calling setFixedPriceSaleStrategy
        uint256 tokenQuantity = 2;

        vm.prank(user);

        // Expect the event to be emitted
        vm.expectEmit(true, true, true, false);
        emit MintWithCreditsFromFixedPriceSale(
            TOKEN_ID, user, address(0), tokenQuantity, tokenQuantity, credits.getEthCostForCredits(tokenQuantity)
        );
        vm.prank(user);

        // This should succeed without needing to call setFixedPriceSaleStrategy
        credits.mintWithCredits(address(coopCollectibles), TOKEN_ID, tokenQuantity, user, payable(address(0)));

        // Verify tokens were minted
        assertEq(coopCollectibles.balanceOf(user, TOKEN_ID), tokenQuantity, "Tokens were not minted correctly");

        // Verify credits were deducted
        uint256 finalCreditBalance = credits.balanceOf(user, credits.CREDITS_TOKEN_ID());
        console.log("User final credit balance:", finalCreditBalance);
        assertEq(finalCreditBalance, creditsAmount - tokenQuantity, "Credits were not deducted correctly");
    }
}
