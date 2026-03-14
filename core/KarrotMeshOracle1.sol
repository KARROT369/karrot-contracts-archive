// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract KarrotMeshOracle {
    struct PriceReport {
        uint256 value;
        uint256 timestamp;
    }

    mapping(string => mapping(address => PriceReport)) public submittedPrices; // asset => oracle => report
    mapping(string => address[]) public oracleSet; // asset => authorized oracles

    address public owner;
    uint256 public quorum; // e.g. 3 = minimum reports required for price acceptance
    mapping(string => uint256) public latestConsensusPrice;

    event PriceSubmitted(string asset, address oracle, uint256 value);
    event ConsensusPriceUpdated(string asset, uint256 consensusPrice);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(uint256 _quorum) {
        owner = msg.sender;
        quorum = _quorum;
    }

    function authorizeOracle(string memory asset, address oracle) external onlyOwner {
        oracleSet[asset].push(oracle);
    }

    function submitPrice(string calldata asset, uint256 value) external {
        require(isAuthorized(asset, msg.sender), "Not authorized");
        submittedPrices[asset][msg.sender] = PriceReport(value, block.timestamp);
        emit PriceSubmitted(asset, msg.sender, value);

        if (oracleSet[asset].length >= quorum) {
            uint256[] memory values = new uint256[](oracleSet[asset].length);
            uint count = 0;

            for (uint i = 0; i < oracleSet[asset].length; i++) {
                address o = oracleSet[asset][i];
                PriceReport memory r = submittedPrices[asset][o];
                if (r.timestamp > 0) {
                    values[count] = r.value;
                    count++;
                }
            }

            if (count >= quorum) {
                uint256 consensus = median(values, count);
                latestConsensusPrice[asset] = consensus;
                emit ConsensusPriceUpdated(asset, consensus);
            }
        }
    }

    function getLatestPrice(string calldata asset) external view returns (uint256) {
        return latestConsensusPrice[asset];
    }

    function isAuthorized(string memory asset, address oracle) internal view returns (bool) {
        for (uint i = 0; i < oracleSet[asset].length; i++) {
            if (oracleSet[asset][i] == oracle) return true;
        }
        return false;
    }

    function median(uint256[] memory a, uint len) internal pure returns (uint256) {
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
