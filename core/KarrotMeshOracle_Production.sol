// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Karrot Mesh Oracle - Production Secure Price Oracle
/// @notice Optimized oracle with quorum consensus, staleness checks, and governance
/// @dev Uses QuickSelect for O(n) median calculation

import "@openzeppelin/contracts/access/Ownable.sol";

contract KarrotMeshOracle is Ownable {
    // ============ Structs ============
    struct Report {
        uint256 value;
        uint256 timestamp;
        uint256 blockNumber;
    }
    
    struct AssetConfig {
        uint256 quorum;
        uint256 reportExpiry;
        uint256 minDeviation; // Minimum % change to trigger update (basis points)
        uint256 lastUpdate;
        uint256 latestConsensusPrice;
        bool active;
    }
    
    // ============ State ============
    mapping(string => mapping(address => Report)) public submittedReports;
    mapping(string => AssetConfig) public assetConfigs;
    mapping(string => address[]) public authorizedOracles;
    mapping(string => mapping(address => bool)) public isOracleAuthorized;
    mapping(string => mapping(address => uint256)) public oracleIndex; // For O(1) removal
    string[] public trackedAssets;
    mapping(string => bool) public isAssetTracked;
    
    uint256 public constant MAX_REPORT_EXPIRY = 7 days;
    uint256 public constant MIN_QUORUM = 1;
    uint256 public constant MAX_QUORUM = 100;
    
    // ============ Events ============
    event OracleAuthorized(string indexed asset, address indexed oracle);
    event OracleDeauthorized(string indexed asset, address indexed oracle);
    event ReportSubmitted(string indexed asset, address indexed oracle, uint256 value, uint256 roundId);
    event ConsensusPriceUpdated(string indexed asset, uint256 oldPrice, uint256 newPrice, uint256 timestamp);
    report ExpiredReportDiscarded(string indexed asset, address indexed oracle, uint256 timestamp);
    event AssetConfigUpdated(string indexed asset, uint256 quorum, uint256 expiry, bool active);
    event OldReportsCleaned(string indexed asset, uint256 cleanedCount);
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
    
    // ============ Constructor ============
    constructor() {}
    
    // ============ Admin Functions ============
    
    /// @notice Configure an asset for price reporting
    function setAssetConfig(
        string calldata asset,
        uint256 quorum,
        uint256 reportExpiry,
        uint256 minDeviation
    ) external onlyOwner {
        require(quorum >= MIN_QUORUM && quorum <= MAX_QUORUM, "Quorum out of range");
        require(reportExpiry > 0 && reportExpiry <= MAX_REPORT_EXPIRY, "Expiry out of range");
        require(minDeviation <= 10000, "Deviation must be <= 10000 (100%)");
        
        assetConfigs[asset] = AssetConfig({
            quorum: quorum,
            reportExpiry: reportExpiry,
            minDeviation: minDeviation,
            lastUpdate: assetConfigs[asset].lastUpdate,
            latestConsensusPrice: assetConfigs[asset].latestConsensusPrice,
            active: true
        });
        
        // Track asset
        if (!isAssetTracked[asset]) {
            trackedAssets.push(asset);
            isAssetTracked[asset] = true;
        }
        
        emit AssetConfigUpdated(asset, quorum, reportExpiry, true);
    }
    
    /// @notice Deactivate an asset
    function deactivateAsset(string calldata asset) external onlyOwner {
        require(assetConfigs[asset].active, "Asset not active");
        assetConfigs[asset].active = false;
        emit AssetConfigUpdated(asset, assetConfigs[asset].quorum, assetConfigs[asset].reportExpiry, false);
    }
    
    /// @notice Authorize an oracle for a specific asset
    function authorizeOracle(string calldata asset, address oracle) external onlyOwner {
        require(oracle != address(0), "Invalid oracle address");
        require(!isOracleAuthorized[asset][oracle], "Already authorized");
        
        authorizedOracles[asset].push(oracle);
        oracleIndex[asset][oracle] = authorizedOracles[asset].length;
        isOracleAuthorized[asset][oracle] = true;
        
        emit OracleAuthorized(asset, oracle);
    }
    
    /// @notice Deauthorize an oracle for a specific asset
    function deauthorizeOracle(string calldata asset, address oracle) external onlyOwner {
        require(isOracleAuthorized[asset][oracle], "Not authorized");
        
        // Swap and remove for O(1) deletion
        uint256 index = oracleIndex[asset][oracle];
        address[] storage oracles = authorizedOracles[asset];
        
        if (index < oracles.length) {
            address lastOracle = oracles[oracles.length - 1];
            oracles[index - 1] = lastOracle;
            oracleIndex[asset][lastOracle] = index;
        }
        oracles.pop();
        
        isOracleAuthorized[asset][oracle] = false;
        oracleIndex[asset][oracle] = 0;
        
        emit OracleDeauthorized(asset, oracle);
    }
    
    // ============ Reporting Functions ============
    
    /// @notice Submit a price report for an asset
    function submitPrice(string calldata asset, uint256 value) external onlyOracleFor(asset) validAsset(asset) {
        require(value > 0, "Price must be > 0");
        
        AssetConfig storage config = assetConfigs[asset];
        
        // Check if previous report expired
        Report storage existing = submittedReports[asset][msg.sender];
        if (existing.timestamp > 0 && block.timestamp > existing.timestamp + config.reportExpiry) {
            emit ExpiredReportDiscarded(asset, msg.sender, existing.timestamp);
        }
        
        // Store new report
        submittedReports[asset][msg.sender] = Report({
            value: value,
            timestamp: block.timestamp,
            blockNumber: block.number
        });
        
        emit ReportSubmitted(asset, msg.sender, value, block.number);
        
        // Check for consensus update
        _updateConsensus(asset);
    }
    
    // ============ Internal Functions ============
    
    function _updateConsensus(string memory asset) internal {
        AssetConfig storage config = assetConfigs[asset];
        address[] storage oracles = authorizedOracles[asset];
        
        // Collect valid (non-expired) reports
        uint256[] memory validValues = new uint256[](oracles.length);
        uint256 validCount = 0;
        
        for (uint256 i = 0; i < oracles.length; i++) {
            Report memory report = submittedReports[asset][oracles[i]];
            if (report.timestamp > 0 && block.timestamp - report.timestamp <= config.reportExpiry) {
                validValues[validCount] = report.value;
                validCount++;
            }
        }
        
        // Require quorum
        if (validCount < config.quorum) return;
        
        // Calculate median
        uint256 newPrice = _quickSelectMedian(validValues, validCount);
        
        // Check if deviation threshold met (if set)
        uint256 oldPrice = config.latestConsensusPrice;
        if (config.minDeviation > 0 && oldPrice > 0) {
            uint256 deviation = oldPrice > newPrice ? 
                ((oldPrice - newPrice) * 10000) / oldPrice : 
                ((newPrice - oldPrice) * 10000) / oldPrice;
            if (deviation < config.minDeviation) return;
        }
        
        // Update consensus
        config.latestConsensusPrice = newPrice;
        config.lastUpdate = block.timestamp;
        
        emit ConsensusPriceUpdated(asset, oldPrice, newPrice, block.timestamp);
    }
    
    /// @notice QuickSelect algorithm for O(n) median calculation
    function _quickSelectMedian(uint256[] memory arr, uint256 len) internal pure returns (uint256) {
        if (len == 0) return 0;
        if (len == 1) return arr[0];
        
        uint256 medianIndex = len / 2;
        return _quickSelect(arr, 0, len - 1, medianIndex);
    }
    
    function _quickSelect(uint256[] memory arr, uint256 left, uint256 right, uint256 k) internal pure returns (uint256) {
        if (left == right) return arr[left];
        
        uint256 pivotIndex = _partition(arr, left, right);
        
        if (k == pivotIndex) {
            return arr[k];
        } else if (k < pivotIndex) {
            return _quickSelect(arr, left, pivotIndex - 1, k);
        } else {
            return _quickSelect(arr, pivotIndex + 1, right, k);
        }
    }
    
    function _partition(uint256[] memory arr, uint256 left, uint256 right) internal pure returns (uint256) {
        uint256 pivot = arr[right];
        uint256 i = left;
        
        for (uint256 j = left; j < right; j++) {
            if (arr[j] <= pivot) {
                (arr[i], arr[j]) = (arr[j], arr[i]);
                i++;
            }
        }
        
        (arr[i], arr[right]) = (arr[right], arr[i]);
        return i;
    }
    
    // ============ Cleanup Functions ============
    
    /// @notice Clean expired reports for a specific asset
    function cleanExpiredReports(string calldata asset) external {
        address[] storage oracles = authorizedOracles[asset];
        AssetConfig storage config = assetConfigs[asset];
        uint256 cleaned = 0;
        
        for (uint256 i = 0; i < oracles.length; i++) {
            Report storage report = submittedReports[asset][oracles[i]];
            if (report.timestamp > 0 && block.timestamp > report.timestamp + config.reportExpiry * 2) {
                delete submittedReports[asset][oracles[i]];
                cleaned++;
            }
        }
        
        if (cleaned > 0) {
            emit OldReportsCleaned(asset, cleaned);
        }
    }
    
    /// @notice Check if price is stale (no update within expiry period)
    function isPriceStale(string calldata asset) external view returns (bool) {
        AssetConfig storage config = assetConfigs[asset];
        if (config.latestConsensusPrice == 0) return true;
        return block.timestamp > config.lastUpdate + config.reportExpiry;
    }
    
    // ============ View Functions ============
    
    function getLatestPrice(string calldata asset) external view returns (uint256) {
        return assetConfigs[asset].latestConsensusPrice;
    }
    
    function getOraclesForAsset(string calldata asset) external view returns (address[] memory) {
        return authorizedOracles[asset];
    }
    
    function getReport(string calldata asset, address oracle) external view returns (Report memory) {
        return submittedReports[asset][oracle];
    }
    
    function getTrackedAssets() external view returns (string[] memory) {
        return trackedAssets;
    }
    
    function getAssetConfig(string calldata asset) external view returns (AssetConfig memory) {
        return assetConfigs[asset];
    }
}
