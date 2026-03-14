// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Karrot Stabilization Vault (KSV) v1.0 - PulseChain Remix-ready Prototype
/// @author Sigma Mother / Mandala Matrix
/// @notice Provides automated peg defense and multi-asset staking for mxDAI on PulseChain

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address owner) external view returns (uint256);
    function burn(uint256 amount) external;
    function decimals() external view returns (uint8);
}

contract KarrotStabilizationVault {
    address public owner;
    address public mxDai;
    address[] public approvedStablecoins;
    uint256 public minCollateralRatio = 130; // e.g. 130%, can be adjusted via governance
    uint256 public lowCollateralRatio = 120; // below this = risk, pause payouts
    bool public circuitBreaker = false;

    // Vault balances (asset => amount)
    mapping(address => uint256) public vaultBalances;

    // Events
    event Deposit(address indexed user, address indexed asset, uint256 amount);
    event Withdraw(address indexed user, address indexed asset, uint256 amount);
    event PegDefense(uint256 mxDaiBought, uint256 blockTimestamp);
    event RewardsIssued(address indexed user, uint256 reward, uint256 blockTimestamp);
    event CircuitBreakerActivated(uint256 timestamp);
    event ParamChange(string param, uint256 newValue);

    constructor(address _mxDai, address[] memory _stables) {
        owner = msg.sender;
        mxDai = _mxDai;
        approvedStablecoins = _stables;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    modifier notPaused() {
        require(!circuitBreaker, "Contract paused");
        _;
    }

    // ===== User Interactions =====
    function deposit(address asset, uint256 amount) external notPaused {
        require(isApprovedStablecoin(asset), "Asset not approved");
        require(IERC20(asset).transferFrom(msg.sender, address(this), amount), "Transfer failed");
        vaultBalances[asset] += amount;
        emit Deposit(msg.sender, asset, amount);
    }

    function withdraw(address asset, uint256 amount) external onlyOwner {
        require(vaultBalances[asset] >= amount, "Insufficient vault balance");
        require(IERC20(asset).transfer(msg.sender, amount), "Withdraw failed");
        vaultBalances[asset] -= amount;
        emit Withdraw(msg.sender, asset, amount);
    }

    // ===== Peg Defense Logic (Vault-Driven Buyback) =====
    function defendPeg(uint256 maxSpend, uint256 minBuy) external notPaused {
        require(vaultBalances[mxDai] >= minBuy, "Not enough mxDAI for buyback");
        require(minBuy > 0 && minBuy <= maxSpend, "Invalid buy amounts");
        IERC20(mxDai).burn(minBuy);
        vaultBalances[mxDai] -= minBuy;
        emit PegDefense(minBuy, block.timestamp);
    }

    // ===== Governance & Circuit Breaker =====
    function toggleBreaker() external onlyOwner {
        circuitBreaker = !circuitBreaker;
        emit CircuitBreakerActivated(block.timestamp);
    }

    function setCollateralRatios(uint256 minRatio, uint256 lowRatio) external onlyOwner {
        minCollateralRatio = minRatio;
        lowCollateralRatio = lowRatio;
        emit ParamChange("Collateral Ratios", minRatio);
    }

    // ===== Utility/Internal =====
    function isApprovedStablecoin(address asset) public view returns (bool) {
        if (asset == mxDai) return true;
        for (uint256 i = 0; i < approvedStablecoins.length; i++) {
            if (approvedStablecoins[i] == asset) return true;
        }
        return false;
    }

    // ===== Transparent State =====
    function getVaultBalance(address asset) public view returns (uint256) {
        return vaultBalances[asset];
    }

    function getApprovedStables() public view returns (address[] memory) {
        return approvedStablecoins;
    }
}
