// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IVault {
    function getTotalDebtValue(address user) external view returns (uint256);
    function getCollateralValue(address user) external view returns (uint256);
    function liquidate(address user, address token, uint256 amount, address receiver) external;
}

interface ITWAP {
    function getTWAP(address token) external view returns (uint256);
}

contract SigmaLiquidator {
    IVault public vault;
    ITWAP public twap;
    address public dao;

    modifier onlyDAO() {
        require(msg.sender == dao, "Not DAO");
        _;
    }

    constructor(address _vault, address _twap, address _dao) {
        vault = IVault(_vault);
        twap = ITWAP(_twap);
        dao = _dao;
    }

    function checkHealthFactor(address user) public view returns (uint256) {
        uint256 debt = vault.getTotalDebtValue(user);
        uint256 col = vault.getCollateralValue(user);
        if (debt == 0) return 1e18;
        return (col * 1e18) / debt;
    }

    function executeLiquidation(address user, address token, uint256 repayAmount) external {
        require(checkHealthFactor(user) < 1e18, "User healthy");
        vault.liquidate(user, token, repayAmount, msg.sender);
    }

    // DAO-only hook to auto-liquidate batch
    function batchLiquidate(address[] calldata users, address token) external onlyDAO {
        for (uint i = 0; i < users.length; i++) {
            if (checkHealthFactor(users[i]) < 1e18) {
                vault.liquidate(users[i], token, type(uint256).max, msg.sender);
            }
        }
    }
}
