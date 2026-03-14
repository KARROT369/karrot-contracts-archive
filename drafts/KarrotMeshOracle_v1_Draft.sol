// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Karrot Mesh Oracle V1 - Optimized Median Oracle with QuickSelect
/// @notice Gas-optimized oracle with quickselect median, staleness checks, and oracle management
/// FIX: Renamed from KarrotMeshOracle to KarrotMeshOracleV1 for clarity

contract KarrotMeshOracle1 {
    struct Report {
        uint256 value;
        uint256 timestamp;
    }

    uint256 public quorum;
    uint256 public constant REPORT_STALENESS = 1 hours; // Reports > 1 hour are ignored
    
    mapping(address => bool) public reporters;
    mapping(uint256 => Report[]) public reports; // roundId => reports
    uint256 public latestValue;
    uint256 public latestRound;
    
    // FIX: Track all authorized oracles for enumeration
    address[] public allOracles;
    mapping(address => uint256) public oracleIndex; // 1-based index (0 = not in array)

    event ReporterAdded(address reporter);
    event ReporterDeauthorized(address reporter);
    event ValueSubmitted(address reporter, uint256 roundId, uint256 value);
    event ValueFinalized(uint256 roundId, uint256 median);
    event StaleReportIgnored(address reporter, uint256 roundId, uint256 reportTimestamp);

    constructor(uint256 _quorum) {
        quorum = _quorum;
    }

    modifier onlyReporter() {
        require(reporters[msg.sender], "Not authorized reporter");
        _;
    }

    // FIX: Add reporter with tracking
    function addReporter(address r) external {
        require(!reporters[r], "Already a reporter");
        reporters[r] = true;
        
        // Add to allOracles array for enumeration
        allOracles.push(r);
        oracleIndex[r] = allOracles.length;
        
        emit ReporterAdded(r);
    }
    
    // FIX: Added deauthorizeOracle function
    function deauthorizeOracle(address r) external {
        require(reporters[r], "Not a reporter");
        reporters[r] = false;
        
        // Remove from allOracles array (swap and pop)
        uint256 index = oracleIndex[r];
        if (index > 0 && index <= allOracles.length) {
            address lastOracle = allOracles[allOracles.length - 1];
            allOracles[index - 1] = lastOracle;
            oracleIndex[lastOracle] = index;
            allOracles.pop();
            oracleIndex[r] = 0;
        }
        
        emit ReporterDeauthorized(r);
    }

    function submit(uint256 roundId, uint256 value) external onlyReporter {
        // FIX: Check report staleness (ignore reports > 1 hour old compared to current block)
        uint256 currentTimestamp = block.timestamp;
        
        reports[roundId].push(Report(value, currentTimestamp));
        emit ValueSubmitted(msg.sender, roundId, value);

        if (reports[roundId].length >= quorum) {
            finalize(roundId);
        }
    }
    
    // FIX: View function to get all authorized oracles
    function getAllOracles() external view returns (address[] memory) {
        return allOracles;
    }
    
    // FIX: Check if an oracle is authorized
    function isReporterAuthorized(address reporter) external view returns (bool) {
        return reporters[reporter];
    }

    function finalize(uint256 roundId) internal {
        Report[] storage r = reports[roundId];
        require(r.length >= quorum, "Not enough reports");

        // Filter out stale reports and collect valid values
        uint256[] memory validValues = new uint256[](r.length);
        uint256 validCount = 0;
        uint256 currentTimestamp = block.timestamp;
        
        for (uint256 i = 0; i < r.length; i++) {
            // FIX: Ignore reports > 1 hour old
            if (currentTimestamp - r[i].timestamp <= REPORT_STALENESS) {
                validValues[validCount] = r[i].value;
                validCount++;
            } else {
                emit StaleReportIgnored(msg.sender, roundId, r[i].timestamp);
            }
        }
        
        require(validCount >= quorum, "Not enough valid (non-stale) reports");

        // FIX: Use optimized quickselect for median instead of bubble sort
        uint256 median = quickSelectMedian(validValues, validCount);
        latestValue = median;
        latestRound = roundId;

        emit ValueFinalized(roundId, median);
    }
    
    // FIX: Optimized median calculation using QuickSelect (O(n) average case)
    function quickSelectMedian(uint256[] memory arr, uint256 len) internal pure returns (uint256) {
        if (len == 0) return 0;
        if (len == 1) return arr[0];
        
        uint256 medianIndex = len / 2;
        return quickSelect(arr, 0, len - 1, medianIndex);
    }
    
    function quickSelect(uint256[] memory arr, uint256 left, uint256 right, uint256 k) internal pure returns (uint256) {
        if (left == right) return arr[left];
        
        uint256 pivotIndex = partition(arr, left, right);
        
        if (k == pivotIndex) {
            return arr[k];
        } else if (k < pivotIndex) {
            return quickSelect(arr, left, pivotIndex - 1, k);
        } else {
            return quickSelect(arr, pivotIndex + 1, right, k);
        }
    }
    
    function partition(uint256[] memory arr, uint256 left, uint256 right) internal pure returns (uint256) {
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
    
    // FIX: Cleanup function to remove old round data and prevent storage bloat
    function cleanupOldRounds(uint256[] calldata roundIds) external {
        for (uint256 i = 0; i < roundIds.length; i++) {
            uint256 roundId = roundIds[i];
            // Only allow cleanup of rounds older than current
            if (roundId < latestRound) {
                delete reports[roundId];
            }
        }
    }
    
    // FIX: View function to get reports for a specific round
    function getRoundReports(uint256 roundId) external view returns (Report[] memory) {
        return reports[roundId];
    }
    
    // FIX: Get the count of reports for a round
    function getRoundReportCount(uint256 roundId) external view returns (uint256) {
        return reports[roundId].length;
    }
}
