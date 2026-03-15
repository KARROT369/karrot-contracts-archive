// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Karrot Stabilization Vault - IMMUTABLE VERSION
/// @notice Automated peg defense and staking - NO ADMIN, NO PAUSE
/// @dev All parameters and approved assets set at deployment. Cannot be changed.

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address owner) external view returns (uint256);
    function burn(uint256 amount) external;
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
}

interface IDexRouter {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}

interface IPriceOracle {
    function getLatestPrice(string calldata asset) external view returns (uint256);
}

contract KarrotStabilizationVault_Immutable is ReentrancyGuard {
    // ============ Structs ============
    struct DepositInfo {
        uint256 amount;
        uint256 timestamp;
        uint256 rewardDebt;
        uint256 lastClaim;
    }
    
    // ============ Immutable State ============
    IERC20 public immutable mxDai;
    IDexRouter public immutable dexRouter;
    IPriceOracle public immutable priceOracle;
    
    address[] public approvedStablecoins;
    mapping(address => bool) public isApprovedStable;
    
    mapping(address => mapping(address => DepositInfo)) public userDeposits;
    mapping(address => uint256) public totalDeposits;
    mapping(address => uint256) public vaultBalance;
    
    uint256 public immutable rewardRate;
    uint256 public immutable maxSlippage;
    uint256 public immutable targetPeg;
    uint256 public immutable minDefendAmount;
    uint256 public immutable minCollateralRatio;
    
    uint256 public accRewardPerShare = 0;
    uint256 public lastRewardTime;
    uint256 public currentCollateralRatio = 15000; // 150% initially
    
    uint256 public constant PEG_PRECISION = 1e8;
    uint256 public constant BASIS_POINTS = 10000;
    
    // ============ Events ============
    event Deposited(address indexed user, address indexed asset, uint256 amount);
    event Withdrawn(address indexed user, address indexed asset, uint256 amount, uint256 rewards);
    event PegDefended(uint256 mxDaiBought, uint256 stableSold, uint256 priceBefore, uint256 priceAfter);
    event RewardsClaimed(address indexed user, uint256 amount);
    event CollateralRatioChecked(uint256 ratio, bool isSafe);
    
    // ============ Modifiers ============
    modifier onlyApproved(address asset) {
        require(isApprovedStable[asset], "Asset not approved");
        _;
    }
    
    // ============ Constructor - EVERYTHING SET HERE ============
    constructor(
        address _mxDai,
        address[] memory _stables,
        address _dexRouter,
        address _priceOracle,
        uint256 _targetPeg,
        uint256 _rewardRate,
        uint256 _maxSlippage,
        uint256 _minDefendAmount,
        uint256 _minCollateralRatio
    ) {
        require(_mxDai != address(0), "Invalid mxDai");
        require(_dexRouter != address(0), "Invalid router");
        require(_priceOracle != address(0), "Invalid oracle");
        require(_stables.length > 0, "Need at least one stable");
        require(_targetPeg > 0, "Invalid target peg");
        require(_rewardRate > 0, "Invalid reward rate");
        require(_maxSlippage <= 1000, "Slippage too high"); // Max 10%
        require(_minDefendAmount > 0, "Invalid min defend");
        require(_minCollateralRatio >= 10000, "Collateral ratio must be >= 100%");
        
        mxDai = IERC20(_mxDai);
        dexRouter = IDexRouter(_dexRouter);
        priceOracle = IPriceOracle(_priceOracle);
        targetPeg = _targetPeg;
        rewardRate = _rewardRate;
        maxSlippage = _maxSlippage;
        minDefendAmount = _minDefendAmount;
        minCollateralRatio = _minCollateralRatio;
        lastRewardTime = block.timestamp;
        
        // Add approved stables
        for (uint i = 0; i < _stables.length; i++) {
            require(_stables[i] != address(0), "Invalid stable");
            require(!isApprovedStable[_stables[i]], "Duplicate stable");
            isApprovedStable[_stables[i]] = true;
            approvedStablecoins.push(_stables[i]);
        }
    }
    
    // ============ Deposit/Withdraw ============
    
    function deposit(address asset, uint256 amount) external nonReentrant onlyApproved(asset) {
        require(amount > 0, "Amount must be > 0");
        
        _updateRewards();
        
        // Claim pending rewards
        uint256 pending = _pendingRewards(msg.sender, asset);
        if (pending > 0) {
            _safeTransfer(address(mxDai), msg.sender, pending);
            emit RewardsClaimed(msg.sender, pending);
        }
        
        DepositInfo storage info = userDeposits[asset][msg.sender];
        info.rewardDebt = (info.amount * accRewardPerShare) / 1e12;
        
        require(IERC20(asset).transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        info.amount += amount;
        info.timestamp = block.timestamp;
        info.lastClaim = block.timestamp;
        totalDeposits[asset] += amount;
        vaultBalance[asset] += amount;
        
        _updateCollateralRatio();
        
        emit Deposited(msg.sender, asset, amount);
    }
    
    function withdraw(address asset, uint256 amount) external nonReentrant onlyApproved(asset) {
        DepositInfo storage info = userDeposits[asset][msg.sender];
        require(info.amount >= amount, "Insufficient balance");
        
        _updateRewards();
        
        uint256 pending = _pendingRewards(msg.sender, asset);
        
        info.amount -= amount;
        totalDeposits[asset] -= amount;
        vaultBalance[asset] -= amount;
        info.rewardDebt = (info.amount * accRewardPerShare) / 1e12;
        
        require(IERC20(asset).transfer(msg.sender, amount), "Withdraw failed");
        
        if (pending > 0) {
            _safeTransfer(address(mxDai), msg.sender, pending);
            emit RewardsClaimed(msg.sender, pending);
        }
        
        info.lastClaim = block.timestamp;
        _updateCollateralRatio();
        
        emit Withdrawn(msg.sender, asset, amount, pending);
    }
    
    function claimRewards(address asset) external nonReentrant onlyApproved(asset) {
        _updateRewards();
        
        uint256 pending = _pendingRewards(msg.sender, asset);
        require(pending > 0, "No rewards to claim");
        
        DepositInfo storage info = userDeposits[asset][msg.sender];
        info.lastClaim = block.timestamp;
        info.rewardDebt = (info.amount * accRewardPerShare) / 1e12;
        
        _safeTransfer(address(mxDai), msg.sender, pending);
        emit RewardsClaimed(msg.sender, pending);
    }
    
    // ============ Peg Defense ============
    
    function defendPeg(
        uint256 maxSpend,
        address stableToUse,
        uint256 minReceive
    ) external nonReentrant returns (uint256 mxDaiBought) {
        require(isApprovedStable[stableToUse], "Stable not approved");
        require(vaultBalance[stableToUse] >= maxSpend, "Insufficient vault balance");
        require(maxSpend >= minDefendAmount, "Amount below minimum");
        
        uint256 priceBefore = _getMxDaiPrice();
        require(priceBefore < targetPeg, "Peg is healthy");
        
        uint256 slippage = (maxSpend * maxSlippage) / BASIS_POINTS;
        require(minReceive >= maxSpend - slippage, "Min receive too low");
        
        IERC20(stableToUse).approve(address(dexRouter), maxSpend);
        
        address[] memory path = new address[](2);
        path[0] = stableToUse;
        path[1] = address(mxDai);
        
        uint256[] memory amounts = dexRouter.swapExactTokensForTokens(
            maxSpend,
            minReceive,
            path,
            address(this),
            block.timestamp + 300
        );
        
        mxDaiBought = amounts[amounts.length - 1];
        mxDai.burn(mxDaiBought);
        vaultBalance[stableToUse] -= maxSpend;
        
        uint256 priceAfter = _getMxDaiPrice();
        _updateCollateralRatio();
        
        emit PegDefended(mxDaiBought, maxSpend, priceBefore, priceAfter);
    }
    
    // ============ Internal Functions ============
    
    function _updateRewards() internal {
        if (block.timestamp <= lastRewardTime) return;
        
        uint256 totalStaked = totalDeposits[address(mxDai)];
        for (uint i = 0; i < approvedStablecoins.length; i++) {
            totalStaked += totalDeposits[approvedStablecoins[i]];
        }
        
        if (totalStaked == 0) {
            lastRewardTime = block.timestamp;
            return;
        }
        
        uint256 elapsed = block.timestamp - lastRewardTime;
        uint256 reward = elapsed * rewardRate * totalStaked / 1e18;
        accRewardPerShare += (reward * 1e12) / totalStaked;
        lastRewardTime = block.timestamp;
    }
    
    function _pendingRewards(address user, address asset) internal view returns (uint256) {
        DepositInfo storage info = userDeposits[asset][user];
        if (info.amount == 0) return 0;
        return (info.amount * accRewardPerShare) / 1e12 - info.rewardDebt;
    }
    
    function _updateCollateralRatio() internal {
        uint256 totalCollateral = 0;
        uint256 totalDebt = mxDai.totalSupply();
        
        for (uint i = 0; i < approvedStablecoins.length; i++) {
            address stable = approvedStablecoins[i];
            uint256 balance = vaultBalance[stable];
            if (balance > 0) {
                uint256 price = priceOracle.getLatestPrice(_getSymbol(stable));
                uint256 decimals = IERC20(stable).decimals();
                totalCollateral += (balance * price) / (10 ** decimals);
            }
        }
        
        if (totalDebt > 0) {
            currentCollateralRatio = (totalCollateral * BASIS_POINTS) / totalDebt;
        } else {
            currentCollateralRatio = 15000;
        }
        
        emit CollateralRatioChecked(currentCollateralRatio, currentCollateralRatio >= minCollateralRatio);
    }
    
    function _getMxDaiPrice() internal view returns (uint256) {
        return priceOracle.getLatestPrice("MXDAI");
    }
    
    function _getSymbol(address token) internal pure returns (string memory) {
        // Simplified - in production would query token.symbol()
        return "STABLE";
    }
    
    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, ) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(success, "Transfer failed");
    }
    
    // ============ View Functions ============
    
    function getDepositInfo(address user, address asset) external view returns (DepositInfo memory) {
        return userDeposits[asset][user];
    }
    
    function getPendingRewards(address user, address asset) external view returns (uint256) {
        return _pendingRewards(user, asset);
    }
    
    function getApprovedStables() external view returns (address[] memory) {
        return approvedStablecoins;
    }
    
    // ============ NO ADMIN FUNCTIONS ============
    // No addStable - stables are immutable
    // No setPegParams - params are immutable
    // No setRewardRate - rate is immutable
    // No emergencyDefend - no admin override
    // No owner - no one can change anything
}
