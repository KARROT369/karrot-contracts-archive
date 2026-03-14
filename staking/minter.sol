// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract GatedNFTMinter is ERC721Enumerable, Ownable, ReentrancyGuard {
    IERC20 public ncelbi2Token;
    uint256 public nextTokenId;
    string public baseTokenURI;
    uint256 public requiredTokenBalance;

    event NFTMinted(address indexed minter, uint256 tokenId, uint256 heldBalance);
    event BaseURIUpdated(string newURI);
    event RequiredBalanceUpdated(uint256 newBalance);

    constructor(
        address _ncelbi2Token,
        string memory _name,
        string memory _symbol,
        string memory _baseTokenURI,
        uint256 _requiredTokenBalance
    ) ERC721(_name, _symbol) Ownable(msg.sender) {
        require(_ncelbi2Token != address(0), "Invalid token address");
        require(_requiredTokenBalance > 0, "Required balance must be > 0");
        
        ncelbi2Token = IERC20(_ncelbi2Token);
        baseTokenURI = _baseTokenURI;
        requiredTokenBalance = _requiredTokenBalance;
    }

    function mint() external nonReentrant {
        uint256 balance = ncelbi2Token.balanceOf(msg.sender);
        require(balance >= requiredTokenBalance, "Not enough NCELBI2 tokens to mint");
        
        uint256 tokenId = nextTokenId;
        nextTokenId++;
        
        _safeMint(msg.sender, tokenId);
        emit NFTMinted(msg.sender, tokenId, balance);
    }

    function setBaseTokenURI(string memory _uri) external onlyOwner {
        baseTokenURI = _uri;
        emit BaseURIUpdated(_uri);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseTokenURI;
    }

    function updateRequiredTokenBalance(uint256 _amount) external onlyOwner {
        require(_amount > 0, "Balance must be > 0");
        requiredTokenBalance = _amount;
        emit RequiredBalanceUpdated(_amount);
    }
}
