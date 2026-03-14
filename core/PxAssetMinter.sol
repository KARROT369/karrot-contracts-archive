// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IERC20Mintable {
    function mint(address to, uint256 amount) external;
    function decimals() external view returns (uint8);
}

interface IKarrotMeshOracle {
    function getLatestPrice(string calldata asset) external view returns (uint256);
}

/// @title PxAssetMinter - IMMUTABLE VERSION
/// @notice Truly immutable cross-chain bridge minter
/// @dev No admin functions, no ownership, no pause. Parameters frozen at deployment.
/// @dev Relayers and merkle root are immutable after initialization.
contract PxAssetMinter is ReentrancyGuard {
    
    // ============ IMMUTABLE STATE ============
    /// @notice Authorized relayers who can mint (immutable after deployment)
    address[] public immutable authorizedRelayers;
    
    /// @notice Merkle root for proof verification (immutable after deployment)
    bytes32 public immutable merkleRoot;
    
    /// @notice Oracle for price checks (immutable)
    IKarrotMeshOracle public immutable oracle;
    
    /// @notice Maximum mint per transaction (immutable)
    uint256 public immutable maxMintPerTx;
    
    /// @notice Daily mint limit per asset (immutable)
    uint256 public immutable dailyMintLimit;
    
    /// @notice Deployment timestamp
    uint256 public immutable deployedAt;
    
    // ============ MUTABLE STATE ============
    // Used proof hashes to prevent replay (necessary mutability)
    mapping(bytes32 => bool) public usedProofs;
    
    // Daily mint tracking (necessary for limits)
    mapping(string => mapping(uint256 => uint256)) public dailyMints;
    
    // Registered assets (set in constructor, then immutable)
    mapping(string => IERC20Mintable) public pxAssets;
    mapping(string => bool) public isAssetRegistered;
    
    // ============ CONSTANTS ============
    uint256 public constant SECONDS_PER_DAY = 86400;
    
    // ============ EVENTS ============
    event PxAssetMinted(string indexed symbol, address indexed user, uint256 amount, bytes32 indexed proofHash);
    event AssetRegistered(string indexed symbol, address indexed pxAsset);
    
    // ============ MODIFIERS ============
    modifier onlyRelayer() {
        bool isAuthorized = false;
        for (uint i = 0; i < authorizedRelayers.length; i++) {
            if (authorizedRelayers[i] == msg.sender) {
                isAuthorized = true;
                break;
            }
        }
        require(isAuthorized, "Not authorized relayer");
        _;
    }
    
    modifier onlyRegistered(string calldata symbol) {
        require(isAssetRegistered[symbol], "Asset not registered");
        _;
    }
    
    // ============ CONSTRUCTOR - ALL IMMUTABLE STATE SET HERE ============
    /// @notice Deploy with all parameters locked forever
    /// @param _relayers Array of authorized relayer addresses (immutable)
    /// @param _merkleRoot Merkle root for proof verification (immutable)
    /// @param _oracle Address of price oracle (immutable)
    /// @param _maxMintPerTx Maximum mint per transaction (immutable)
    /// @param _dailyMintLimit Daily mint limit per asset (immutable)
    /// @param _symbols Array of asset symbols to register
    /// @param _pxAssets Array of pxAsset token addresses (must match _symbols length)
    constructor(
        address[] memory _relayers,
        bytes32 _merkleRoot,
        address _oracle,
        uint256 _maxMintPerTx,
        uint256 _dailyMintLimit,
        string[] memory _symbols,
        address[] memory _pxAssets
    ) {
        require(_relayers.length > 0, "No relayers");
        require(_merkleRoot != bytes32(0), "No merkle root");
        require(_oracle != address(0), "No oracle");
        require(_maxMintPerTx > 0, "Zero max mint");
        require(_dailyMintLimit > 0, "Zero daily limit");
        require(_symbols.length == _pxAssets.length, "Length mismatch");
        require(_symbols.length > 0, "No assets");
        
        // Set immutable state
        authorizedRelayers = _relayers;
        merkleRoot = _merkleRoot;
        oracle = IKarrotMeshOracle(_oracle);
        maxMintPerTx = _maxMintPerTx;
        dailyMintLimit = _dailyMintLimit;
        deployedAt = block.timestamp;
        
        // Register assets (becomes immutable after constructor)
        for (uint i = 0; i < _symbols.length; i++) {
            require(_pxAssets[i] != address(0), "Invalid asset");
            pxAssets[_symbols[i]] = IERC20Mintable(_pxAssets[i]);
            isAssetRegistered[_symbols[i]] = true;
            emit AssetRegistered(_symbols[i], _pxAssets[i]);
        }
    }
    
    // ============ CORE MINT FUNCTION - IMMUTABLE LOGIC ============
    /// @notice Mints pxAsset using verified cross-chain proof
    /// @param symbol Asset symbol (e.g., "pxSOL")
    /// @param user Receiver address
    /// @param amount Amount to mint
    /// @param proof Merkle proof of lock transaction
    /// @param leafIndex Index in merkle tree
    function mintFromLockProof(
        string calldata symbol,
        address user,
        uint256 amount,
        bytes32[] calldata proof,
        uint256 leafIndex
    ) external nonReentrant onlyRelayer onlyRegistered(symbol) {
        
        require(user != address(0), "Invalid user");
        require(amount > 0, "Zero amount");
        require(amount <= maxMintPerTx, "Exceeds max mint");
        
        IERC20Mintable pxToken = pxAssets[symbol];
        
        // Check daily mint limit
        uint256 day = block.timestamp / SECONDS_PER_DAY;
        uint256 newDailyMint = dailyMints[symbol][day] + amount;
        require(newDailyMint <= dailyMintLimit, "Exceeds daily limit");
        dailyMints[symbol][day] = newDailyMint;
        
        // Generate proof hash (leaf)
        bytes32 leaf = keccak256(abi.encode(symbol, user, amount, leafIndex));
        require(!usedProofs[leaf], "Proof already used");
        
        // Verify merkle proof
        require(verifyMerkleProof(proof, merkleRoot, leaf, leafIndex), "Invalid proof");
        
        // Verify oracle price exists (extra validation)
        uint256 price = oracle.getLatestPrice(symbol);
        require(price > 0, "No oracle price");
        
        // Mark proof as used BEFORE minting (checks-effects-interactions)
        usedProofs[leaf] = true;
        
        // Mint tokens
        pxToken.mint(user, amount);
        
        emit PxAssetMinted(symbol, user, amount, leaf);
    }
    
    // ============ PURE FUNCTIONS - NO STATE CHANGE ============
    /// @notice Verify a merkle proof (pure, no gas cost for view)
    function verifyMerkleProof(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf,
        uint256 index
    ) public pure returns (bool) {
        bytes32 computedHash = leaf;
        
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            
            if (index % 2 == 0) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
            
            index = index / 2;
        }
        
        return computedHash == root;
    }
    
    /// @notice Check if relayer is authorized (view)
    function isRelayerAuthorized(address relayer) external view returns (bool) {
        for (uint i = 0; i < authorizedRelayers.length; i++) {
            if (authorizedRelayers[i] == relayer) return true;
        }
        return false;
    }
    
    /// @notice Get all authorized relayers (view)
    function getRelayers() external view returns (address[] memory) {
        return authorizedRelayers;
    }
    
    /// @notice Check if proof was used (view)
    function isProofUsed(bytes32 proofHash) external view returns (bool) {
        return usedProofs[proofHash];
    }
    
    /// @notice Get remaining daily allowance (view)
    function getRemainingDailyAllowance(string calldata symbol) external view returns (uint256) {
        uint256 day = block.timestamp / SECONDS_PER_DAY;
        uint256 used = dailyMints[symbol][day];
        return used >= dailyMintLimit ? 0 : dailyMintLimit - used;
    }
    
    /// @notice Get contract info (view)
    function getContractInfo() external view returns (
        bytes32 _merkleRoot,
        address _oracle,
        uint256 _maxMintPerTx,
        uint256 _dailyMintLimit,
        uint256 _deployedAt,
        uint256 _relayerCount
    ) {
        return (merkleRoot, address(oracle), maxMintPerTx, dailyMintLimit, deployedAt, authorizedRelayers.length);
    }
}
