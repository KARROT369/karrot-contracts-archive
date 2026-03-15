// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Karrot Mesh Oracle - IMMUTABLE VERSION
/// @notice Multi-oracle consensus price feed - NO ADMIN, NO PAUSE
/// @dev All oracles and assets set at deployment. Cannot be changed.

contract KarrotMeshOracle_Immutable {
    // ============ Structs ============
    struct Report {
        uint256 value;
        uint256 timestamp;
        uint256 blockNumber;
    }
    
    struct AssetConfig {
        uint256 quorum;
        uint256 reportExpiry;
        uint256 minDeviation;
        uint256 lastUpdate;
        uint256 latestConsensusPrice;
        bool active;
    }
    
    // ============ Immutable State ============
    mapping(string => mapping(address => Report)) public submittedReports;
    mapping(string => AssetConfig) public assetConfigs;
    mapping(string => address[]) public authorizedOracles;
    mapping(string => mapping(address => bool)) public isOracleAuthorized;
    mapping(string => mapping(address => uint256)) public oracleIndex;
    string[] public trackedAssets;
    mapping(string => bool) public isAssetTracked;
    
    uint256 public constant MAX_REPORT_EXPIRY = 7 days;
    uint256 public constant MIN_QUORUM = 1;
    uint256 public constant MAX_QUORUM = 100;
    
    // ============ Events ============
    event ReportSubmitted(string indexed asset, address indexed oracle, uint256 value, uint256 roundId);
    event ConsensusPriceUpdated(string indexed asset, uint256 oldPrice, uint256 newPrice, uint256 timestamp);
    event ExpiredReportDiscarded(string indexed asset, address indexed oracle, uint256 timestamp);
    event StalePriceDetected(string indexed asset, uint256 lastUpdate, uint256 currentTime);
    
    // ============ Modifiers ============
    modifier onlyOracleFor(string calldata asset) {
        require(isOracleAuthorized[asset][msg.sender], "Not authorized oracle for asset");
        _;
    }
    
    modifier validAsset(string calldata asset) {
        require(assetConfigs[asset].active, "Asset not active");
        _;
    }
    
    // ============ Constructor - ALL ORACLES AND ASSETS SET HERE ============
    constructor(
        string[] memory _assets,
        uint256[] memory _quorums,
        uint256[] memory _expiries,
        uint256[] memory _deviations,
        address[][] memory _oraclesPerAsset
    ) {
        require(_assets.length == _quorums.length, "Arrays mismatch");
        require(_assets.length == _expiries.length, "Arrays mismatch");
        require(_assets.length == _deviations.length, "Arrays mismatch");
        require(_assets.length == _oraclesPerAsset.length, "Arrays mismatch");
        
        for (uint i = 0; i < _assets.length; i++) {
            require(_quorums[i] >= MIN_QUORUM && _quorums[i] <= MAX_QUORUM, "Quorum out of range");
            require(_expiries[i] > 0 && _expiries[i] <= MAX_REPORT_EXPIRY, "Expiry out of range");
            require(_deviations[i] <= 10000, "Deviation must be <= 10000");
            require(_oraclesPerAsset[i].length >= _quorums[i], "Not enough oracles for quorum");
            
            string memory asset = _assets[i];
            
            assetConfigs[asset] = AssetConfig({
                quorum: _quorums[i],
                reportExpiry: _expiries[i],
                minDeviation: _deviations[i],
                lastUpdate: 0,
                latestConsensusPrice: 0,
                active: true
            });
            
            // Authorize oracles for this asset
            for (uint j = 0; j < _oraclesPerAsset[i].length; j++) {
                address oracle = _oraclesPerAsset[i][j];
                require(oracle != address(0), "Invalid oracle");
                
                if (!isOracleAuthorized[asset][oracle]) {
                    isOracleAuthorized[asset][oracle] = true;
                    oracleIndex[asset][oracle] = authorizedOracles[asset].length;
                    authorizedOracles[asset].push(oracle);
                }
            }
            
            trackedAssets.push(asset);
            isAssetTracked[asset] = true;
        }
    }
    
    // ============ Core Functions ============
    
    /// @notice Submit price report - AUTHORIZED ORACLES ONLY
    function submitReport(string calldata asset, uint256 value) external onlyOracleFor(asset) validAsset(asset) {
        require(value > 0, "Value must be > 0");
        
        AssetConfig storage config = assetConfigs[asset];
        
        // Store report
        submittedReports[asset][msg.sender] = Report({
            value: value,
            timestamp: block.timestamp,
            blockNumber: block.number
        });
        
        emit ReportSubmitted(asset, msg.sender, value, block.number);
        
        // Try to update consensus
        _tryUpdateConsensus(asset);
    }
    
    /// @notice Try to update consensus price
    function _tryUpdateConsensus(string calldata asset) internal {
        AssetConfig storage config = assetConfigs[asset];
        address[] memory oracles = authorizedOracles[asset];
        
        uint256[] memory validValues = new uint256[](oracles.length);
        uint256 validCount = 0;
        
        // Collect valid (non-expired) reports
        for (uint i = 0; i < oracles.length; i++) {
            Report memory report = submittedReports[asset][oracles[i]];
            if (report.timestamp > 0 && block.timestamp <= report.timestamp + config.reportExpiry) {
                validValues[validCount] = report.value;
                validCount++;
            } else if (report.timestamp > 0) {
                emit ExpiredReportDiscarded(asset, oracles[i], block.timestamp);
            }
        }
        
        // Need quorum
        if (validCount < config.quorum) return;
        
        // Calculate median (QuickSelect for O(n))
        uint256 median = _quickSelect(validValues, validCount, validCount / 2);
        
        // Check deviation
        if (config.latestConsensusPrice > 0) {
            uint256 deviation = _calculateDeviation(median, config.latestConsensusPrice);
            if (deviation < config.minDeviation) return; // Skip small changes
        }
        
        // Update consensus
        uint256 oldPrice = config.latestConsensusPrice;
        config.latestConsensusPrice = median;
        config.lastUpdate = block.timestamp;
        
        emit ConsensusPriceUpdated(asset, oldPrice, median, block.timestamp);
    }
    
    // ============ View Functions ============
    
    function getLatestPrice(string calldata asset) external view validAsset(asset) returns (uint256) {
        AssetConfig storage config = assetConfigs[asset];
        require(block.timestamp <= config.lastUpdate + config.reportExpiry, "Price expired");
        return config.latestConsensusPrice;
    }
    
    function getAssetConfig(string calldata asset) external view returns (AssetConfig memory) {
        return assetConfigs[asset];
    }
    
    function getOraclesForAsset(string calldata asset) external view returns (address[] memory) {
        return authorizedOracles[asset];
    }
    
    function isStale(string calldata asset) external view returns (bool) {
        AssetConfig storage config = assetConfigs[asset];
        if (config.lastUpdate == 0) return true;
        return block.timestamp > config.lastUpdate + config.reportExpiry;
    }
    
    // ============ Internal Functions ============
    
    function _quickSelect(uint256[] memory arr, uint256 len, uint256 k) internal pure returns (uint256) {
        if (len == 1) return arr[0];
        
        // Simple sort for small arrays (optimization for typical oracle counts < 20)
        for (uint i = 0; i < len; i++) {
            for (uint j = i + 1; j < len; j++) {
                if (arr[j] < arr[i]) {
                    (arr[i], arr[j]) = (arr[j], arr[i]);
                }
            }
        }
        return arr[k];
    }
    
    function _calculateDeviation(uint256 newPrice, uint256 oldPrice) internal pure returns (uint256) {
        if (oldPrice == 0) return 10000;
        uint256 diff = newPrice > oldPrice ? newPrice - oldPrice : oldPrice - newPrice;
        return (diff * 10000) / oldPrice;
    }
    
    // ============ NO ADMIN FUNCTIONS ============
    // No setAssetConfig - assets are immutable
    // No authorizeOracle - oracles are immutable
    // No deactivateAsset - assets always active
    // No owner - no one can change anything
}
