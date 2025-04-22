// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {Credits1155} from "../src/Credits1155.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

// Import our mock implementations
import {MockCoopCreator1155} from "./mocks/MockCoopCreator1155.sol";
import {MockFixedPriceSaleStrategy} from "./mocks/MockFixedPriceSaleStrategy.sol";
import {ICoopCreator1155} from "../src/interfaces/ICoopCreator1155.sol";
import {IMinter1155} from "../src/interfaces/IMinter1155.sol";

contract Credits1155CoopIntegrationTest is Test {
    Credits1155 public implementation;
    Credits1155 public credits;
    ProxyAdmin public proxyAdmin;

    // Mock implementations
    MockCoopCreator1155 public coopCollectibles;
    MockFixedPriceSaleStrategy public saleStrategy;

    address public owner;
    address public user;

    uint256 public constant TOKEN_ID = 123;
    uint256 public constant SALE_TERMS_ID = 456;

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
        vm.deal(owner, 100 ether);

        // 3. Deploy the Credits1155 contract
        vm.startPrank(owner);

        implementation = new Credits1155();

        // Deploy ProxyAdmin with owner
        proxyAdmin = new ProxyAdmin(owner);

        // Encode initialization data - still using old interface
        // This will need to be updated for CoopCollectibles
        bytes memory initData = abi.encodeWithSelector(
            Credits1155.initialize.selector,
            "ipfs://test",
            payable(address(coopCollectibles)) // Using coopCollectibles address
        );

        // Deploy and initialize proxy
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), initData);

        // Setup proxy interface
        credits = Credits1155(payable(address(proxy)));

        // 1. First deploy our mock implementations
        coopCollectibles = new MockCoopCreator1155();
        saleStrategy = new MockFixedPriceSaleStrategy(credits.MINT_FEE_IN_WEI());

        // 2. Set up the token and sale in the mock implementations
        coopCollectibles.setupNewToken(TOKEN_ID, "ipfs://test/token", 1000); // Max supply 1000

        // Set up a valid sale for TOKEN_ID
        MockFixedPriceSaleStrategy.SalesConfig memory config = MockFixedPriceSaleStrategy.SalesConfig({
            saleStart: uint64(0), // Started 1000 seconds ago
            saleEnd: uint64(block.timestamp + 1000), // Ends 1000 seconds from now
            maxTokensPerAddress: 0, // No limit per address
            pricePerToken: uint96(credits.MINT_FEE_IN_WEI()), // Price per token
            fundsRecipient: payable(owner), // Funds go to owner
            exists: true // Sale exists
        });
        saleStrategy.setSale(address(coopCollectibles), TOKEN_ID, config);

        // Set up an inactive sale for testing
        saleStrategy.setInactiveSale(address(coopCollectibles), 789);

        // Set the fixed price sale strategy in the Credits1155 contract
        credits.setFixedPriceSaleStrategy(address(saleStrategy));

        vm.stopPrank();

        // Give the user some credits to work with
        uint256 creditsAmount = 100;
        uint256 cost = credits.getEthCostForCredits(creditsAmount);
        vm.prank(user);
        credits.buyCredits{value: cost}(user, creditsAmount);
    }

    function test_MintWithCredits_CoopIntegration() public {
        // This test expects the mintWithCredits function to interact with CoopCollectibles
        // instead of the old MultiTokenDropMarket

        uint256 tokenQuantity = 2;
        address tokenRecipient = user;
        address payable referrer = payable(address(0));

        // Get the initial balance of credits
        uint256 initialCreditsBalance = credits.balanceOf(user, credits.CREDITS_TOKEN_ID());

        // Calculate expected ETH cost
        uint256 expectedEthCost = credits.getEthCostForCredits(tokenQuantity);

        // Check initial token balance
        uint256 initialTokenBalance = coopCollectibles.balanceOf(tokenRecipient, TOKEN_ID);

        vm.prank(user);

        // Expect the event to be emitted with the right parameters
        vm.expectEmit(true, true, true, false);
        emit MintWithCreditsFromFixedPriceSale(
            TOKEN_ID, tokenRecipient, referrer, tokenQuantity, tokenQuantity, expectedEthCost
        );

        // Now we expect this to succeed instead of revert
        credits.mintWithCredits(address(coopCollectibles), TOKEN_ID, tokenQuantity, tokenRecipient, referrer);

        // Verify that credits were burned
        assertEq(
            credits.balanceOf(user, credits.CREDITS_TOKEN_ID()),
            initialCreditsBalance - tokenQuantity,
            "Credits were not burned correctly"
        );

        // Verify tokens were minted
        assertEq(
            coopCollectibles.balanceOf(tokenRecipient, TOKEN_ID),
            initialTokenBalance + tokenQuantity,
            "Tokens were not minted correctly"
        );
    }

    // function test_MintWithCredits_UsingSaleStrategy() public {
    //     // This test checks if the contract properly uses the sale strategy for pricing

    //     uint256 tokenQuantity = 1;

    //     // Get the initial balance of credits
    //     uint256 initialCreditsBalance = credits.balanceOf(
    //         user,
    //         credits.CREDITS_TOKEN_ID()
    //     );

    //     // Calculate the expected credits cost for a token with the mock sale strategy's price
    //     uint256 expectedCreditsCost = 10; // This will depend on implementation

    //     vm.prank(user);

    //     // Now we expect this to succeed and use the correct price from the sale strategy
    //     credits.mintWithCredits(
    //         TOKEN_ID,
    //         tokenQuantity,
    //         user,
    //         payable(address(0))
    //     );

    //     // Verify credits were burned with the correct amount based on sale strategy price
    //     assertEq(
    //         credits.balanceOf(user, credits.CREDITS_TOKEN_ID()),
    //         initialCreditsBalance - expectedCreditsCost,
    //         "Credits were not burned correctly based on sale strategy price"
    //     );
    // }

    // function test_MintWithCredits_RevertsForInactiveSale() public {
    //     // Using our inactive sale ID (789)
    //     uint256 inactiveSaleId = 789;

    //     vm.prank(user);

    //     // This should still revert with a message about the sale not being active
    //     vm.expectRevert(MockFixedPriceSaleStrategy.SaleNotActive.selector);
    //     credits.mintWithCredits(inactiveSaleId, 1, user, payable(address(0)));
    // }

    // function test_MintWithCredits_RevertsForInsufficientCredits() public {
    //     // Try to mint more tokens than the user has credits for
    //     uint256 tokenQuantity = 1000; // This should require more credits than the user has

    //     // Calculate the expected credits cost for this quantity (will be more than user has)
    //     uint256 expectedCreditsCost = 10000; // This will depend on implementation

    //     vm.prank(user);

    //     // This should revert with an insufficient credits message
    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             Credits1155.Credits1155_Insufficient_Credits_Balance.selector,
    //             expectedCreditsCost,
    //             credits.balanceOf(user, credits.CREDITS_TOKEN_ID())
    //         )
    //     );
    //     credits.mintWithCredits(
    //         TOKEN_ID,
    //         tokenQuantity,
    //         user,
    //         payable(address(0))
    //     );
    // }

    // function test_MintWithCredits_EmitsCorrectEvent() public {
    //     uint256 tokenQuantity = 1;
    //     address tokenRecipient = user;
    //     address payable referrer = payable(address(0));

    //     // Calculate expected costs
    //     uint256 expectedCreditsCost = 10; // This will depend on implementation
    //     uint256 expectedEthCost = credits.getEthCostForCredits(
    //         expectedCreditsCost
    //     );

    //     vm.prank(user);

    //     // We expect the contract to emit an event with these parameters
    //     vm.expectEmit(true, true, true, false);
    //     emit MintWithCreditsFromCoopCollectibles(
    //         TOKEN_ID,
    //         tokenRecipient,
    //         referrer,
    //         tokenQuantity,
    //         expectedCreditsCost,
    //         expectedEthCost
    //     );

    //     // This should succeed and emit the event
    //     credits.mintWithCredits(
    //         TOKEN_ID,
    //         tokenQuantity,
    //         tokenRecipient,
    //         referrer
    //     );
    // }
}
