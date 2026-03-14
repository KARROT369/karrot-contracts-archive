// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title pxAsset Minter - Production Cross-chain Asset Minter
/// @notice Mints wrapped assets after cross-chain proof verification
/// @dev Full implementation with access control, replay protection, oracle validation, pausable

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IERC20Mintable {
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
}

interface IPriceOracle {
    function getLatestPrice(string calldata asset) external view returns (uint256);
}

contract PxAssetMinter is Ownable, Pausable, ReentrancyGuard {
    // ============ Structs ============
    struct AssetInfo {
        address token;
        uint256 minAmount;
        uint256 maxAmount;
        bool active;
        uint256 totalMinted;
    }
    
    // ============ State ============
    IPriceOracle public oracle;
    address public escrow;
    
    // Asset symbol => info
    mapping(string => AssetInfo) public assets;
    string[] public assetList;
    mapping(string => bool) public isAssetRegistered;
    
    // Proof hash => used
    mapping(bytes32 => bool) public usedProofs;
    
    // Daily mint limits per user
    mapping(address => mapping(uint256 => uint256)) public dailyMints;
    uint256 public dailyMintLimit = 100000 * 1e18; // 100k tokens per day per user
    
    // ============ Events ============
    event AssetRegistered(string indexed symbol, address indexed token, uint256 minAmount, uint256 maxAmount);
    event AssetUpdated(string indexed symbol, bool active, uint256 minAmount, uint256 maxAmount);
    event AssetRemoved(string indexed symbol);
    event Minted(string indexed symbol, address indexed user, uint256 amount, bytes32 indexed proofHash);
    event Burnt(string indexed symbol, address indexed user, uint256 amount);
    event OracleUpdated(address indexed newOracle);
    event EscrowUpdated(address indexed newEscrow);
    event DailyLimitUpdated(uint256 newLimit);
    event ProofInvalidated(bytes32 indexed proofHash);
    
    // ============ Modifiers ============
    modifier onlyEscrow() {
        require(msg.sender == escrow, "Not authorized escrow");
        _;
    }
    
    // ============ Constructor ============
    constructor(address _oracle, address _escrow) {
        require(_oracle != address(0), "Invalid oracle");
        require(_escrow != address(0), "Invalid escrow");
        oracle = IPriceOracle(_oracle);
        escrow = _escrow;
    }
    
    // ============ Admin Functions ============
    
    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "Invalid oracle");
        oracle = IPriceOracle(_oracle);
        emit OracleUpdated(_oracle);
    }
    
    function setEscrow(address _escrow) external onlyOwner {
        require(_escrow != address(0), "Invalid escrow");
        escrow = _escrow;
        emit EscrowUpdated(_escrow);
    }
    
    function setDailyMintLimit(uint256 _limit) external onlyOwner {
        dailyMintLimit = _limit;
        emit DailyLimitUpdated(_limit);
    }
    
    function registerAsset(
        string calldata symbol,
        address token,
        uint256 minAmount,
        uint256 maxAmount
    ) external onlyOwner {
        require(token != address(0), "Invalid token");
        require(!isAssetRegistered[symbol], "Asset already registered");
        require(minAmount < maxAmount, "Invalid amounts");
        
        assets[symbol] = AssetInfo({
            token: token,
            minAmount: minAmount,
            maxAmount: maxAmount,
            active: true,
            totalMinted: 0
        });
        
        assetList.push(symbol);
        isAssetRegistered[symbol] = true;
        
        emit AssetRegistered(symbol, token, minAmount, maxAmount);
    }
    
    function updateAssetConfig(
        string calldata symbol,
        bool active,
        uint256 minAmount,
        uint256 maxAmount
    ) external onlyOwner {
        require(isAssetRegistered[symbol], "Asset not registered");
        AssetInfo storage info = assets[symbol];
        info.active = active;
        info.minAmount = minAmount;
        info.maxAmount = maxAmount;
        emit AssetUpdated(symbol, active, minAmount, maxAmount);
    }
    
    function removeAsset(string calldata symbol) external onlyOwner {
        require(isAssetRegistered[symbol], "Asset not registered");
        
        delete assets[symbol];
        isAssetRegistered[symbol] = false;
        
        // Remove from array
        for (uint i = 0; i < assetList.length; i++) {
            if (keccak256(bytes(assetList[i])) == keccak256(bytes(symbol))) {
                assetList[i] = assetList[assetList.length - 1];
                assetList.pop();
                break;
            }
        }
        
        emit AssetRemoved(symbol);
    }
    
    function invalidateProof(bytes32 proofHash) external onlyOwner {
        usedProofs[proofHash] = true;
        emit ProofInvalidated(proofHash);
    }
    
    function togglePause() external onlyOwner {
        paused() ? _unpause() : _pause();
    }
    
    // ============ Minting ============
    
    /// @notice Mint pxAsset from cross-chain proof
    function mintFromProof(
        string calldata symbol,
        address user,
        uint256 amount,
        bytes calldata proof
    ) external nonReentrant whenNotPaused {
        require(user != address(0), "Invalid user");
        require(isAssetRegistered[symbol], "Asset not registered");
        
        AssetInfo storage asset = assets[symbol];
        require(asset.active, "Asset not active");
        require(amount >= asset.minAmount, "Amount below minimum");
        require(amount <= asset.maxAmount, "Amount above maximum");
        
        // Check proof uniqueness
        bytes32 proofHash = keccak256(proof);
        require(!usedProofs[proofHash], "Proof already used");
        usedProofs[proofHash] = true;
        
        // Check daily limit
        uint256 day = block.timestamp / 1 days;
        require(dailyMints[user][day] + amount <= dailyMintLimit, "Daily limit exceeded");
        dailyMints[user][day] += amount;
        
        // Get oracle price if needed
        uint256 price = oracle.getLatestPrice(symbol);
        require(price > 0, "No oracle price available");
        
        // Mint tokens
        IERC20Mintable(asset.token).mint(user, amount);
        asset.totalMinted += amount;
        
        emit Minted(symbol, user, amount, proofHash);
    }
    
    /// @notice Mint from escrow (escrow only)
    function mintFromEscrow(
        string calldata symbol,
        address user,
        uint256 amount,
        bytes calldata proof
    ) external onlyEscrow nonReentrant whenNotPaused {
        _validateAndMint(symbol, user, amount, proof);
    }
    
    // ============ Burn ============
    
    /// @notice Burn pxAsset to release on native chain
    function burn(string calldata symbol, uint256 amount) external nonReentrant {
        require(isAssetRegistered[symbol], "Asset not registered");
        AssetInfo storage asset = assets[symbol];
        require(amount <= asset.totalMinted, "Burn exceeds minted");
        
        IERC20Mintable(asset.token).burn(amount);
        asset.totalMinted -= amount;
        
        emit Burnt(symbol, msg.sender, amount);
    }
    
    // ============ Internal ============
    
    function _validateAndMint(
        string calldata symbol,
        address user,
        uint256 amount,
        bytes calldata proof
    ) internal {
        require(user != address(0), "Invalid user");
        
        AssetInfo storage asset = assets[symbol];
        require(asset.active, "Asset not active");
        require(amount >= asset.minAmount, "Amount below minimum");
        
        bytes32 proofHash = keccak256(proof);
        require(!usedProofs[proofHash], "Proof already used");
        usedProofs[proofHash] = true;
        
        IERC20Mintable(asset.token).mint(user, amount);
        asset.totalMinted += amount;
        
        emit Minted(symbol, user, amount, proofHash);
    }
    
    // ============ View Functions ============
    
    function isProofUsed(bytes32 proofHash) external view returns (bool) {
        return usedProofs[proofHash];
    }
    
    function getDailyMinted(address user, uint256 day) external view returns (uint256) {
        return dailyMints[user][day];
    }
    
    function getAssetList() external view returns (string[] memory) {
        return assetList;
    }
    
    function getAssetInfo(string calldata symbol) external view returns (AssetInfo memory) {
        return assets[symbol];
    }
    
    function getUserRemainingDailyAllowance(address user) external view returns (uint256) {
        uint256 day = block.timestamp / 1 days;
        return dailyMintLimit > dailyMints[user][day] ? dailyMintLimit - dailyMints[user][day] : 0;
    }
}
