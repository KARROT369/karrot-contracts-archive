// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

contract SigmaInterestModel {
    address public controller;
    address public dao;

    struct InterestParams {
        uint256 baseRate; // e.g. 2e16 = 2%
        uint256 kink;     // utilization (in 1e18) where rate slope changes
        uint256 slopeLow; // below kink
        uint256 slopeHigh;// above kink
    }

    mapping(address => InterestParams) public tokenParams;

    modifier onlyDAO() {
        require(msg.sender == dao, "Not DAO");
        _;
    }

    constructor(address _controller, address _dao) {
        controller = _controller;
        dao = _dao;
    }

    function setParams(
        address token,
        uint256 baseRate,
        uint256 kink,
        uint256 slopeLow,
        uint256 slopeHigh
    ) external onlyDAO {
        tokenParams[token] = InterestParams(baseRate, kink, slopeLow, slopeHigh);
    }

    // Called by vault: gets current borrow rate
    function getBorrowRate(address token, uint256 totalSupply, uint256 totalBorrow) external view returns (uint256) {
        if (totalSupply == 0) return 0;
        InterestParams memory p = tokenParams[token];
        uint256 util = (totalBorrow * 1e18) / totalSupply;

        if (util < p.kink) {
            return p.baseRate + ((util * p.slopeLow) / 1e18);
        } else {
            uint256 over = util - p.kink;
            return p.baseRate + ((p.kink * p.slopeLow) / 1e18) + ((over * p.slopeHigh) / 1e18);
        }
    }
}
