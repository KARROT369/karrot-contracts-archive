// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Karrot Escrow - IMMUTABLE VERSION
/// @notice Cross-chain lockproof sink - NO ADMIN, NO PAUSE, NO ORACLE SETTING
/// @dev All oracles and parameters set at deployment. Cannot be changed.

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address owner) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract KarrotEscrow_Immutable is ReentrancyGuard {
    // ============ Structs ============
    struct LockInfo {
        address user;
        address asset;
        uint256 amount;
        string targetChain;
        string targetAddress;
        uint256 timestamp;
        bool released;
    }
    
    // ============ Immutable State ============
    mapping(bytes32 => bool) public processedProofs;
    mapping(bytes32 => uint256) public proofTimestamps;
    mapping(bytes32 => bool) public burnedProofs;
    mapping(address => uint256) public totalBurned;
    mapping(address => uint256) public totalLocked;
    mapping(bytes32 => LockInfo) public locks;
    
    // Oracles - set in constructor, never changeable
    mapping(address => bool) public isOracle;
    address[] public oracles;
    
    uint256 public immutable PROOF_EXPIRY;
    
    // ============ Events ============
    event Locked(bytes32 indexed lockId, address indexed user, address asset, uint256 amount, string targetChain, string targetAddress);
    event ProofAccepted(bytes32 indexed proofHash, uint256 timestamp);
    event ProofExpired(bytes32 indexed proofHash, uint256 submittedAt, uint256 expiredAt);
    event WrappedAssetBurned(address indexed asset, uint256 amount, bytes32 indexed proofHash, address indexed burnedBy);
    event Released(bytes32 indexed lockId, address indexed to, address asset, uint256 amount);
    event EmergencyWithdraw(address indexed asset, uint256 amount);
    
    // ============ Modifiers ============
    modifier onlyOracle() {
        require(isOracle[msg.sender], "Not authorized oracle");
        _;
    }
    
    // ============ Constructor - ALL ORACLES SET HERE ============
    constructor(
        address[] memory _oracles,
        uint256 _proofExpiry
    ) {
        require(_oracles.length > 0, "Need at least one oracle");
        require(_proofExpiry > 0, "Proof expiry must be > 0");
        
        PROOF_EXPIRY = _proofExpiry;
        
        for (uint i = 0; i < _oracles.length; i++) {
            require(_oracles[i] != address(0), "Invalid oracle address");
            require(!isOracle[_oracles[i]], "Duplicate oracle");
            isOracle[_oracles[i]] = true;
            oracles.push(_oracles[i]);
        }
    }
    
    // ============ Core Functions ============
    
    /// @notice Lock tokens for cross-chain transfer
    function lock(
        address asset, 
        uint256 amount, 
        string calldata targetChain, 
        string calldata targetAddress
    ) external nonReentrant returns (bytes32 lockId) {
        require(asset != address(0), "Invalid asset");
        require(amount > 0, "Amount must be > 0");
        require(bytes(targetChain).length > 0, "Target chain required");
        require(bytes(targetAddress).length > 0, "Target address required");
        
        lockId = keccak256(abi.encodePacked(
            msg.sender, 
            asset, 
            amount, 
            targetChain, 
            targetAddress, 
            block.timestamp,
            block.number
        ));
        
        require(locks[lockId].user == address(0), "Lock already exists");
        
        locks[lockId] = LockInfo({
            user: msg.sender,
            asset: asset,
            amount: amount,
            targetChain: targetChain,
            targetAddress: targetAddress,
            timestamp: block.timestamp,
            released: false
        });
        
        totalLocked[asset] += amount;
        require(IERC20(asset).transferFrom(msg.sender, address(this), amount), "Transfer failed");
        emit Locked(lockId, msg.sender, asset, amount, targetChain, targetAddress);
    }
    
    /// @notice Accept a proof of cross-chain completion - ANY ORACLE CAN CALL
    function acceptProof(bytes32 proofHash) external onlyOracle {
        require(!processedProofs[proofHash], "Already processed");
        
        if (proofTimestamps[proofHash] == 0) {
            proofTimestamps[proofHash] = block.timestamp;
        }
        
        require(block.timestamp <= proofTimestamps[proofHash] + PROOF_EXPIRY, "Proof expired");
        processedProofs[proofHash] = true;
        emit ProofAccepted(proofHash, block.timestamp);
    }
    
    /// @notice Release locked tokens after proof verification - ANY ORACLE CAN CALL
    function release(bytes32 lockId, bytes32 proofHash) external nonReentrant onlyOracle {
        LockInfo storage lockInfo = locks[lockId];
        
        require(lockInfo.user != address(0), "Lock does not exist");
        require(!lockInfo.released, "Already released");
        require(processedProofs[proofHash], "Proof not accepted");
        require(block.timestamp <= proofTimestamps[proofHash] + PROOF_EXPIRY, "Proof expired");
        
        lockInfo.released = true;
        totalLocked[lockInfo.asset] -= lockInfo.amount;
        require(IERC20(lockInfo.asset).transfer(lockInfo.user, lockInfo.amount), "Release failed");
        emit Released(lockId, lockInfo.user, lockInfo.asset, lockInfo.amount);
    }
    
    /// @notice Burn wrapped assets after proof verification - ANY ORACLE CAN CALL
    function burnWrappedAsset(address asset, uint256 amount, bytes32 proofHash) external onlyOracle nonReentrant {
        require(!burnedProofs[proofHash], "Asset already burned for this proof");
        require(processedProofs[proofHash], "Proof not yet accepted");
        require(block.timestamp <= proofTimestamps[proofHash] + PROOF_EXPIRY, "Proof expired");
        require(amount <= totalLocked[asset], "Insufficient locked amount");
        
        burnedProofs[proofHash] = true;
        totalBurned[asset] += amount;
        totalLocked[asset] -= amount;
        require(IERC20(asset).transfer(address(0xdead), amount), "Burn transfer failed");
        emit WrappedAssetBurned(asset, amount, proofHash, msg.sender);
    }
    
    // ============ View Functions ============
    
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
    
    function isBurned(bytes32 proofHash) external view returns (bool) {
        return burnedProofs[proofHash];
    }
    
    function getTotalBurned(address asset) external view returns (uint256) {
        return totalBurned[asset];
    }
    
    function getLockInfo(bytes32 lockId) external view returns (LockInfo memory) {
        return locks[lockId];
    }
    
    function getContractBalance(address asset) external view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }
    
    function getOracles() external view returns (address[] memory) {
        return oracles;
    }
    
    // ============ NO ADMIN FUNCTIONS ============
    // No setOracle - oracles are immutable
    // No emergencyWithdraw - if tokens get stuck, they stay stuck
    // No owner - no one can change anything
}
