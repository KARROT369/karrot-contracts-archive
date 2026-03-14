// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract KarrotMeshOracle {
    address public owner;
    uint public quorum; // Minimum number of agreeing feeds

    struct PriceReport {
        uint price;
        uint timestamp;
    }

    mapping(string => PriceReport[]) public assetReports;

    constructor(uint _quorum) {
        owner = msg.sender;
        quorum = _quorum;
    }

    function submitPrice(string calldata asset, uint price) external {
        assetReports[asset].push(PriceReport(price, block.timestamp));
    }

    function getVerifiedPrice(string calldata asset) public view returns (uint) {
        PriceReport[] memory reports = assetReports[asset];
        require(reports.length >= quorum, "Not enough data");

        uint[] memory prices = new uint[](reports.length);
        for (uint i = 0; i < reports.length; i++) {
            prices[i] = reports[i].price;
        }

        // Sort + take median
        for (uint i = 0; i < prices.length; i++) {
            for (uint j = i+1; j < prices.length; j++) {
                if (prices[i] > prices[j]) {
                    (prices[i], prices[j]) = (prices[j], prices[i]);
                }
            }
        }
        return prices[reports.length / 2]; // Median
    }
}
