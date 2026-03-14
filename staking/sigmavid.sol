// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title SigmaVid
 * @notice NFT contract for Sigma video content with gated access
 */
contract SigmaVid is ERC721, Ownable, ReentrancyGuard {
    string private _baseTokenURI;
    uint256 public nextTokenId;
    uint256 public maxSupply;
    mapping(address => bool) public authorizedMinters;

    event BaseURIChanged(string newBaseURI);
    event MinterAuthorized(address minter, bool authorized);
    event Minted(address indexed to, uint256 tokenId);
    event MaxSupplySet(uint256 maxSupply);

    modifier onlyAuthorized() {
        require(owner() == msg.sender || authorizedMinters[msg.sender], "Not authorized");
        _;
    }

    constructor(string memory baseURI, uint256 _maxSupply) ERC721("SigmaVid", "SVID") Ownable(msg.sender) {
        require(_maxSupply > 0, "Invalid max supply");
        _baseTokenURI = baseURI;
        maxSupply = _maxSupply;
    }

    function mint(address to) external onlyAuthorized nonReentrant {
        require(to != address(0), "Invalid recipient");
        require(nextTokenId < maxSupply, "Max supply reached");
        
        _safeMint(to, nextTokenId);
        emit Minted(to, nextTokenId);
        nextTokenId++;
    }

    function batchMint(address[] calldata recipients) external onlyAuthorized nonReentrant {
        require(nextTokenId + recipients.length <= maxSupply, "Would exceed max supply");
        
        for (uint i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Invalid recipient");
            _safeMint(recipients[i], nextTokenId);
            emit Minted(recipients[i], nextTokenId);
            nextTokenId++;
        }
    }

    function setAuthorizedMinter(address minter, bool authorized) external onlyOwner {
        require(minter != address(0), "Invalid minter");
        authorizedMinters[minter] = authorized;
        emit MinterAuthorized(minter, authorized);
    }

    function setMaxSupply(uint256 _maxSupply) external onlyOwner {
        require(_maxSupply > nextTokenId, "Below current supply");
        maxSupply = _maxSupply;
        emit MaxSupplySet(_maxSupply);
    }

    function setBaseURI(string memory newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
        emit BaseURIChanged(newBaseURI);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }
}
