// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {Credits1155} from "../src/Credits1155.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

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
            abi.encodeWithSelector(Credits1155.initialize.selector, "ipfs://test", payable(dummyMarket));

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
        // Test data setup
        bytes memory commands = hex"01"; // Example command
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = hex"02"; // Example input

        // This test should fail since the method doesn't exist yet
        // Following TDD red-green-refactor cycle
        vm.prank(user);
        vm.expectRevert();
        credits.buyDopplerCoinsWithCredits(commands, inputs);
    }

    function test_RevertWhen_BuyDopplerCoinsWithCreditsRouterNotSet() public {
        // Test data setup
        bytes memory commands = hex"01"; // Example command
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = hex"02"; // Example input

        // Expect the method to revert when router is not set
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Credits1155.Credits1155_Contract_Address_Is_Not_A_Contract.selector));
        credits.buyDopplerCoinsWithCredits(commands, inputs);
    }
}
