// SPDX-License-Identifier: MIT OR Apache-2.0

pragma solidity ^0.8.18;

// solhint-disable max-line-length
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC1155BurnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ERC1155SupplyUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
// solhint-enable max-line-length

import {IMultiTokenDropMarket} from "./interfaces/IMultiTokenDropMarket.sol";

contract Spurs1155 is
    Initializable,
    Ownable2StepUpgradeable,
    AccessControlUpgradeable,
    ERC1155Upgradeable,
    ERC1155SupplyUpgradeable,
    ERC1155BurnableUpgradeable
{
    using Address for address payable;

    /**
     * @notice Hardcoded token id.
     * @dev Spurs1155 only uses the first id.
     */
    uint256 public constant SPURS_TOKEN_ID = 1;

    /// @dev A new discounted fixed fee charged for each MultiToken minted.
    uint256 public constant MULTI_TOKEN_MINT_FEE_IN_WEI = 0.0001 ether;

    /**
     * @notice Drop market where Spurs can be spent to mint tokens.
     */
    IMultiTokenDropMarket public multiTokenDropMarket;

    /**
     * @notice Not a contract
     * @dev The drop market address provided is not a contract.
     */
    error Spurs1155_MultiTokenDropMarket_Address_Is_Not_A_Contract();

    /**
     * @notice Invalid sales term ID
     * @dev The provided sales term ID does not correspond to an active sale.
     */
    error Spurs1155_MultiTokenDropMarket_Invalid_Sales_Term_Id(uint256 saleTermsId);

    /**
     * @notice Must buy 1
     * @dev The buyer must mint at least one token with Spurs
     */
    error Spurs1155_Must_Buy_At_Least_One_Token();

    /**
     * @notice Not enough ETH sent
     * @dev ETH must be sent to buy Spurs.
     */
    error Spurs1155_Not_Enough_ETH_Sent(uint256 required, uint256 sent);

    /**
     * @notice Insufficient Spurs balance
     * @dev The account does not have enough Spurs for this action.
     */
    error Spurs1155_Insufficient_Spurs_Balance(uint256 required, uint256 available);

    /**
     * @notice Insufficient ETH in contract
     * @dev The contract does not have enough ETH to complete this action.
     */
    error Spurs1155_Insufficient_ETH_In_Contract(uint256 required, uint256 available);

    /**
     * @notice Cannot withdraw to 0x0
     * @dev Cannot withdraw to 0x0
     */
    error Spurs1155_Invalid_Withdraw_Address();

    /**
     * @notice Emitted when an admin withdraws ETH from the contract
     * @param admin The address of the admin executing the withdraw
     * @param recipient The address of the recipient of the ETH
     * @param amount The amount of ETH being withdrawn
     */
    event AdminWithdrawal(address indexed admin, address indexed recipient, uint256 amount);

    /**
     * @notice Emitted when a buyer successfully mints tokens from a fixed price sale using Spurs.
     * @param saleTermsId The ID of the sale terms for the listing this minted from.
     * @param tokenRecipient The address which received the minted tokens.
     * @param referrer The address of the referrer for this purchase, if any.
     * @param tokenQuantity The number of tokens minted.
     * @param spursCost The amount of Spurs burned to mint the tokens
     * @param ethCost The amount of ETH spent to mint the tokens
     */
    event MintWithSpursFromFixedPriceSale(
        uint256 indexed saleTermsId,
        address indexed tokenRecipient,
        address indexed referrer,
        uint256 tokenQuantity,
        uint256 spursCost,
        uint256 ethCost
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(string memory tokenUri, address payable _multiTokenDropMarket) public initializer {
        if (_multiTokenDropMarket.code.length == 0) {
            revert Spurs1155_MultiTokenDropMarket_Address_Is_Not_A_Contract();
        }
        multiTokenDropMarket = IMultiTokenDropMarket(_multiTokenDropMarket);

        __ERC1155_init(tokenUri); // creates first token
        __Ownable_init(msg.sender);
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Buy Spurs with ETH
     * @dev Checks for sufficient ETH before executing.
     * @param account The account address to buy Spurs for.
     * @param amount The amount of Spurs to buy.
     */
    function buySpurs(address account, uint256 amount) public payable {
        uint256 ethCost = getEthCostForSpurs(amount);

        if (msg.value < ethCost) {
            revert Spurs1155_Not_Enough_ETH_Sent(ethCost, msg.value);
        }

        // Mint spurs to sender
        _mint(account, SPURS_TOKEN_ID, amount, "");

        // Refund any excess Ether
        uint256 remainder = msg.value - ethCost;
        if (remainder > 0) {
            payable(msg.sender).sendValue(remainder);
        }
    }

    /**
     * @notice Burn Spurs to get the underlying ETH.
     * @dev Checks for sufficient Spurs balance and ETH in contract before executing. Only redeems to msg.sender.
     * @param amount The amount of Spurs to redeem
     */
    function redeemSpurs(uint256 amount) public {
        uint256 bal = balanceOf(msg.sender, SPURS_TOKEN_ID);
        if (bal < amount) {
            revert Spurs1155_Insufficient_Spurs_Balance(amount, bal);
        }

        uint256 ethCost = getEthCostForSpurs(amount);
        uint256 ethBal = address(this).balance;
        if (ethBal < ethCost) {
            revert Spurs1155_Insufficient_ETH_In_Contract(ethCost, ethBal);
        }
        _burn(msg.sender, SPURS_TOKEN_ID, amount);
        payable(msg.sender).sendValue(ethCost);
    }

    /**
     * @notice Mints token(s) from MultiTokenDropMarket with Spurs balance on this contract.
     * @param saleTermsId id of SaleTerms for the token to be minted.
     * @param tokenQuantity The number of tokens to be minted.
     * @param tokenRecipient The address where tokens should be minted to.
     * @param referrer The address of the referrer for this mint.
     */
    function mintWithSpurs(uint256 saleTermsId, uint256 tokenQuantity, address tokenRecipient, address payable referrer)
        external
    {
        if (tokenQuantity < 1) {
            revert Spurs1155_Must_Buy_At_Least_One_Token();
        }
        IMultiTokenDropMarket.GetFixedPriceSaleResults memory fixedPriceSale =
            multiTokenDropMarket.getFixedPriceSale(saleTermsId, referrer);

        // Check if sales terms exist
        if (fixedPriceSale.multiTokenContract == address(0)) {
            revert Spurs1155_MultiTokenDropMarket_Invalid_Sales_Term_Id(saleTermsId);
        }

        // Burn balance and mint with unlocked ETH
        uint256 spursCost = getSpursCostForMint(fixedPriceSale.pricePerQuantity, tokenQuantity);
        uint256 userSpursBalance = balanceOf(msg.sender, SPURS_TOKEN_ID);

        if (spursCost > userSpursBalance) {
            revert Spurs1155_Insufficient_Spurs_Balance(spursCost, userSpursBalance);
        }
        _burn(msg.sender, SPURS_TOKEN_ID, spursCost);

        uint256 ethCost = getEthCostForSpurs(spursCost);
        multiTokenDropMarket.mintFromFixedPriceSale{value: ethCost}(
            saleTermsId, tokenQuantity, tokenRecipient, referrer
        );

        // Emit information multiTokenDropMarket wouldn't have
        emit MintWithSpursFromFixedPriceSale(saleTermsId, tokenRecipient, referrer, tokenQuantity, spursCost, ethCost);
    }

    /**
     * @notice Allows admins to set the URI of the contract
     * @param newuri The new URI to set for the contract
     */
    function adminSetURI(string memory newuri) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(newuri);
    }

    /**
     * @notice Allows admins to update the MultiTokenDropMarket contract address
     * @param newMarket The address of the new MultiTokenDropMarket contract
     */
    function adminSetMultiTokenDropMarket(address newMarket) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newMarket.code.length == 0) {
            revert Spurs1155_MultiTokenDropMarket_Address_Is_Not_A_Contract();
        }
        multiTokenDropMarket = IMultiTokenDropMarket(newMarket);
    }

    /**
     * @notice Allow admins to withdraw extra ETH in the contract.
     * @dev Note that this does not check balances,and may result in less ETH than is required for full redemption.
     * @param recipient The address receiving the ETH.
     * @param amount Amount of ETH to send to recipient.
     *
     */
    function adminWithdraw(address payable recipient, uint256 amount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (recipient == address(0)) {
            revert Spurs1155_Invalid_Withdraw_Address();
        }
        uint256 contractBalance = address(this).balance;
        if (amount > contractBalance) {
            revert Spurs1155_Insufficient_ETH_In_Contract(amount, contractBalance);
        }

        recipient.sendValue(amount);
        emit AdminWithdrawal(msg.sender, recipient, amount);
    }

    /**
     * @notice ETH cost of minting from MultiTokenCollection
     * @dev This is mostly copied over from MultiTokenDropMarketFixedPriceSale,
     * but returns one variable to avoid stack too deep issues.
     * @param pricePerQuantity The address receiving the ETH.
     * @param tokenQuantity Amount of ETH to send to recipient.
     * @return spursCost The Spurs cost for minting
     */
    function getSpursCostForMint(uint256 pricePerQuantity, uint256 tokenQuantity)
        public
        pure
        returns (uint256 spursCost)
    {
        uint256 protocolFee = getEthCostForSpurs(tokenQuantity);
        uint256 creatorRevenue = 0;

        if (pricePerQuantity == 0) {
            creatorRevenue = protocolFee / 2;
            protocolFee -= creatorRevenue;
        } else {
            creatorRevenue = pricePerQuantity * tokenQuantity;
        }
        spursCost = (creatorRevenue + protocolFee) / MULTI_TOKEN_MINT_FEE_IN_WEI;
    }

    /**
     * @notice Calculate the total ETH cost for a given quantity of Spurs
     * @dev Multiplies the constant fee by the requested quantity
     * @param quantity The number of Spurs to calculate cost for
     * @return ethCost The total ETH cost for the requested quantity of Spurs
     */
    function getEthCostForSpurs(uint256 quantity) public pure returns (uint256 ethCost) {
        ethCost = MULTI_TOKEN_MINT_FEE_IN_WEI * quantity;
    }

    /// @inheritdoc ERC1155Upgradeable
    function _update(address from, address to, uint256[] memory tokenIds, uint256[] memory quantities)
        internal
        override(ERC1155Upgradeable, ERC1155SupplyUpgradeable)
    {
        super._update(from, to, tokenIds, quantities);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlUpgradeable, ERC1155Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    receive() external payable {}

    uint256[50] private __gap;
}
