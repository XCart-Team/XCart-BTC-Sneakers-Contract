// SPDX-License-Identifier: MIT
// Creator: XCart Dev Team

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

error MintedQueryForZeroAddress();
error PiecesNotEnoughToSynthesize();

contract XCART is ERC1155, Ownable {
    using SafeERC20 for IERC20;
    enum Status {
        Waiting,
        Started,
        Opened,
        Finished
    }

    struct AddressData {
        // Sum of minted and synthesized.
        uint64 nft_balance;
        // Only for minted ones.
        uint64 nft_num_minted;
        // From id to number.
        mapping(uint8 => uint16) piecesData;
    }

    Status public status;

    // Instead of uri_
    string private _baseURI;

    // Price
    uint256 private NFT_PRICE = 0.168 * 10**18; // 0.168 ETH
    uint256 private PIECE_PRICE = 0.0188 * 10**18; // 0.0188 ETH

    // For NFT
    uint8 private MAX_MINT_PER_ADDR = 2;

    // This value cannot be greater than 2800.
    uint16 private SYN_SUPPLY = 0;
    // This value cannot be greater than 7200.
    uint16 private MINT_SUPPLY = 0;
    // Offset between mint & syn
    uint16 private _offset = 7205;

    // The tokenId of the next token to be minted.
    uint256 private _currentMintNFTIndex;
    uint256 private _currentSynNFTIndex;

    // For pieces
    uint8 public constant ID_P1 = 0;
    uint8 public constant ID_P2 = 1;
    uint8 public constant ID_P3 = 2;
    uint8 public constant ID_P4 = 3;
    uint8 public constant ID_P5 = 4;

    uint16 public constant MAX_PIECES = 2800;

    mapping(address => AddressData) private _addressData;
    mapping(uint8 => uint16) private _piecesMinted;

    event NFTMinted(address indexed minter, uint256 amount, uint256 firstTokenId, address inviter);
    event NFTSynthesized(address owner, uint256 tokenId);
    event NFTExchanged(address indexed owner, uint256 tokenId);
    event PiecesMinted(address indexed minter, uint256 amount, uint256 tokenId, address inviter);
    event PiecesAirdropped(address indexed receiver, uint256 amount);
    event StatusChanged(Status status);
    event BaseURIChanged(string newBaseURI);

    constructor(string memory uri_) ERC1155("XCART") {
        _baseURI = uri_;
        _currentMintNFTIndex = _genesisNFTId();
        _currentSynNFTIndex = _offset;
    }

    function _genesisNFTId() internal view virtual returns (uint256) {
        return 5;
    }

    function totalSupply() public view returns (uint256) {
        unchecked {
            return MINT_SUPPLY + SYN_SUPPLY;
        }
    }

    function totalMintSupply() public view returns (uint256) {
        unchecked {
            return MINT_SUPPLY;
        }
    }

    function totalSynSupply() public view returns (uint256) {
        unchecked {
            return SYN_SUPPLY;
        }
    }

    function perAccountSupply() public view returns (uint256) {
        unchecked {
            return MAX_MINT_PER_ADDR;
        }
    }

    // How many NFTs has been minted.
    function totalNFTMinted() public view returns (uint256) {
        unchecked {
            return _currentMintNFTIndex - _genesisNFTId();
        }
    }

    function totalNFTSynthesized() public view returns (uint256) {
        unchecked {
            return _currentSynNFTIndex - _offset;
        }
    }

    // Max mint number for each address
    function maxMintNumberPerAddress() public view returns (uint256) {
        unchecked {
            return uint256(MAX_MINT_PER_ADDR);
        }
    }

    // How many pieces has been minted.
    function piecesMinted(uint8 pid) public view returns (uint256) {
        unchecked {
            return uint256(_piecesMinted[pid]);
        }
    }

    function numberMinted(address owner_) public view returns (uint256) {
        if (owner_ == address(0)) revert MintedQueryForZeroAddress();
        return uint256(_addressData[owner_].nft_num_minted);
    }

    // Read-only price functions
    function nftPrice() public view returns (uint256) {
        unchecked {
            return NFT_PRICE;
        }
    }

    function piecePrice() public view returns (uint256) {
        unchecked {
            return PIECE_PRICE;
        }
    }

    function mintNFT(uint256 quantity_, address inviter_) public payable {
        require(status == Status.Started || status == Status.Opened, "Sale has not started");
        require(tx.origin == msg.sender, "Contract calls are not allowed");
        require(quantity_ > 0, "At least one NFT must be minted");
        require(
            totalNFTMinted() + quantity_ <= MINT_SUPPLY,
            "Short minted supply(NFT)"
        );
        require(
            numberMinted(msg.sender) + quantity_ <= MAX_MINT_PER_ADDR,
            "This address has reached the limit of minting."
        );
        require(msg.value >= NFT_PRICE * quantity_, "Not enough ETH sent: check price.");

        uint256[] memory ids = new uint256[] (quantity_);
        uint256[] memory amounts = new uint256[] (quantity_);
        uint256 index = _currentMintNFTIndex;
        for (uint256 i = 0; i < quantity_; i++) {
            ids[i] = index;
            amounts[i] = 1;
            index ++;
        }
        _mintBatch(msg.sender, ids, amounts, "");
        _currentMintNFTIndex += quantity_;
        _addressData[msg.sender].nft_balance += uint64(quantity_);
        _addressData[msg.sender].nft_num_minted += uint64(quantity_);

        _refundIfOver(NFT_PRICE * quantity_);
        emit NFTMinted(msg.sender, quantity_, ids[0], inviter_);
    }

    function mintPiece(address inviter_) public payable {
        require(status == Status.Started || status == Status.Opened, "Sale has not started");
        require(tx.origin == msg.sender, "Contract calls are not allowed");
        require( 
            piecesMinted(ID_P1) + 
            piecesMinted(ID_P2) + 
            piecesMinted(ID_P3) + 
            piecesMinted(ID_P4) + 
            piecesMinted(ID_P5) < MAX_PIECES * 5, "Short minted supply(Pieces)");

        require(msg.value >= PIECE_PRICE, "Not enough ETH sent: check price.");

        uint8 random = _randomInFive();
        if (piecesMinted(random) == MAX_PIECES) {
            for (uint8 i = 0; i < 5; i++) {
                if (piecesMinted(i) < MAX_PIECES) {
                    random = i;
                    break;
                }
            }
        }
        _mint(msg.sender, random, 1, "");
        _piecesMinted[random] += 1;
        _addressData[msg.sender].piecesData[random] += 1;
        uint256 tokenId = random;

        _refundIfOver(PIECE_PRICE);
        emit PiecesMinted(msg.sender, 1, tokenId, inviter_);
    }

    function synthesize() public payable {
        require(status >= Status.Started, "Sale has not started");
        require(tx.origin == msg.sender, "Contract calls are not allowed");
        require(
            totalNFTSynthesized() <= SYN_SUPPLY,
            "Short synthesized NFT supply"
        );
        for(uint8 i = 0 ; i < 5 ; i ++) {
            if(_addressData[msg.sender].piecesData[i] <= 0) {
                revert PiecesNotEnoughToSynthesize();
            }
        }
        for (uint8 i = 0 ; i < 5 ; i ++) {
            _burn(msg.sender, i, 1);
            _addressData[msg.sender].piecesData[i] -= 1;
        }
        _synthesizeNFT();
    }

    function exchange(uint256 nft_id_) public payable {
        require(status >= Status.Started, "Sale has not started");
        require(tx.origin == msg.sender, "Contract calls are not allowed");
        require(balanceOf(msg.sender, nft_id_) > 0, "Address does not have any NFTs");
        require(nft_id_ >= _genesisNFTId(), "Cannot exchange a piece.");
        _burn(msg.sender, nft_id_, 1);
        _addressData[msg.sender].nft_balance -= 1;
        emit NFTExchanged(msg.sender, nft_id_);
    }

    function _synthesizeNFT() private {
        require(status >= Status.Started, "Sale has not started");
        require(tx.origin == msg.sender, "Contract calls are not allowed");
        require(
            totalNFTSynthesized() <= SYN_SUPPLY,
            "Short synthesized NFT supply"
        );
        uint256 tokenId = _currentSynNFTIndex;
        _mint(msg.sender, _currentSynNFTIndex, 1, "");
        _currentSynNFTIndex += 1;
        _addressData[msg.sender].nft_balance += 1;
        emit NFTSynthesized(msg.sender, tokenId);
    }

    function setStatus(Status status_) public onlyOwner {
        status = status_;
        emit StatusChanged(status);
    }

    function uri(uint256 tokenId_) public view virtual override returns (string memory) {
        if (tokenId_ < _genesisNFTId()) {
            return "https://bafybeie2mbntsrgcgiw3svgqutbz7ovtpfcxjuotu5mbhjy4s3xduiugry.ipfs.nftstorage.link/{id}.json";
        }
        return _baseURI;
    }

    function setURI(string calldata newURI_) public onlyOwner {
        _baseURI = newURI_;
        emit BaseURIChanged(newURI_);
    }

    function setMintSupply(uint16 mintSupply_) public onlyOwner {
        require(mintSupply_ > MINT_SUPPLY, "Mint supply value must be greater than original value");
        require(mintSupply_ <= 7200, "Mint supply value must be less than or equal 7200");
        MINT_SUPPLY = mintSupply_;
    }

    function setSynSupply(uint16 synSupply_) public onlyOwner {
        require(synSupply_ > SYN_SUPPLY, "Syn supply value must be greater than original value");
        require(synSupply_ <= 2800, "Syn supply value must be less than or equal 2800");
        SYN_SUPPLY = synSupply_;
    }

    function setMaxMintNumberPerAddress(uint8 maxMintNumber_) public onlyOwner {
        require(maxMintNumber_ > 0, "Value must greater than 0");
        require(maxMintNumber_ < 256, "Value must less than 256");
        MAX_MINT_PER_ADDR = maxMintNumber_;
    }

    function setMintPrice(uint256 mintPrice_) public onlyOwner {
        require(mintPrice_ > 0, "Mint price must be greater than 0");
        NFT_PRICE = mintPrice_;
    }

    function setPiecePrice(uint256 pPrice_) public onlyOwner {
        require(pPrice_ > 0, "Piece price must be greater than 0");
        PIECE_PRICE = pPrice_;
    }

    function _refundIfOver(uint256 price_) private {
        if (msg.value > price_) {
            payable(msg.sender).transfer(msg.value - price_);
        }
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public override {
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "ERC1155: caller is not token owner nor approved"
        );
        require(amount < 65536, "Amount cannot over 65536");
        _safeTransferFrom(from, to, id, amount, data);

        if (id < _genesisNFTId()) {
            _addressData[from].piecesData[uint8(id)] -= uint16(amount);
            _addressData[to].piecesData[uint8(id)] += uint16(amount);
        } else {
            _addressData[from].nft_balance -= uint16(amount);
            _addressData[to].nft_balance += uint16(amount);
        }
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public override {
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "ERC1155: caller is not token owner nor approved"
        );
        _safeBatchTransferFrom(from, to, ids, amounts, data);

        for (uint256 i = 0; i < ids.length; ++i) {
            require(amounts[i] < 65536, "Amount cannot over 65536");
            if (ids[i] < _genesisNFTId()) {
                _addressData[from].piecesData[uint8(ids[i])] -= uint16(amounts[i]);
                _addressData[to].piecesData[uint8(ids[i])] += uint16(amounts[i]);
            } else {
                _addressData[from].nft_balance -= uint16(amounts[i]);
                _addressData[to].nft_balance += uint16(amounts[i]);
            }
        }
    }

    // Get a random number in 5
    function _randomInFive() private view returns (uint8) {
        uint256 x = uint256(keccak256(abi.encodePacked(
                    (block.timestamp) +
                    (block.difficulty) +
                    ((uint256(keccak256(abi.encodePacked(block.coinbase)))) / (block.timestamp)) +
                    (block.gaslimit) +
                    ((uint256(keccak256(abi.encodePacked(msg.sender)))) / (block.timestamp)) +
                    (block.number)
                ))) % 5;
        return uint8(x);
    }

    function withdrawETH(address payable recipient_) external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success, ) = recipient_.call{value: balance}("");
        require(success, "Withdraw successfully");
    }

    function withdrawSafeERC20Token(address tokenContract_, address payable recipient_, uint256 amount_) external onlyOwner {
        IERC20 tokenContract = IERC20(tokenContract_);
        tokenContract.safeTransfer(recipient_, amount_);
    }

    function airdropPieces(address receiver_, uint16 amount_) external onlyOwner {
        require(piecesMinted(ID_P1) < MAX_PIECES - amount_, "Short minted supply(Piece id: 0)");
        require(piecesMinted(ID_P2) < MAX_PIECES - amount_, "Short minted supply(Piece id: 1)");
        require(piecesMinted(ID_P3) < MAX_PIECES - amount_, "Short minted supply(Piece id: 2)");
        require(piecesMinted(ID_P4) < MAX_PIECES - amount_, "Short minted supply(Piece id: 3)");
        require(piecesMinted(ID_P5) < MAX_PIECES - amount_, "Short minted supply(Piece id: 4)");

        for (uint8 i = 0; i < 5; i ++) {
            _mint(receiver_, i, amount_, "");
            _piecesMinted[i] += amount_;
            _addressData[receiver_].piecesData[i] += amount_;
        }
        emit PiecesAirdropped(receiver_, amount_);
    }
}
