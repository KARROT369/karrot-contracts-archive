// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Karrot Escrow V0 - Cross-chain lockproof sink for pxAssets with proof expiration
/// @notice Escrow contract with proof expiration to prevent stale proof acceptance
/// FIX: Renamed from KarrotEscrow to KarrotEscrowV0 to avoid naming conflict

contract KarrotEscrowV0 {
    address public owner;
    mapping(bytes32 => bool) public processedProofs;
    
    // FIX: Added proof expiration tracking
    mapping(bytes32 => uint256) public proofTimestamps;
    uint256 public constant PROOF_EXPIRY = 24 hours; // Proofs expire after 24 hours

    event Locked(address indexed user, address asset, uint256 amount, string targetChain, string targetAddress);
    event ProofAccepted(bytes32 indexed proofHash, uint256 timestamp);
    // FIX: Added event for proof expiration
    event ProofExpired(bytes32 indexed proofHash, uint256 submittedAt, uint256 expiredAt);

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

    // FIX: Added proof expiration check
    function acceptProof(bytes32 proofHash) external onlyOwner {
        require(!processedProofs[proofHash], "Already processed");
        
        // Check if proof has expired
        if (proofTimestamps[proofHash] > 0) {
            require(block.timestamp <= proofTimestamps[proofHash] + PROOF_EXPIRY, "Proof expired");
        } else {
            // First time seeing this proof, record timestamp
            proofTimestamps[proofHash] = block.timestamp;
        }
        
        processedProofs[proofHash] = true;
        emit ProofAccepted(proofHash, block.timestamp);
    }
    
    // FIX: Added function to check if a proof is expired
    function isProofExpired(bytes32 proofHash) external view returns (bool) {
        if (proofTimestamps[proofHash] == 0) return false; // Not submitted yet
        return block.timestamp > proofTimestamps[proofHash] + PROOF_EXPIRY;
    }
    
    // FIX: Added function to get remaining time before proof expires
    function getProofRemainingTime(bytes32 proofHash) external view returns (uint256) {
        if (proofTimestamps[proofHash] == 0) return 0;
        uint256 expiryTime = proofTimestamps[proofHash] + PROOF_EXPIRY;
        if (block.timestamp >= expiryTime) return 0;
        return expiryTime - block.timestamp;
    }
}

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
