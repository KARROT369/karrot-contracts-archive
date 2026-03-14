// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Karrot Mesh Oracle V0 - Secure Price Oracle with Expiration and Cleanup
/// @notice Oracle with authorized reporters, report expiration, and storage cleanup
/// FIX: Renamed from KarrotMeshOracle to KarrotMeshOracleV0 for clarity

contract KarrotMeshOracle0 {
    struct PriceReport {
        uint256 value;
        uint256 timestamp;
    }

    address public owner;
    uint256 public quorum;
    uint256 public reportExpiry = 30 minutes;

    mapping(string => mapping(address => PriceReport)) public submittedPrices;
    mapping(string => address[]) public authorizedOracles;
    mapping(string => uint256) public latestConsensusPrice;
    
    // FIX: Added authorized oracle mapping for O(1) lookup
    mapping(string => mapping(address => bool)) public isOracleAuthorized;
    
    // FIX: Track asset list for cleanup operations
    string[] public trackedAssets;
    mapping(string => bool) public isAssetTracked;

    event OracleAuthorized(string asset, address oracle);
    event OracleDeauthorized(string asset, address oracle);
    event PriceSubmitted(string asset, address oracle, uint256 value);
    event ConsensusPriceUpdated(string asset, uint256 consensusPrice);
    event ReportExpired(string asset, address oracle, uint256 timestamp);
    event OldReportsRemoved(string asset, uint256 removedCount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(uint256 _quorum) {
        require(_quorum > 0, "Quorum must be > 0");
        owner = msg.sender;
        quorum = _quorum;
    }

    function setReportExpiry(uint256 expirySeconds) external onlyOwner {
        reportExpiry = expirySeconds;
    }

    function authorizeOracle(string memory asset, address oracle) external onlyOwner {
        require(!isOracleAuthorized[asset][oracle], "Already authorized");
        isOracleAuthorized[asset][oracle] = true;
        authorizedOracles[asset].push(oracle);
        
        // Track asset for cleanup
        if (!isAssetTracked[asset]) {
            trackedAssets.push(asset);
            isAssetTracked[asset] = true;
        }
        
        emit OracleAuthorized(asset, oracle);
    }

    function submitPrice(string calldata asset, uint256 value) external {
        // FIX: Only authorized oracles can submit
        require(isOracleAuthorized[asset][msg.sender], "Not authorized oracle");
        
        // FIX: Check report expiration for this specific oracle's previous report
        PriceReport storage existingReport = submittedPrices[asset][msg.sender];
        if (existingReport.timestamp > 0 && block.timestamp > existingReport.timestamp + reportExpiry) {
            emit ReportExpired(asset, msg.sender, existingReport.timestamp);
        }

        submittedPrices[asset][msg.sender] = PriceReport(value, block.timestamp);
        emit PriceSubmitted(asset, msg.sender, value);

        checkAndUpdateConsensus(asset);
    }

    function getLatestPrice(string calldata asset) external view returns (uint256) {
        return latestConsensusPrice[asset];
    }

    function checkAndUpdateConsensus(string memory asset) internal {
        address[] storage oracles = authorizedOracles[asset];
        uint256[] memory values = new uint256[](oracles.length);
        uint256 validReports = 0;

        for (uint256 i = 0; i < oracles.length; i++) {
            PriceReport memory report = submittedPrices[asset][oracles[i]];
            // FIX: Discard reports older than reportExpiry
            if (report.timestamp > 0 && block.timestamp - report.timestamp <= reportExpiry) {
                values[validReports] = report.value;
                validReports++;
            }
        }

        if (validReports >= quorum) {
            uint256 consensus = median(values, validReports);
            latestConsensusPrice[asset] = consensus;
            emit ConsensusPriceUpdated(asset, consensus);
        }
    }

    // FIX: Added function to remove old/expired reports to prevent storage bloat
    function removeOldReports(string calldata asset) external {
        address[] storage oracles = authorizedOracles[asset];
        uint256 removedCount = 0;
        
        for (uint256 i = 0; i < oracles.length; i++) {
            address oracle = oracles[i];
            PriceReport storage report = submittedPrices[asset][oracle];
            
            // Remove reports that are significantly expired (2x the expiry window)
            if (report.timestamp > 0 && block.timestamp > report.timestamp + (reportExpiry * 2)) {
                delete submittedPrices[asset][oracle];
                removedCount++;
            }
        }
        
        emit OldReportsRemoved(asset, removedCount);
    }
    
    // FIX: Batch cleanup function for all assets
    function removeAllOldReports() external {
        for (uint256 a = 0; a < trackedAssets.length; a++) {
            string memory asset = trackedAssets[a];
            address[] storage oracles = authorizedOracles[asset];
            uint256 removedCount = 0;
            
            for (uint256 i = 0; i < oracles.length; i++) {
                address oracle = oracles[i];
                PriceReport storage report = submittedPrices[asset][oracle];
                
                if (report.timestamp > 0 && block.timestamp > report.timestamp + (reportExpiry * 2)) {
                    delete submittedPrices[asset][oracle];
                    removedCount++;
                }
            }
            
            if (removedCount > 0) {
                emit OldReportsRemoved(asset, removedCount);
            }
        }
    }
    
    // FIX: Get all authorized oracles for an asset
    function getAllOracles(string calldata asset) external view returns (address[] memory) {
        return authorizedOracles[asset];
    }
    
    // FIX: Check if an oracle is authorized for an asset (O(1) lookup)
    function checkOracleAuthorization(string calldata asset, address oracle) external view returns (bool) {
        return isOracleAuthorized[asset][oracle];
    }

    function median(uint256[] memory a, uint256 len) internal pure returns (uint256) {
        for (uint i = 0; i < len - 1; i++) {
            for (uint j = 0; j < len - i - 1; j++) {
                if (a[j] > a[j + 1]) {
                    (a[j], a[j + 1]) = (a[j + 1], a[j]);
                }
            }
        }
        return a[len / 2];
    }
}
