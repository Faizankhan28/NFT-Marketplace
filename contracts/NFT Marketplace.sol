// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC721 {
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function getApproved(uint256 tokenId) external view returns (address operator);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}

contract Project {
    
    address public owner;
    uint256 public marketplaceFee = 250;
    uint256 public constant MAX_FEE = 1000;
    bool private locked;
    
    struct Listing {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 price;
        bool active;
    }
    
    mapping(uint256 => Listing) public listings;
    uint256 public listingCounter;
    
    event NFTListed(uint256 indexed listingId, address indexed seller, address indexed nftContract, uint256 tokenId, uint256 price);
    event NFTSold(uint256 indexed listingId, address indexed buyer, address indexed seller, uint256 price);
    event ListingCancelled(uint256 indexed listingId);
    event MarketplaceFeeUpdated(uint256 newFee);
    
    constructor() {
        owner = msg.sender;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }
    
    modifier nonReentrant() {
        require(!locked, "Reentrant call");
        locked = true;
        _;
        locked = false;
    }
    
    function listNFT(address _nftContract, uint256 _tokenId, uint256 _price) external nonReentrant {
        require(_price > 0, "Price must be greater than zero");
        require(_nftContract != address(0), "Invalid NFT contract address");
        
        IERC721 nft = IERC721(_nftContract);
        require(nft.ownerOf(_tokenId) == msg.sender, "You don't own this NFT");
        require(
            nft.getApproved(_tokenId) == address(this) || 
            nft.isApprovedForAll(msg.sender, address(this)),
            "Marketplace not approved to transfer NFT"
        );
        
        uint256 listingId = listingCounter++;
        
        listings[listingId] = Listing({
            seller: msg.sender,
            nftContract: _nftContract,
            tokenId: _tokenId,
            price: _price,
            active: true
        });
        
        emit NFTListed(listingId, msg.sender, _nftContract, _tokenId, _price);
    }
    
    function buyNFT(uint256 _listingId) external payable nonReentrant {
        Listing storage listing = listings[_listingId];
        
        require(listing.active, "Listing is not active");
        require(msg.value >= listing.price, "Insufficient payment");
        require(msg.sender != listing.seller, "Cannot buy your own NFT");
        
        IERC721 nft = IERC721(listing.nftContract);
        require(nft.ownerOf(listing.tokenId) == listing.seller, "Seller no longer owns NFT");
        
        uint256 fee = (listing.price * marketplaceFee) / 10000;
        uint256 sellerAmount = listing.price - fee;
        
        listing.active = false;
        
        nft.safeTransferFrom(listing.seller, msg.sender, listing.tokenId);
        
        (bool sellerPaid, ) = payable(listing.seller).call{value: sellerAmount}("");
        require(sellerPaid, "Failed to pay seller");
        
        if (fee > 0) {
            (bool feePaid, ) = payable(owner).call{value: fee}("");
            require(feePaid, "Failed to pay marketplace fee");
        }
        
        if (msg.value > listing.price) {
            (bool refunded, ) = payable(msg.sender).call{value: msg.value - listing.price}("");
            require(refunded, "Failed to refund excess payment");
        }
        
        emit NFTSold(_listingId, msg.sender, listing.seller, listing.price);
    }
    
    function cancelListing(uint256 _listingId) external nonReentrant {
        Listing storage listing = listings[_listingId];
        
        require(listing.active, "Listing is not active");
        require(listing.seller == msg.sender, "Only seller can cancel listing");
        
        listing.active = false;
        
        emit ListingCancelled(_listingId);
    }
    
    function getListing(uint256 _listingId) external view returns (address seller, address nftContract, uint256 tokenId, uint256 price, bool active) {
        Listing memory listing = listings[_listingId];
        return (listing.seller, listing.nftContract, listing.tokenId, listing.price, listing.active);
    }
    
    function updateMarketplaceFee(uint256 _newFee) external onlyOwner {
        require(_newFee <= MAX_FEE, "Fee too high");
        marketplaceFee = _newFee;
        emit MarketplaceFeeUpdated(_newFee);
    }
    
    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        
        (bool success, ) = payable(owner).call{value: balance}("");
        require(success, "Withdrawal failed");
    }
    
    function getTotalListings() external view returns (uint256) {
        return listingCounter;
    }
}
