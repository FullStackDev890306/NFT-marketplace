// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./INFTMarketplace.sol";

contract NFTMarketplace is ReentrancyGuard, INFTMarketplace
{
    address dummyTokenAddress;
    address devAddress;
    using Counters for Counters.Counter;
    Counters.Counter public auctionId;
    enum AuctionState {
        OPEN,
        CANCELLED,
        ENDED
    }
    struct Bid {
        address bidder;
        uint256 bid;
    }
    struct Auction {
        uint256 aucId;
        uint256 startTime;
        uint256 endTime;
        uint256 startPrice;
        uint256 reservedPrice;
        address creator;
        address nftAddr; // The address of the NFT contract
        uint256 tokenId; // The id of the token
        uint256 highestBid;
        address highestBidder;
        AuctionState aucState;
        bool isCancelled;
        bool tokenRedeemed;
        bool fundClaimed;
    }

    Auction[] auctions;
    mapping(uint256 => Bid[]) bids;

    constructor(address _dummyTokenAddress, address _devAddress){
        dummyTokenAddress = _dummyTokenAddress;
        devAddress = _devAddress;
    }

    // create auction
    function createAuction(uint256 _startPrice,uint256 _reservedPrice, address _nftAddr,uint256 _tokenId) public returns(uint256){
        uint256 aucId = auctionId.current();
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 5 minutes;
        AuctionState aucState;
        aucState = AuctionState.OPEN;
        auctions.push(Auction(aucId,startTime,endTime,_startPrice,_reservedPrice,payable(msg.sender),_nftAddr,_tokenId,0,address(0),aucState,false,false,false));
        auctionId.increment();
        IERC721 nft = IERC721(_nftAddr);
        nft.transferFrom(msg.sender, address(this), _tokenId);
        emit NewAuction(aucId,endTime,_startPrice,_reservedPrice,_nftAddr,_tokenId);
        return aucId;
    }
    
    // Place a bid on the auction
    function placeBid(uint256 _id, uint256 _numberOfDummyTokens) public isValidAuction(_id) returns(bool){
        auctions[_id].aucState = getAuctionState(_id);
        require(msg.sender != auctions[_id].creator,"Cannot bid your NFT"); // The auction creator can not place a bid
        require(auctions[_id].aucState == AuctionState.OPEN,"Auction's closed"); // The auction must be open
        require(GetUserTokenBalance() > auctions[_id].highestBid,"Need more token.");
        require(_numberOfDummyTokens > auctions[_id].highestBid,"Need more token.");
        bids[_id].push(Bid(msg.sender,_numberOfDummyTokens));
        uint256 lastHighestBid = auctions[_id].highestBid; // The last highest bid
        address lastHighestBidder = auctions[_id].highestBidder;
        auctions[_id].highestBid = _numberOfDummyTokens; // The new highest bid
        auctions[_id].highestBidder = msg.sender; // The address of the new highest bidder
        IERC20(dummyTokenAddress).transferFrom(msg.sender, address(this), _numberOfDummyTokens);
        if(lastHighestBid != 0){ // if there is a bid
            IERC20(dummyTokenAddress).transfer(lastHighestBidder, lastHighestBid);
        }
        emit NewBid(msg.sender,_numberOfDummyTokens); // emit a new bid event
        return true; // The bid was placed successfully
    }

    // Withdraw the token after the auction is over
    function redeemToken(uint256 _id) public  isValidAuction(_id) returns(bool){
        auctions[_id].aucState = getAuctionState(_id);
        require(auctions[_id].aucState == AuctionState.ENDED, "Not Ended yet.");  
        require(msg.sender == auctions[_id].highestBidder,"Not highest bidder"); // The highest bidder can only withdraw the token
        require(!auctions[_id].tokenRedeemed,"You've redeemed it.");
        auctions[_id].tokenRedeemed=true;
        IERC721 nft = IERC721(auctions[_id].nftAddr);
        nft.transferFrom(address(this), auctions[_id].highestBidder, auctions[_id].tokenId); // Transfer the token to the highest bidder
        emit RedeemToken(auctions[_id].highestBidder); // Emit a withdraw token event
        return true;
    }
    // Withdraw the funds after the auction is over
    function claimFunds(uint256 _id) public isValidAuction(_id)   returns(bool){ 
        auctions[_id].aucState = getAuctionState(_id);
        require(auctions[_id].aucState == AuctionState.ENDED);  
        require(msg.sender == auctions[_id].creator,"Not creator"); 
        require(!auctions[_id].fundClaimed,"You've claimed it.");
        auctions[_id].fundClaimed = true;
        IERC20 erc20 = IERC20(dummyTokenAddress);
        erc20.transfer(auctions[_id].creator, auctions[_id].highestBid * 9 / 10);
        erc20.transfer(devAddress, auctions[_id].highestBid / 10);
        emit ClaimFunds(msg.sender,auctions[_id].highestBid); 
        return true;
    }
    
    function cancelAuction(uint256 _id) public isValidAuction(_id)  returns(bool){ // Cancel the auction
        auctions[_id].aucState = getAuctionState(_id);
        require(msg.sender == auctions[_id].creator,"Not creator"); 
        require(auctions[_id].aucState == AuctionState.OPEN,"Auction's closed");
        require(auctions[_id].highestBid<auctions[_id].reservedPrice,"Reserved price is reached"); // The auction must not be cancelled if bid>reserved price
        auctions[_id].isCancelled = true; // The auction has been cancelled
        auctions[_id].aucState = AuctionState.CANCELLED;
        IERC721 nft = IERC721(auctions[_id].nftAddr);
        nft.transferFrom(address(this), auctions[_id].creator, auctions[_id].tokenId); // Transfer the NFT token back to the auction creator
        if(auctions[_id].highestBid != 0) 
            IERC20(dummyTokenAddress).transferFrom(address(this), auctions[_id].highestBidder, auctions[_id].highestBid);
        emit AuctionCanceled(); // Emit Auction Canceled event
        return true;
    } 

    // Get the auction state
    function getAuctionState(uint256 _id) public isValidAuction(_id) view returns(AuctionState) {
        
        if(auctions[_id].isCancelled) return AuctionState.CANCELLED; // If the auction is cancelled return CANCELLED
        if(block.timestamp >= (auctions[_id].startTime + 5 minutes)) return AuctionState.ENDED; // The auction is over if the block timestamp is greater than the end timestamp, return ENDED
        else return AuctionState.OPEN; //Auction ongoing
    }
        
    // Return all the infomation of auction
    function getStartTime(uint256 _id) external isValidAuction(_id) view returns(uint256){
        return auctions[_id].startTime;
    }
    function getEndTime(uint256 _id) external isValidAuction(_id) view returns(uint256){
        return auctions[_id].startTime + 5 minutes;
    }
    function getStartPrice(uint256 _id) external isValidAuction(_id) view returns(uint256){
        return auctions[_id].startPrice;
    }
    function getReservedPrice(uint256 _id) external isValidAuction(_id) view returns(uint256){
        return auctions[_id].reservedPrice;
    }
    function getCreator(uint256 _id) external isValidAuction(_id) view returns(address){
        return auctions[_id].creator;
    }
    function getNftAddress(uint256 _id) external isValidAuction(_id) view returns(address){
        return auctions[_id].nftAddr;
    }
    function getTokenId(uint256 _id) external isValidAuction(_id) view returns(uint256){
        return auctions[_id].tokenId;
    }
    function getAllBids(uint256 _id) external isValidAuction(_id) view returns(address[] memory, uint256[] memory){
        address[] memory addrs = new address[](bids[_id].length);
        uint256[] memory bidPrice = new uint256[](bids[_id].length);
        for (uint256 i = 0; i < bids[_id].length; i++) {
            addrs[i] = bids[_id][i].bidder;
            bidPrice[i] = bids[_id][i].bid;
        }
        return (addrs, bidPrice);
    }
    function getHighestBid(uint256 _id) external isValidAuction(_id) view returns(uint256){
        return auctions[_id].highestBid;
    }
    function getHighestBidder(uint256 _id) external isValidAuction(_id) view returns(address){
        return auctions[_id].highestBidder;
    }
    function getIsCancelled(uint256 _id) external isValidAuction(_id) view returns(bool){
        return auctions[_id].isCancelled;
    }
    function getTokenRedeemed(uint256 _id) external isValidAuction(_id) view returns(bool){
        return auctions[_id].tokenRedeemed;
    }
    function getFundClaimed(uint256 _id) external isValidAuction(_id) view returns(bool){
        return auctions[_id].fundClaimed;
    }
    function GetUserTokenBalance() public view returns(uint256){ 
       return IERC20(dummyTokenAddress).balanceOf(msg.sender);// balancdOf function is already declared in ERC20 token function
   }
    function GetAllowance() public view returns(uint256){
       return IERC20(dummyTokenAddress).allowance(msg.sender, address(this));
   }
    modifier isValidAuction(uint256 _id){
        require(_id<=auctionId.current(),"Invalid ID");
        _;
    }
    event NewAuction(uint256 id, uint256 _endTime, uint256 _startPrice,uint256 _reservedPrice, address _nftAddr,uint256 _tokenId);
    event NewBid(address bidder, uint256 bid); // A new bid was placed
    event RedeemToken(address withdrawer); // The auction winner withdrawed the token
    event ClaimFunds(address withdrawer, uint256 amount); // The auction owner withdrawed the funds
    event AuctionCanceled(); // The auction was cancelled
}
