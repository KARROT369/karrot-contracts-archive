// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Karrot Escrow V1 - Cross-chain lockproof sink with oracle-burn capabilities
/// @notice Enhanced escrow with oracle-only burn functionality for wrapped assets
/// FIX: Renamed from KarrotEscrow to KarrotEscrowV1 to avoid naming conflict

contract KarrotEscrowV1 {
    address public owner;
    address public oracle;
    mapping(bytes32 => bool) public processedProofs;
    mapping(bytes32 => uint256) public proofTimestamps;
    uint256 public constant PROOF_EXPIRY = 24 hours;
    
    // FIX: Track wrapped asset burns
    mapping(address => uint256) public totalBurned;
    mapping(bytes32 => bool) public burnedProofs;

    event Locked(address indexed user, address asset, uint256 amount, string targetChain, string targetAddress);
    event ProofAccepted(bytes32 indexed proofHash, uint256 timestamp);
    event ProofExpired(bytes32 indexed proofHash, uint256 submittedAt, uint256 expiredAt);
    // FIX: Enhanced burn event with actual burn details
    event WrappedAssetBurned(address indexed asset, uint256 amount, bytes32 indexed proofHash, address indexed burnedBy);
    event OracleSet(address indexed previousOracle, address indexed newOracle);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    // FIX: Added onlyOracle modifier
    modifier onlyOracle() {
        require(msg.sender == oracle, "Not authorized oracle");
        _;
    }

    constructor() {
        owner = msg.sender;
    }
    
    // FIX: Function to set/change oracle address
    function setOracle(address _oracle) external onlyOwner {
        address previousOracle = oracle;
        oracle = _oracle;
        emit OracleSet(previousOracle, _oracle);
    }

    function lock(address asset, uint256 amount, string calldata targetChain, string calldata targetAddress) external {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        emit Locked(msg.sender, asset, amount, targetChain, targetAddress);
    }

    function acceptProof(bytes32 proofHash) external onlyOwner {
        require(!processedProofs[proofHash], "Already processed");
        
        if (proofTimestamps[proofHash] > 0) {
            require(block.timestamp <= proofTimestamps[proofHash] + PROOF_EXPIRY, "Proof expired");
        } else {
            proofTimestamps[proofHash] = block.timestamp;
        }
        
        processedProofs[proofHash] = true;
        emit ProofAccepted(proofHash, block.timestamp);
    }
    
    // FIX: Actually implement burnWrappedAsset with onlyOracle modifier and proper burn logic
    function burnWrappedAsset(address asset, uint256 amount, bytes32 proofHash) external onlyOracle {
        require(!burnedProofs[proofHash], "Asset already burned for this proof");
        require(processedProofs[proofHash], "Proof not yet accepted");
        require(block.timestamp <= proofTimestamps[proofHash] + PROOF_EXPIRY, "Proof expired");
        
        // Mark as burned to prevent double-burn
        burnedProofs[proofHash] = true;
        
        // Track total burned
        totalBurned[asset] += amount;
        
        // FIX: In production, this would call the token's burn function
        // For wrapped assets that don't support burn, we transfer to dead address
        // or call a custom burn mechanism
        IERC20(asset).transfer(address(0xdead), amount);
        
        emit WrappedAssetBurned(asset, amount, proofHash, msg.sender);
    }
    
    // FIX: View function to check if asset has been burned for a proof
    function isBurned(bytes32 proofHash) external view returns (bool) {
        return burnedProofs[proofHash];
    }
    
    // FIX: View function to get total burned amount for an asset
    function getTotalBurned(address asset) external view returns (uint256) {
        return totalBurned[asset];
    }
    
    function isProofExpired(bytes32 proofHash) external view returns (bool) {
        if (proofTimestamps[proofHash] == 0) return false;
        return block.timestamp > proofTimestamps[proofHash] + PROOF_EXPIRY;
    }
    
    function getProofRemainingTime(bytes32 proofHash) external view returns (uint256) {
        if (proofTimestamps[proofHash] == 0) return 0;
        uint256 expiryTime = proofTimestamps[proofHash] + PROOF_EXPIRY;
        if (block.timestamp >= expiryTime) return 0;
        return expiryTime - block.timestamp;
    }
}

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}
