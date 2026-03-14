// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract GatedNFTMinter is ERC721Enumerable, Ownable {
    IERC20 public ncelbi2Token;
    uint256 public nextTokenId;
    string public baseTokenURI;
    uint256 public requiredTokenBalance;

    constructor(
        address _ncelbi2Token,
        string memory _name,
        string memory _symbol,
        string memory _baseTokenURI,
        uint256 _requiredTokenBalance
    ) ERC721(_name, _symbol) {
        ncelbi2Token = IERC20(_ncelbi2Token);
        baseTokenURI = _baseTokenURI;
        requiredTokenBalance = _requiredTokenBalance;
    }

    function mint() external {
        require(
            ncelbi2Token.balanceOf(msg.sender) >= requiredTokenBalance,
            "Not enough NCELBI2 tokens to mint"
        );
        _safeMint(msg.sender, nextTokenId);
        nextTokenId++;
    }

    function setBaseTokenURI(string memory _uri) external onlyOwner {
        baseTokenURI = _uri;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseTokenURI;
    }

    function updateRequiredTokenBalance(uint256 _amount) external onlyOwner {
        requiredTokenBalance = _amount;
    }
}
