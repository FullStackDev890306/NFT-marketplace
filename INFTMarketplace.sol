// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface INFTMarketplace{
    function createAuction(uint256 startPrice,uint256 reservedPrice, address nftAddr,uint256 tokenId) external returns(uint256);
    function placeBid(uint256 id, uint256 numberOfDummyTokens) external returns(bool);
    function getAllBids(uint256 id) external view returns (address[] memory, uint256[] memory);
    function redeemToken( uint256 id ) external returns(bool);
    function claimFunds(uint256 id) external returns(bool);
    function cancelAuction(uint256 id) external returns(bool);
    event NewBid(address bidder, uint bid); // A new bid was placed
    event RedeemToken(address withdrawer); // The auction winner withdrawed the token
    event ClaimFunds(address withdrawer, uint256 amount); // The auction owner withdrawed the funds
    event AuctionCanceled(); // The auction was cancelled
    event NewAuction(uint256 id, uint256 _endTime, uint256 _startPrice,uint256 _reservedPrice, address _nftAddr,uint256 _tokenId);
}