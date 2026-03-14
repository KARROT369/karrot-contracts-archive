// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract KarrotMeshOracle {
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

    event OracleAuthorized(string asset, address oracle);
    event PriceSubmitted(string asset, address oracle, uint256 value);
    event ConsensusPriceUpdated(string asset, uint256 consensusPrice);

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
        require(!isAuthorized(asset, oracle), "Already authorized");
        authorizedOracles[asset].push(oracle);
        emit OracleAuthorized(asset, oracle);
    }

    function submitPrice(string calldata asset, uint256 value) external {
        require(isAuthorized(asset, msg.sender), "Not authorized oracle");

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

    function isAuthorized(string memory asset, address oracle) public view returns (bool) {
        address[] storage oracles = authorizedOracles[asset];
        for (uint256 i = 0; i < oracles.length; i++) {
            if (oracles[i] == oracle) return true;
        }
        return false;
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
