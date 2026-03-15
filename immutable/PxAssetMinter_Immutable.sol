// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title PxAsset Minter - IMMUTABLE VERSION
/// @notice Mints wrapped assets after cross-chain proof - NO ADMIN, NO PAUSE
/// @dev All relayers, assets, and limits set at deployment. Cannot be changed.

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IERC20Mintable {
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
}

interface IPriceOracle {
    function getLatestPrice(string calldata asset) external view returns (uint256);
}

contract PxAssetMinter_Immutable is ReentrancyGuard {
    // ============ Structs ============
    struct AssetInfo {
        address token;
        uint256 minAmount;
        uint256 maxAmount;
        bool active;
        uint256 totalMinted;
    }
    
    // ============ Immutable State ============
    IPriceOracle public immutable oracle;
    address public immutable escrow;
    
    mapping(string => AssetInfo) public assets;
    string[] public assetList;
    mapping(string => bool) public isAssetRegistered;
    
    mapping(bytes32 => bool) public usedProofs;
    mapping(address => mapping(uint256 => uint256)) public dailyMints;
    
    uint256 public immutable dailyMintLimit;
    uint256 public immutable maxMintPerTx;
    bytes32 public immutable merkleRoot;
    
    // Relayers - set in constructor, never changeable
    mapping(address => bool) public isRelayer;
    address[] public relayers;
    
    // ============ Events ============
    event Minted(string indexed symbol, address indexed user, uint256 amount, bytes32 indexed proofHash);
    event Burnt(string indexed symbol, address indexed user, uint256 amount);
    event DailyLimitUpdated(uint256 newLimit);
    event ProofInvalidated(bytes32 indexed proofHash);
    
    // ============ Modifiers ============
    modifier onlyRelayer() {
        require(isRelayer[msg.sender], "Not authorized relayer");
        _;
    }
    
    // ============ Constructor - EVERYTHING SET HERE ============
    constructor(
        address[] memory _relayers,
        bytes32 _merkleRoot,
        address _oracle,
        uint256 _maxMintPerTx,
        uint256 _dailyMintLimit,
        string[] memory _assetSymbols,
        address[] memory _assetTokens
    ) {
        require(_relayers.length > 0, "Need at least one relayer");
        require(_oracle != address(0), "Invalid oracle");
        require(_maxMintPerTx > 0, "Max mint must be > 0");
        require(_dailyMintLimit >= _maxMintPerTx, "Daily limit must be >= max per tx");
        require(_assetSymbols.length == _assetTokens.length, "Asset arrays mismatch");
        require(_assetSymbols.length > 0, "Need at least one asset");
        
        oracle = IPriceOracle(_oracle);
        escrow = msg.sender; // Deployer is escrow
        maxMintPerTx = _maxMintPerTx;
        dailyMintLimit = _dailyMintLimit;
        merkleRoot = _merkleRoot;
        
        // Set relayers
        for (uint i = 0; i < _relayers.length; i++) {
            require(_relayers[i] != address(0), "Invalid relayer");
            require(!isRelayer[_relayers[i]], "Duplicate relayer");
            isRelayer[_relayers[i]] = true;
            relayers.push(_relayers[i]);
        }
        
        // Register assets
        for (uint i = 0; i < _assetSymbols.length; i++) {
            require(_assetTokens[i] != address(0), "Invalid token");
            require(!isAssetRegistered[_assetSymbols[i]], "Duplicate asset");
            
            assets[_assetSymbols[i]] = AssetInfo({
                token: _assetTokens[i],
                minAmount: 1e9, // Default 1 token with 9 decimals
                maxAmount: _maxMintPerTx,
                active: true,
                totalMinted: 0
            });
            
            isAssetRegistered[_assetSymbols[i]] = true;
            assetList.push(_assetSymbols[i]);
        }
    }
    
    // ============ Core Functions ============
    
    /// @notice Mint wrapped asset after cross-chain proof - ANY RELAYER CAN CALL
    function mint(
        string calldata symbol,
        address user,
        uint256 amount,
        bytes32 proofHash
    ) external onlyRelayer nonReentrant {
        require(!usedProofs[proofHash], "Proof already used");
        require(isAssetRegistered[symbol], "Asset not registered");
        
        AssetInfo storage asset = assets[symbol];
        require(asset.active, "Asset not active");
        require(amount >= asset.minAmount, "Amount below minimum");
        require(amount <= asset.maxAmount, "Amount above maximum");
        require(amount <= maxMintPerTx, "Amount above max per tx");
        
        // Check daily limit
        uint256 today = block.timestamp / 1 days;
        require(dailyMints[user][today] + amount <= dailyMintLimit, "Daily limit exceeded");
        
        // Mark proof as used
        usedProofs[proofHash] = true;
        dailyMints[user][today] += amount;
        asset.totalMinted += amount;
        
        // Mint tokens
        IERC20Mintable(asset.token).mint(user, amount);
        
        emit Minted(symbol, user, amount, proofHash);
    }
    
    /// @notice Burn wrapped asset to unlock on other chain
    function burn(string calldata symbol, uint256 amount) external nonReentrant {
        require(isAssetRegistered[symbol], "Asset not registered");
        require(amount > 0, "Amount must be > 0");
        
        AssetInfo storage asset = assets[symbol];
        require(asset.active, "Asset not active");
        
        IERC20Mintable(asset.token).burn(amount);
        emit Burnt(symbol, msg.sender, amount);
    }
    
    // ============ View Functions ============
    
    function getAssetInfo(string calldata symbol) external view returns (AssetInfo memory) {
        return assets[symbol];
    }
    
    function getDailyMint(address user) external view returns (uint256) {
        uint256 today = block.timestamp / 1 days;
        return dailyMints[user][today];
    }
    
    function getRelayers() external view returns (address[] memory) {
        return relayers;
    }
    
    function isProofUsed(bytes32 proofHash) external view returns (bool) {
        return usedProofs[proofHash];
    }
    
    // ============ NO ADMIN FUNCTIONS ============
    // No registerAsset - assets are immutable
    // No setDailyMintLimit - limit is immutable
    // No setOracle - oracle is immutable
    // No setEscrow - escrow is immutable
    // No owner - no one can change anything
}
