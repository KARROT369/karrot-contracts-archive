// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";

contract DadBule1190NFT is ERC721, ERC721URIStorage, Ownable, ERC721Burnable {
    uint256 private _nextTokenId;

    // Optional: max supply if you want limited edition
    uint256 public constant MAX_SUPPLY = 100; // example

    constructor() ERC721("DadBule Pioneers", "DBP") Ownable(msg.sender) {}

    // Only owner (you/project wallet) can mint
    function safeMint(address to, string memory uri) public onlyOwner {
        require(_nextTokenId < MAX_SUPPLY, "Max supply reached");
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
    }

    // Anyone holding the NFT can burn it (to redeem)
    // You can add extra logic if desired (e.g. only after certain date)
    function burn(uint256 tokenId) public override {
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        super.burn(tokenId);
        // Optional: emit event for your backend to track redemptions
        emit Transfer(msg.sender, address(0), tokenId);
    }

    // Required overrides for multiple inheritance
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721URIStorage)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721)
    {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }
}