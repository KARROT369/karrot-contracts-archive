// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IERC20 {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns(uint256);
}

contract Ncelbi2Staking is ReentrancyGuard, Ownable {
    IERC20 public immutable token;
    
    struct Stake {
        uint256 amount;
        uint256 timestamp;
        uint256 rewardDebt;
    }

    mapping(address => Stake) public stakes;
    uint256 public rewardRatePerSecond;
    uint256 public totalStaked;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);
    event RateUpdated(uint256 newRate);

    constructor(address _token, uint256 _rewardRatePerSecond) Ownable(msg.sender) {
        require(_token != address(0), "Invalid token");
        require(_rewardRatePerSecond > 0, "Invalid rate");
        token = IERC20(_token);
        rewardRatePerSecond = _rewardRatePerSecond;
    }

    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot stake zero");

        Stake storage user = stakes[msg.sender];
        _updateRewards(msg.sender);

        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        user.amount += amount;
        totalStaked += amount;
        user.timestamp = block.timestamp;
        
        emit Staked(msg.sender, amount);
    }

    function _updateRewards(address userAddr) internal {
        Stake storage user = stakes[userAddr];
        if (user.amount > 0 && block.timestamp > user.timestamp) {
            uint256 timeElapsed = block.timestamp - user.timestamp;
            uint256 reward = (timeElapsed * rewardRatePerSecond * user.amount) / 1e18;
            user.rewardDebt += reward;
        }
        user.timestamp = block.timestamp;
    }

    function claim() external nonReentrant {
        _updateRewards(msg.sender);
        uint256 reward = stakes[msg.sender].rewardDebt;
        require(reward > 0, "No rewards");
        
        stakes[msg.sender].rewardDebt = 0;
        require(token.transfer(msg.sender, reward), "Reward transfer failed");
        emit RewardPaid(msg.sender, reward);
    }

    function withdraw(uint256 amount) external nonReentrant {
        Stake storage user = stakes[msg.sender];
        require(user.amount >= amount, "Insufficient balance");
        require(amount > 0, "Cannot withdraw 0");
        
        _updateRewards(msg.sender);

        user.amount -= amount;
        totalStaked -= amount;
        require(token.transfer(msg.sender, amount), "Withdraw failed");
        emit Withdrawn(msg.sender, amount);
    }

    function updateRewardRate(uint256 newRate) external onlyOwner {
        require(newRate > 0, "Invalid rate");
        rewardRatePerSecond = newRate;
        emit RateUpdated(newRate);
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "No tokens");
        require(token.transfer(owner(), balance), "Emergency withdraw failed");
    }

    function tokenBalance() public view returns (uint256) {
        return token.balanceOf(address(this));
    }
}
