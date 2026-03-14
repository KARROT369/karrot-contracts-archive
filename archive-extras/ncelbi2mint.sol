// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract GatedNFTMinter is ERC721, Ownable {
    IERC20 public gatingToken;
    uint256 public nextTokenId;
    string private baseTokenURI;

    constructor(address _gatingToken, string memory _baseURI) ERC721("Karrot404NFT", "K404") {
        gatingToken = IERC20(_gatingToken);
        baseTokenURI = _baseURI;
    }

    function mint() external {
        require(gatingToken.balanceOf(msg.sender) > 0, "Must hold gating token to mint");
        _safeMint(msg.sender, nextTokenId);
        nextTokenId++;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseTokenURI;
    }

    function setBaseURI(string memory _baseURI) external onlyOwner {
        baseTokenURI = _baseURI;
    }
}
