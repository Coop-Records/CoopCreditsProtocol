// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.18;

interface IMultiTokenDropMarket {
    struct GetFixedPriceSaleResults {
        address multiTokenContract;
        uint256 tokenId;
        uint256 pricePerQuantity;
        uint256 quantityAvailableToMint;
        address payable creatorPaymentAddress;
        uint256 generalAvailabilityStartTime;
        uint256 mintEndTime;
        uint256 creatorRevenuePerQuantity;
        uint256 referrerRewardPerQuantity;
        uint256 worldCuratorRevenuePerQuantity;
        uint256 protocolFeePerQuantity;
    }

    function getSaleTermsForToken(address nftContract, uint256 tokenId) external view returns (uint256 saleTermsId);

    function getFixedPriceSale(uint256 saleTermsId, address payable referrer)
        external
        view
        returns (GetFixedPriceSaleResults memory results);

    function mintFromFixedPriceSale(
        uint256 saleTermsId,
        uint256 tokenQuantity,
        address tokenRecipient,
        address referrer
    ) external payable;
}
