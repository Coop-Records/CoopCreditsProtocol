// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {Credits1155} from "../src/Credits1155.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ICoop} from "../src/interfaces/ICoop.sol";
import {MockCoopCoin} from "./mocks/MockCoopCoin.sol";

contract Credits1155Test is Test {
    Credits1155 public implementation;
    Credits1155 public credits;
    ProxyAdmin public proxyAdmin;
    address public owner;
    address public user;
    address public dummyMarket;

    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");
        dummyMarket = makeAddr("dummyMarket");
        vm.deal(user, 100 ether);

        // Add code to the dummy market to make it a contract
        vm.etch(dummyMarket, hex"00");

        vm.startPrank(owner);

        // Deploy implementation
        implementation = new Credits1155();

        // Deploy ProxyAdmin with owner
        proxyAdmin = new ProxyAdmin(owner);

        // Encode initialization data
        bytes memory initData =
            abi.encodeWithSelector(Credits1155.initialize.selector, "ipfs://test", payable(dummyMarket), address(0));

        // Deploy and initialize proxy
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), initData);

        // Setup proxy interface
        credits = Credits1155(payable(address(proxy)));

        vm.stopPrank();
    }

    function test_Constants() public view {
        assertEq(credits.CREDITS_TOKEN_ID(), 1);
        assertEq(credits.MINT_FEE_IN_WEI(), 0.0004 ether);
    }

    function test_BuyCredits() public {
        uint256 amount = 10;
        uint256 cost = credits.getEthCostForCredits(amount);

        vm.prank(user);
        credits.buyCredits{value: cost}(user, amount);

        assertEq(credits.balanceOf(user, credits.CREDITS_TOKEN_ID()), amount);
    }

    function test_RedeemCredits() public {
        // First buy some credits
        uint256 amount = 10;
        uint256 cost = credits.getEthCostForCredits(amount);

        vm.startPrank(user);
        credits.buyCredits{value: cost}(user, amount);

        uint256 balanceBefore = user.balance;
        credits.redeemCredits(amount);
        vm.stopPrank();

        assertEq(credits.balanceOf(user, credits.CREDITS_TOKEN_ID()), 0);
        assertEq(user.balance, balanceBefore + cost);
    }

    function test_AdminSetURI() public {
        string memory newUri = "ipfs://newtest";
        vm.prank(owner);
        credits.adminSetURI(newUri);
    }

    function test_RevertWhen_NonAdminSetsURI() public {
        vm.prank(user);
        vm.expectRevert();
        credits.adminSetURI("ipfs://test");
    }

    function test_SetDopplerUniversalRouter() public {
        // Test data setup
        address dopplerRouter = makeAddr("dopplerRouter");

        // Add code to the dopplerRouter to make it a contract
        vm.etch(dopplerRouter, hex"00");

        // Call the method as owner - should succeed
        vm.prank(owner);
        credits.setDopplerUniversalRouter(dopplerRouter);

        // Verify the router was set correctly
        assertEq(address(credits.dopplerUniversalRouter()), dopplerRouter);
    }

    function test_RevertWhen_SetDopplerUniversalRouterWithNonContractAddress() public {
        // Test data setup - use a regular address (not a contract)
        address nonContractAddress = makeAddr("nonContract");

        // Expect the specific error to be thrown
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Credits1155.Credits1155_Contract_Address_Is_Not_A_Contract.selector));
        credits.setDopplerUniversalRouter(nonContractAddress);
    }

    function test_RevertWhen_NonOwnerSetsDopplerUniversalRouter() public {
        // Test data setup
        address dopplerRouter = makeAddr("dopplerRouter");
        address nonOwner = makeAddr("nonOwner");

        // Expect the method to revert when called by non-owner
        // This will revert with AccessControl error since the user doesn't have DEFAULT_ADMIN_ROLE
        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")),
                nonOwner,
                bytes32(0x0000000000000000000000000000000000000000000000000000000000000000) // DEFAULT_ADMIN_ROLE
            )
        );
        credits.setDopplerUniversalRouter(dopplerRouter);
    }

    function test_BuyDopplerCoinsWithCredits() public {
        // First buy some credits for the user
        uint256 creditsAmount = 10;
        uint256 creditsCost = credits.getEthCostForCredits(creditsAmount);
        vm.prank(user);
        credits.buyCredits{value: creditsCost}(user, creditsAmount);

        // Verify initial credits balance
        uint256 initialCreditsBalance = credits.balanceOf(user, credits.CREDITS_TOKEN_ID());
        assertEq(initialCreditsBalance, creditsAmount);

        // Set up the Doppler Universal Router
        address dopplerRouter = makeAddr("dopplerRouter");
        vm.etch(dopplerRouter, hex"00");
        vm.prank(owner);
        credits.setDopplerUniversalRouter(dopplerRouter);

        // Test data setup
        bytes memory commands = hex"01"; // Example command
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = hex"02"; // Example input

        // Call buyDopplerCoinsWithCredits - should succeed and consume 1 credit
        vm.prank(user);
        credits.buyDopplerCoinsWithCredits(commands, inputs);

        // Verify credits balance decreased by 1
        uint256 finalCreditsBalance = credits.balanceOf(user, credits.CREDITS_TOKEN_ID());
        assertEq(finalCreditsBalance, initialCreditsBalance - 1);
    }

    function test_RevertWhen_BuyDopplerCoinsWithCreditsRouterNotSet() public {
        // First buy some credits for the user
        uint256 creditsAmount = 10;
        uint256 creditsCost = credits.getEthCostForCredits(creditsAmount);
        vm.prank(user);
        credits.buyCredits{value: creditsCost}(user, creditsAmount);

        // Verify initial credits balance
        uint256 initialCreditsBalance = credits.balanceOf(user, credits.CREDITS_TOKEN_ID());
        assertEq(initialCreditsBalance, creditsAmount);

        // Test data setup
        bytes memory commands = hex"01"; // Example command
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = hex"02"; // Example input

        // Expect the method to revert when router is not set
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Credits1155.Credits1155_Contract_Address_Is_Not_A_Contract.selector));
        credits.buyDopplerCoinsWithCredits(commands, inputs);

        // Verify credits balance remains unchanged after revert
        uint256 finalCreditsBalance = credits.balanceOf(user, credits.CREDITS_TOKEN_ID());
        assertEq(finalCreditsBalance, initialCreditsBalance);
    }

    function test_RevertWhen_BuyDopplerCoinsWithCreditsNoCredits() public {
        // Set up the Doppler Universal Router first
        address dopplerRouter = makeAddr("dopplerRouter");
        vm.etch(dopplerRouter, hex"00");
        vm.prank(owner);
        credits.setDopplerUniversalRouter(dopplerRouter);

        // Verify user has no credits initially
        uint256 initialCreditsBalance = credits.balanceOf(user, credits.CREDITS_TOKEN_ID());
        assertEq(initialCreditsBalance, 0);

        // Test data setup
        bytes memory commands = hex"01"; // Example command
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = hex"02"; // Example input

        // Expect the method to revert when user has no credits
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                Credits1155.Credits1155_Insufficient_Credits_Balance.selector,
                1, // required amount
                0 // available amount
            )
        );
        credits.buyDopplerCoinsWithCredits(commands, inputs);

        // Verify credits balance remains at 0
        uint256 finalCreditsBalance = credits.balanceOf(user, credits.CREDITS_TOKEN_ID());
        assertEq(finalCreditsBalance, 0);
    }

    // ===== COOP Coins Tests =====

    function test_BuyCoopCoinsWithCredits() public {
        // First buy some credits for the user
        uint256 creditsAmount = 10;
        uint256 creditsCost = credits.getEthCostForCredits(creditsAmount);
        vm.prank(user);
        credits.buyCredits{value: creditsCost}(user, creditsAmount);

        // Verify initial credits balance
        uint256 initialCreditsBalance = credits.balanceOf(user, credits.CREDITS_TOKEN_ID());
        assertEq(initialCreditsBalance, creditsAmount);

        // Deploy the mock COOP WOW Token contract
        MockCoopCoin mockCoopToken = new MockCoopCoin();
        address coinAddress = address(mockCoopToken);

        // Test data setup - simulate the buy function call from the frontend
        address recipient = makeAddr("recipient");
        address refundRecipient = makeAddr("refundRecipient");
        address orderReferrer = makeAddr("orderReferrer");
        string memory comment = "Test comment";
        ICoop.MarketType marketType = ICoop.MarketType.BONDING_CURVE; // curve market
        uint256 minOutput = 1000; // minimum tokens to receive
        uint160 sqrtPriceLimitX96 = 0;

        // Call buyCoopCoinsWithCredits - should succeed and consume 1 credit
        vm.prank(user);
        credits.buyCoopCoinsWithCredits(
            coinAddress, recipient, refundRecipient, orderReferrer, comment, marketType, minOutput, sqrtPriceLimitX96
        );

        // Verify credits balance decreased by 1
        uint256 finalCreditsBalance = credits.balanceOf(user, credits.CREDITS_TOKEN_ID());
        assertEq(finalCreditsBalance, initialCreditsBalance - 1);
    }

    function test_RevertWhen_BuyCoopCoinsWithCreditsNoCredits() public {
        // Verify user has no credits initially
        uint256 initialCreditsBalance = credits.balanceOf(user, credits.CREDITS_TOKEN_ID());
        assertEq(initialCreditsBalance, 0);

        // Deploy the mock COOP WOW Token contract
        MockCoopCoin mockCoopToken = new MockCoopCoin();
        address coinAddress = address(mockCoopToken);

        // Test data setup - simulate the buy function call from the frontend
        address recipient = makeAddr("recipient");
        address refundRecipient = makeAddr("refundRecipient");
        address orderReferrer = makeAddr("orderReferrer");
        string memory comment = "Test comment";
        ICoop.MarketType marketType = ICoop.MarketType.BONDING_CURVE; // curve market
        uint256 minOutput = 1000; // minimum tokens to receive
        uint160 sqrtPriceLimitX96 = 0;

        // Expect the method to revert when user has no credits
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                Credits1155.Credits1155_Insufficient_Credits_Balance.selector,
                1, // required amount
                0 // available amount
            )
        );
        credits.buyCoopCoinsWithCredits(
            coinAddress, recipient, refundRecipient, orderReferrer, comment, marketType, minOutput, sqrtPriceLimitX96
        );

        // Verify credits balance remains at 0
        uint256 finalCreditsBalance = credits.balanceOf(user, credits.CREDITS_TOKEN_ID());
        assertEq(finalCreditsBalance, 0);
    }

    function test_RevertWhen_BuyCoopCoinsWithCreditsNonContractAddress() public {
        // First buy some credits for the user
        uint256 creditsAmount = 10;
        uint256 creditsCost = credits.getEthCostForCredits(creditsAmount);
        vm.prank(user);
        credits.buyCredits{value: creditsCost}(user, creditsAmount);

        // Verify initial credits balance
        uint256 initialCreditsBalance = credits.balanceOf(user, credits.CREDITS_TOKEN_ID());
        assertEq(initialCreditsBalance, creditsAmount);

        // Use a regular address (not a contract) for coinAddress
        address nonContractAddress = makeAddr("nonContract");

        // Test data setup
        address recipient = makeAddr("recipient");
        address refundRecipient = makeAddr("refundRecipient");
        address orderReferrer = makeAddr("orderReferrer");
        string memory comment = "Test comment";
        ICoop.MarketType marketType = ICoop.MarketType.BONDING_CURVE;
        uint256 minOutput = 1000;
        uint160 sqrtPriceLimitX96 = 0;

        // Expect the method to revert due to onlyContracts modifier
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Credits1155.Credits1155_Contract_Address_Is_Not_A_Contract.selector));
        credits.buyCoopCoinsWithCredits(
            nonContractAddress,
            recipient,
            refundRecipient,
            orderReferrer,
            comment,
            marketType,
            minOutput,
            sqrtPriceLimitX96
        );

        // Verify credits balance remains unchanged after revert
        uint256 finalCreditsBalance = credits.balanceOf(user, credits.CREDITS_TOKEN_ID());
        assertEq(finalCreditsBalance, initialCreditsBalance);
    }
}
