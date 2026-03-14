// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FlippedGamifiedStaking
 * @notice Stake Karrot, earn Rabbit Hole rewards with XP/level system
 */
contract FlippedGamifiedStaking is ReentrancyGuard, Ownable {
    IERC20 public stakingToken;    // Karrot token
    IERC20 public rewardsToken;    // Rabbit Hole token

    uint256 public rewardRate;     // Rewards per second
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public constant PRECISION = 1e18;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    // Gamification
    mapping(address => uint256) public xp;
    mapping(address => uint256) public level;
    uint256 public constant XP_PER_SECOND_PER_TOKEN = 1;
    uint256[] public levels = [0, 1000, 5000, 15000, 35000, 70000];
    address[] public leaderboard;

    uint256 public constant EMERGENCY_PENALTY = 10;
    bool public paused;

    // Events
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);
    event LevelUp(address indexed user, uint256 newLevel);
    event EmergencyWithdraw(address indexed user, uint256 amountAfterPenalty);
    event RateUpdated(uint256 newRate);

    constructor(uint256 _rewardRate) Ownable(msg.sender) {
        stakingToken = IERC20(0x6910076Eee8F4b6ea251B7cCa1052dd744Fc04DA); // Karrot
        rewardsToken = IERC20(0xDB75a19203a65Ba93c1baaac777d229bf08452Da); // Rabbit Hole
        require(_rewardRate > 0, "Invalid rate");
        rewardRate = _rewardRate;
        lastUpdateTime = block.timestamp;
    }

    modifier notPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    function stake(uint256 amount) external notPaused nonReentrant {
        require(amount > 0, "Cannot stake zero");
        
        _updateReward(msg.sender);
        _totalSupply += amount;
        _balances[msg.sender] += amount;

        require(stakingToken.transferFrom(msg.sender, address(this), amount), "Stake failed");

        _tryUpdateLevel(msg.sender);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) external notPaused nonReentrant {
        require(amount > 0, "Cannot withdraw zero");
        require(_balances[msg.sender] >= amount, "Withdraw exceeds balance");
        
        _updateReward(msg.sender);
        _totalSupply -= amount;
        _balances[msg.sender] -= amount;

        require(stakingToken.transfer(msg.sender, amount), "Withdraw failed");

        _tryUpdateLevel(msg.sender);
        emit Withdrawn(msg.sender, amount);
    }

    function claimReward() external notPaused nonReentrant {
        _updateReward(msg.sender);
        uint256 reward = rewards[msg.sender];
        require(reward > 0, "No rewards");

        rewards[msg.sender] = 0;
        require(rewardsToken.transfer(msg.sender, reward), "Reward transfer failed");
        
        emit RewardClaimed(msg.sender, reward);
    }

    function emergencyWithdraw() external nonReentrant {
        uint256 balance = _balances[msg.sender];
        require(balance > 0, "Nothing to withdraw");

        uint256 penalty = (balance * EMERGENCY_PENALTY) / 100;
        uint256 amountAfterPenalty = balance - penalty;

        _totalSupply -= balance;
        _balances[msg.sender] = 0;
        rewards[msg.sender] = 0;

        require(stakingToken.transfer(msg.sender, amountAfterPenalty), "Emergency withdraw failed");
        emit EmergencyWithdraw(msg.sender, amountAfterPenalty);

        _tryUpdateLevel(msg.sender);
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) return rewardPerTokenStored;
        return rewardPerTokenStored + (((block.timestamp - lastUpdateTime) * rewardRate * PRECISION) / _totalSupply);
    }

    function earned(address account) public view returns (uint256) {
        uint256 base = (_balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / PRECISION + rewards[account];
        uint256 multiplier = 100 + (level[account] * 10);
        return (base * multiplier) / 100;
    }

    function _updateReward(address account) internal {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;

        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
    }

    function _tryUpdateLevel(address user) internal {
        if (rewards[user] > 0) {
            xp[user] += rewards[user] / PRECISION;
        }

        uint256 currentLevel = level[user];
        for (uint256 i = levels.length - 1; i > currentLevel; i--) {
            if (xp[user] >= levels[i]) {
                level[user] = i;
                emit LevelUp(user, i);
                break;
            }
        }
    }

    function _tryAddToLeaderboard(address user) internal {
        if (_balances[user] > 0) {
            for (uint256 i = 0; i < leaderboard.length; i++) {
                if (leaderboard[i] == user) return;
            }
            leaderboard.push(user);
        }
    }

    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        require(_rewardRate > 0, "Invalid rate");
        _updateReward(address(0));
        rewardRate = _rewardRate;
        emit RateUpdated(_rewardRate);
    }

    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    function totalSupply() external view returns (uint256) { return _totalSupply; }
    function balanceOf(address account) external view returns (uint256) { return _balances[account]; }
    function getUserStats(address user) external view returns (uint256 userXP, uint256 userLevel) {
        return (xp[user], level[user]);
    }
    function getLeaderboard() external view returns (address[] memory) { return leaderboard; }
}
