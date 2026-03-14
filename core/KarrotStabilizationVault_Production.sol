// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Karrot Stabilization Vault (KSV) - Production
/// @notice Automated peg defense and multi-asset staking with DEX integration
/// @dev Production: Full DEX-based peg defense, reentrancy protection, reward calculation, emergency controls

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

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

contract KarrotStabilizationVault is Ownable, ReentrancyGuard, Pausable {
    // ============ Structs ============
    struct DepositInfo {
        uint256 amount;
        uint256 timestamp;
        uint256 rewardDebt;
        uint256 lastClaim;
    }
    
    struct PegDefenseParams {
        uint256 maxSlippage;      // Max slippage in basis points (e.g., 100 = 1%)
        uint256 targetPeg;        // Target peg in oracle precision (e.g., 1e8 for $1.00)
        uint256 minDefendAmount;  // Minimum amount to trigger defense
        bool active;
    }
    
    // ============ State ============
    IERC20 public mxDai;
    IDexRouter public dexRouter;
    IPriceOracle public priceOracle;
    
    address[] public approvedStablecoins;
    mapping(address => bool) public isApprovedStable;
    
    // User deposits (asset => user => info)
    mapping(address => mapping(address => DepositInfo)) public userDeposits;
    mapping(address => uint256) public totalDeposits;
    
    // Vault state
    mapping(address => uint256) public vaultBalance;
    uint256 public totalVaultValue;
    
    // Peg defense
    PegDefenseParams public pegParams;
    uint256 public constant PEG_PRECISION = 1e8;
    uint256 public constant BASIS_POINTS = 10000;
    
    // Rewards
    uint256 public rewardRate = 100; // Rewards per second per 1e18 deposited
    uint256 public accRewardPerShare = 0;
    uint256 public lastRewardTime;
    mapping(address => uint256) public userRewardDebt;
    
    // Collateral levels
    uint256 public constant MIN_COLLATERAL_RATIO = 13000; // 130% in basis points
    uint256 public constant LOW_COLLATERAL_RATIO = 12000; // 120% in basis points
    uint256 public currentCollateralRatio = 15000; // 150% initially
    
    // ============ Events ============
    event Deposited(address indexed user, address indexed asset, uint256 amount);
    event Withdrawn(address indexed user, address indexed asset, uint256 amount, uint256 rewards);
    event PegDefended(uint256 mxDaiBought, uint256 stableSold, uint256 priceBefore, uint256 priceAfter);
    event RewardsClaimed(address indexed user, uint256 amount);
    event CollateralRatioChecked(uint256 ratio, bool isSafe);
    event CircuitBreakerToggled(bool paused);
    event EmergencyDefendTriggered(uint256 timestamp);
    event StableAdded(address stable);
    event StableRemoved(address stable);
    
    // ============ Modifiers ============
    modifier onlyApproved(address asset) {
        require(isApprovedStable[asset]

 || asset == address(mxDai), "Asset not approved");
        _;
    }
    
    // ============ Constructor ============
    constructor(
        address _mxDai,
        address[] memory _stables,
        address _dexRouter,
        address _priceOracle,
        uint256 _targetPeg
    ) {
        require(_mxDai != address(0), "Invalid mxDai");
        require(_dexRouter != address(0), "Invalid router");
        require(_priceOracle != address(0), "Invalid oracle");
        
        mxDai = IERC20(_mxDai);
        dexRouter = IDexRouter(_dexRouter);
        priceOracle = IPriceOracle(_priceOracle);
        
        // Add approved stables
        for (uint i = 0; i < _stables.length; i++) {
            _addStable(_stables[i]);
        }
        
        pegParams = PegDefenseParams({
            maxSlippage: 300, // 3% max slippage
            targetPeg: _targetPeg,
            minDefendAmount: 1000 * 1e18, // 1000 tokens
            active: true
        });
        
        lastRewardTime = block.timestamp;
    }
    
    // ============ Admin Functions ============
    
    function addStable(address stable) external onlyOwner {
        _addStable(stable);
    }
    
    function removeStable(address stable) external onlyOwner {
        require(isApprovedStable[stable], "Not approved");
        isApprovedStable[stable] = false;
        
        // Remove from array
        for (uint i = 0; i < approvedStablecoins.length; i++) {
            if (approvedStablecoins[i] == stable) {
                approvedStablecoins[i] = approvedStablecoins[approvedStablecoins.length - 1];
                approvedStablecoins.pop();
                break;
            }
        }
        emit StableRemoved(stable);
    }
    
    function setPegParams(
        uint256 maxSlippage,
        uint256 targetPeg,
        uint256 minDefendAmount,
        bool active
    ) external onlyOwner {
        require(maxSlippage <= 1000, "Slippage too high"); // Max 10%
        pegParams = PegDefenseParams(maxSlippage, targetPeg, minDefendAmount, active);
    }
    
    function setRewardRate(uint256 _rate) external onlyOwner {
        _updateRewards();
        rewardRate = _rate;
    }
    
    function setDexRouter(address _router) external onlyOwner {
        require(_router != address(0), "Invalid router");
        dexRouter = IDexRouter(_router);
    }
    
    function setPriceOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "Invalid oracle");
        priceOracle = IPriceOracle(_oracle);
    }
    
    // ============ Deposit/Withdraw ============
    
    function deposit(address asset, uint256 amount) external nonReentrant whenNotPaused onlyApproved(asset) {
        require(amount > 0, "Amount must be > 0");
        
        _updateRewards();
        
        // Claim pending rewards before updating deposit
        uint256 pending = _pendingRewards(msg.sender, asset);
        if (pending > 0) {
            _safeTransfer(address(mxDai), msg.sender, pending);
            emit RewardsClaimed(msg.sender, pending);
        }
        
        DepositInfo storage info = userDeposits[asset][msg.sender];
        
        // Update reward debt
        info.rewardDebt = (info.amount * accRewardPerShare) / 1e12;
        
        // Transfer tokens
        require(IERC20(asset).transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        // Update state
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
        
        // Calculate rewards
        uint256 pending = _pendingRewards(msg.sender, asset);
        
        // Update state
        info.amount -= amount;
        totalDeposits[asset] -= amount;
        vaultBalance[asset] -= amount;
        info.rewardDebt = (info.amount * accRewardPerShare) / 1e12;
        
        // Transfer tokens and rewards
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
    
    /// @notice Defend the peg by buying mxDAI when under peg
    function defendPeg(
        uint256 maxSpend,
        address stableToUse,
        uint256 minReceive
    ) external nonReentrant whenNotPaused returns (uint256 mxDaiBought) {
        require(pegParams.active, "Peg defense not active");
        require(isApprovedStable[stableToUse], "Stable not approved");
        require(vaultBalance[stableToUse] >= maxSpend, "Insufficient vault balance");
        require(maxSpend >= pegParams.minDefendAmount, "Amount below minimum");
        
        // Get current price
        uint256 priceBefore = _getMxDaiPrice();
        
        // Only defend if mxDAI is below target peg (price < target indicates below peg)
        require(priceBefore < pegParams.targetPeg, "Peg is healthy");
        
        // Calculate maximum slippage
        uint256 slippage = (maxSpend * pegParams.maxSlippage) / BASIS_POINTS;
        require(minReceive >= maxSpend - slippage, "Min receive too low");
        
        // Approve router
        IERC20(stableToUse).approve(address(dexRouter), maxSpend);
        
        // Swap stable for mxDai
        address[] memory path = new address[](2);
        path[0] = stableToUse;
        path[1] = address(mxDai);
        
        uint256[] memory amounts = dexRouter.swapExactTokensForTokens(
            maxSpend,
            minReceive,
            path,
            address(this),
            block.timestamp + 300 // 5 min deadline
        );
        
        mxDaiBought = amounts[amounts.length - 1];
        
        // Burn purchased mxDai to reduce supply and defend peg
        mxDai.burn(mxDaiBought);
        
        // Update vault state
        vaultBalance[stableToUse] -= maxSpend;
        
        // Get price after
        uint256 priceAfter = _getMxDaiPrice();
        
        // Update collateral ratio
        _updateCollateralRatio();
        
        emit PegDefended(mxDaiBought, maxSpend, priceBefore, priceAfter);
        
        return mxDaiBought;
    }
    
    /// @notice Emergency peg defense (owner only, buys and burns without checks)
    function emergencyDefend(
        address stableToUse,
        uint256 amount,
        uint256 minReceive
    ) external onlyOwner nonReentrant {
        require(isApprovedStable[stableToUse], "Stable not approved");
        require(vaultBalance[stableToUse] >= amount, "Insufficient balance");
        
        // Approve and swap
        IERC20(stableToUse).approve(address(dexRouter), amount);
        
        address[] memory path = new address[](2);
        path[0] = stableToUse;
        path[1] = address(mxDai);
        
        uint256[] memory amounts = dexRouter.swapExactTokensForTokens(
            amount,
            minReceive,
            path,
            address(this),
            block.timestamp + 60 // 1 min deadline for emergency
        );
        
        uint256 mxDaiBought = amounts[amounts.length - 1];
        mxDai.burn(mxDaiBought);
        vaultBalance[stableToUse] -= amount;
        
        _updateCollateralRatio();
        
        emit EmergencyDefendTriggered(block.timestamp);
        emit PegDefended(mxDaiBought, amount, 0, 0);
    }
    
    // ============ Internal Functions ============
    
    function _addStable(address stable) internal {
        require(stable != address(0), "Invalid stable");
        require(!isApprovedStable[stable], "Already approved");
        isApprovedStable[stable] = true;
        approvedStablecoins.push(stable);
        emit StableAdded(stable);
    }
    
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
                // Get price from oracle
                uint256 price = priceOracle.getLatestPrice(_getSymbol(stable));
                uint256 decimals = IERC20(stable).decimals();
                totalCollateral += (balance * price) / (10 ** decimals);
            }
        }
        
        if (totalDebt > 0) {
            currentCollateralRatio = (totalCollateral * BASIS_POINTS) / totalDebt;
        } else {
            currentCollateralRatio = 15000; // Default 150%
        }
        
        emit CollateralRatioChecked(currentCollateralRatio, currentCollateralRatio >= MIN_COLLATERAL_RATIO);
    }
    
    function _getMxDaiPrice() internal view returns (uint256) {
        return priceOracle.getLatestPrice("mxDAI");
    }
    
    function _getSymbol(address token) internal pure returns (string memory) {
        // Simplified - in production use a registry or IERC20Metadata
        return "STABLE";
    }
    
    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, ) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(success, "Transfer failed");
    }
    
    // ============ View Functions ============
    
    function getPendingRewards(address user, address asset) external view returns (uint256) {
        return _pendingRewards(user, asset);
    }
    
    function getDepositInfo(address user, address asset) external view returns (DepositInfo memory) {
        return userDeposits[asset][user];
    }
    
    function getVaultBalance(address asset) external view returns (uint256) {
        return vaultBalance[asset];
    }
    
    function isCollateralSafe() external view returns (bool) {
        return currentCollateralRatio >= MIN_COLLATERAL_RATIO;
    }
    
    function isCollateralLow() external view returns (bool) {
        return currentCollateralRatio < LOW_COLLATERAL_RATIO;
    }
    
    function getApprovedStables() external view returns (address[] memory) {
        return approvedStablecoins;
    }
    
    // ============ Emergency Functions ============
    
    function togglePause() external onlyOwner {
        paused() ? _unpause() : _pause();
    }
    
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        require(IERC20(token).transfer(owner(), amount), "Emergency withdraw failed");
    }
}
