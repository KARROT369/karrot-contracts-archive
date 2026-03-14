// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Karrot Escrow - Cross-chain lockproof sink for pxAssets
contract KarrotEscrow {
    address public owner;
    mapping(bytes32 => bool) public processedProofs;

    event Locked(address indexed user, address asset, uint256 amount, string targetChain, string targetAddress);
    event ProofAccepted(bytes32 indexed proofHash);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function lock(address asset, uint256 amount, string calldata targetChain, string calldata targetAddress) external {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        emit Locked(msg.sender, asset, amount, targetChain, targetAddress);
    }

    function acceptProof(bytes32 proofHash) external onlyOwner {
        require(!processedProofs[proofHash], "Already processed");
        processedProofs[proofHash] = true;
        emit ProofAccepted(proofHash);
    }
}

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
