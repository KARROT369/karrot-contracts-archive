// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SimpleStaking is ReentrancyGuard, Ownable {
    IERC20 public stakingToken;
    IERC20 public rewardToken;

    mapping(address => uint256) public stakes;
    mapping(address => uint256) public rewardDebt;
    mapping(address => uint256) public userRewardPerTokenPaid;

    uint256 public rewardPerTokenStored;
    uint256 public totalStaked;
    uint256 public lastUpdateTime;
    uint256 public rewardRatePerSecond;
    uint256 public constant PRECISION = 1e18;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event RateUpdated(uint256 newRate);

    constructor(
        address _stakingToken,
        address _rewardToken,
        uint256 _rewardRatePerSecond
    ) Ownable(msg.sender) {
        require(_stakingToken != address(0), "Invalid staking token");
        require(_rewardToken != address(0), "Invalid reward token");
        require(_rewardRatePerSecond > 0, "Invalid rate");
        
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        rewardRatePerSecond = _rewardRatePerSecond;
        lastUpdateTime = block.timestamp;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        if (account != address(0)) {
            uint256 earned = _earned(account);
            rewardDebt[account] = earned;
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + (
            ((block.timestamp - lastUpdateTime) * rewardRatePerSecond * PRECISION) / totalStaked
        );
    }

    function _earned(address account) internal view returns (uint256) {
        return (
            (stakes[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / PRECISION
        ) + rewardDebt[account];
    }

    function earned(address account) public view returns (uint256) {
        return _earned(account);
    }

    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        
        totalStaked += amount;
        stakes[msg.sender] += amount;
        
        require(stakingToken.transferFrom(msg.sender, address(this), amount), "Stake failed");
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        require(stakes[msg.sender] >= amount, "Not enough staked");
        
        totalStaked -= amount;
        stakes[msg.sender] -= amount;
        
        require(stakingToken.transfer(msg.sender, amount), "Withdraw failed");
        emit Withdrawn(msg.sender, amount);
    }

    function claimReward() external nonReentrant updateReward(msg.sender) {
        uint256 reward = rewardDebt[msg.sender];
        require(reward > 0, "No rewards");
        
        rewardDebt[msg.sender] = 0;
        require(rewardToken.transfer(msg.sender, reward), "Reward transfer failed");
        emit RewardClaimed(msg.sender, reward);
    }

    function setRewardRate(uint256 _rate) external onlyOwner {
        require(_rate > 0, "Invalid rate");
        rewardRatePerSecond = _rate;
        emit RateUpdated(_rate);
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 balance = stakingToken.balanceOf(address(this));
        require(balance > 0, "No tokens");
        require(stakingToken.transfer(owner(), balance), "Emergency withdraw failed");
    }
}
