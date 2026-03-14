// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title Karrot Escrow - IMMUTABLE VERSION
/// @notice Truly immutable cross-chain escrow with no admin functions
/// @dev All parameters frozen at deployment, no ownership, no emergency controls
/// @dev Once deployed, contract behavior cannot change
contract KarrotEscrow is ReentrancyGuard {
    
    // ============ IMMUTABLE STATE ============
    /// @notice Authorized oracle addresses (immutable after deployment)
    address[] public immutable authorizedOracles;
    
    /// @notice Proof expiry time in seconds (immutable)
    uint256 public immutable proofExpiry;
    
    /// @notice Supported asset tokens (immutable)
    address[] public immutable supportedAssets;
    mapping(address => bool) public immutable isSupportedAsset;
    
    /// @notice Deployment timestamp
    uint256 public immutable deployedAt;
    
    // ============ MUTABLE STATE (Required for functionality) ============
    struct LockInfo {
        address user;
        address asset;
        uint256 amount;
        string targetChain;
        string targetAddress;
        uint256 timestamp;
        bool released;
        bytes32 releaseProof;
    }
    
    // Locks (necessary state)
    mapping(bytes32 => LockInfo) public locks;
    mapping(bytes32 => bool) public processedProofs;
    mapping(bytes32 => uint256) public proofTimestamps;
    
    // Totals
    mapping(address => uint256) public totalLocked;
    mapping(address => uint256) public totalReleased;
    
    // ============ CONSTANTS ============
    uint256 public constant MAX_TARGET_CHAIN_LENGTH = 32;
    uint256 public constant MAX_TARGET_ADDRESS_LENGTH = 64;
    
    // ============ EVENTS ============
    event Locked(
        bytes32 indexed lockId,
        address indexed user,
        address indexed asset,
        uint256 amount,
        string targetChain,
        string targetAddress
    );
    
    event Released(
        bytes32 indexed lockId,
        address indexed to,
        address indexed asset,
        uint256 amount,
        bytes32 proofHash
    );
    
    event ProofAccepted(bytes32 indexed proofHash, uint256 timestamp);
    
    event ProofExpired(bytes32 indexed proofHash, uint256 expiredAt);
    
    // ============ MODIFIERS ============
    modifier onlyOracle() {
        bool isAuthorized = false;
        for (uint i = 0; i < authorizedOracles.length; i++) {
            if (authorizedOracles[i] == msg.sender) {
                isAuthorized = true;
                break;
            }
        }
        require(isAuthorized, "Not authorized oracle");
        _;
    }
    
    modifier onlySupportedAsset(address asset) {
        require(isSupportedAsset[asset], "Asset not supported");
        _;
    }
    
    // ============ CONSTRUCTOR - ALL IMMUTABLE STATE SET HERE ============
    /// @notice Deploy escrow with all parameters locked forever
    /// @param _oracles Array of authorized oracle addresses (immutable)
    /// @param _proofExpiry Time in seconds for proof validity (immutable)
    /// @param _supportedAssets Array of supported token addresses (immutable)
    constructor(
        address[] memory _oracles,
        uint256 _proofExpiry,
        address[] memory _supportedAssets
    ) {
        require(_oracles.length > 0, "No oracles");
        require(_proofExpiry > 0, "Zero expiry");
        require(_supportedAssets.length > 0, "No supported assets");
        
        // Set immutable state
        authorizedOracles = _oracles;
        proofExpiry = _proofExpiry;
        deployedAt = block.timestamp;
        
        // Set supported assets (becomes immutable after constructor)
        for (uint i = 0; i < _supportedAssets.length; i++) {
            require(_supportedAssets[i] != address(0), "Invalid asset");
            supportedAssets.push(_supportedAssets[i]);
            isSupportedAsset[_supportedAssets[i]] = true;
        }
    }
    
    // ============ USER FUNCTIONS ============
    /// @notice Lock tokens for cross-chain transfer
    /// @param asset Token address to lock
    /// @param amount Amount to lock
    /// @param targetChain Destination chain (e.g., "solana")
    /// @param targetAddress Destination address on target chain
    function lock(
        address asset,
        uint256 amount,
        string calldata targetChain,
        string calldata targetAddress
    ) external nonReentrant onlySupportedAsset(asset) returns (bytes32 lockId) {
        
        require(amount > 0, "Zero amount");
        require(bytes(targetChain).length > 0 && bytes(targetChain).length <= MAX_TARGET_CHAIN_LENGTH, "Invalid chain");
        require(bytes(targetAddress).length > 0 && bytes(targetAddress).length <= MAX_TARGET_ADDRESS_LENGTH, "Invalid address");
        
        // Generate unique lock ID
        lockId = keccak256(abi.encodePacked(
            msg.sender,
            asset,
            amount,
            targetChain,
            targetAddress,
            block.timestamp,
            block.number,
            locks.length // Additional uniqueness
        ));
        
        require(locks[lockId].user == address(0), "Lock already exists");
        
        // Store lock info
        locks[lockId] = LockInfo({
            user: msg.sender,
            asset: asset,
            amount: amount,
            targetChain: targetChain,
            targetAddress: targetAddress,
            timestamp: block.timestamp,
            released: false,
            releaseProof: bytes32(0)
        });
        
        // Update totals
        totalLocked[asset] += amount;
        
        // Transfer tokens to escrow
        require(
            IERC20(asset).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        
        emit Locked(lockId, msg.sender, asset, amount, targetChain, targetAddress);
    }
    
    // ============ ORACLE FUNCTIONS ============
    /// @notice Accept a proof of cross-chain completion (oracle only)
    /// @param proofHash Hash of the proof from destination chain
    function acceptProof(bytes32 proofHash) external onlyOracle {
        require(!processedProofs[proofHash], "Already processed");
        
        // Record timestamp on first acceptance
        if (proofTimestamps[proofHash] == 0) {
            proofTimestamps[proofHash] = block.timestamp;
        }
        
        // Check expiry
        require(
            block.timestamp <= proofTimestamps[proofHash] + proofExpiry,
            "Proof expired"
        );
        
        processedProofs[proofHash] = true;
        
        emit ProofAccepted(proofHash, block.timestamp);
    }
    
    /// @notice Release locked tokens after proof verification (oracle only)
    /// @param lockId ID of the lock to release
    /// @param proofHash Proof hash that validates the release
    function release(
        bytes32 lockId,
        bytes32 proofHash
    ) external nonReentrant onlyOracle {
        LockInfo storage lockInfo = locks[lockId];
        
        require(lockInfo.user != address(0), "Lock not found");
        require(!lockInfo.released, "Already released");
        require(processedProofs[proofHash], "Proof not accepted");
        require(
            block.timestamp <= proofTimestamps[proofHash] + proofExpiry,
            "Proof expired"
        );
        
        // Update state before transfer
        lockInfo.released = true;
        lockInfo.releaseProof = proofHash;
        totalLocked[lockInfo.asset] -= lockInfo.amount;
        totalReleased[lockInfo.asset] += lockInfo.amount;
        
        // Transfer tokens back to user
        require(
            IERC20(lockInfo.asset).transfer(lockInfo.user, lockInfo.amount),
            "Release failed"
        );
        
        emit Released(lockId, lockInfo.user, lockInfo.asset, lockInfo.amount, proofHash);
    }
    
    // ============ VIEW FUNCTIONS ============
    /// @notice Get lock information
    function getLock(bytes32 lockId) external view returns (LockInfo memory) {
        return locks[lockId];
    }
    
    /// @notice Check if proof is processed and not expired
    function isProofValid(bytes32 proofHash) external view returns (bool) {
        if (!processedProofs[proofHash]) return false;
        if (proofTimestamps[proofHash] == 0) return false;
        return block.timestamp <= proofTimestamps[proofHash] + proofExpiry;
    }
    
    /// @notice Get remaining time for proof validity
    function getProofRemainingTime(bytes32 proofHash) external view returns (uint256) {
        if (!processedProofs[proofHash]) return 0;
        if (proofTimestamps[proofHash] == 0) return 0;
        
        uint256 expiryTime = proofTimestamps[proofHash] + proofExpiry;
        if (block.timestamp >= expiryTime) return 0;
        return expiryTime - block.timestamp;
    }
    
    /// @notice Check if address is authorized oracle
    function isOracle(address account) external view returns (bool) {
        for (uint i = 0; i < authorizedOracles.length; i++) {
            if (authorizedOracles[i] == account) return true;
        }
        return false;
    }
    
    /// @notice Get all authorized oracles
    function getOracles() external view returns (address[] memory) {
        return authorizedOracles;
    }
    
    /// @notice Get supported assets
    function getSupportedAssets() external view returns (address[] memory) {
        return supportedAssets;
    }
    
    /// @notice Get contract info
    function getContractInfo() external view returns (
        uint256 _proofExpiry,
        uint256 _deployedAt,
        uint256 _oracleCount,
        uint256 _assetCount
    ) {
        return (proofExpiry, deployedAt, authorizedOracles.length, supportedAssets.length);
    }
    
    /// @notice Get contract balance for an asset
    function getBalance(address asset) external view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}
