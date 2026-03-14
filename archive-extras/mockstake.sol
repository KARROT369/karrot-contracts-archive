// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IERC20 {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
}

contract Ncelbi2Staking {
    IERC20 public immutable token;
    address public owner;
    uint256 public rewardRatePerSecond;

    struct Stake {
        uint256 amount;
        uint256 timestamp;
        uint256 rewardDebt;
    }

    mapping(address => Stake) public stakes;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address _token, uint256 _rewardRatePerSecond) {
        token = IERC20(_token);
        rewardRatePerSecond = _rewardRatePerSecond;
        owner = msg.sender;
    }

    function stake(uint256 amount) external {
        require(amount > 0, "Cannot stake zero");

        Stake storage user = stakes[msg.sender];
        _updateRewards(msg.sender);

        token.transferFrom(msg.sender, address(this), amount);
        user.amount += amount;
        user.timestamp = block.timestamp;
    }

    function _updateRewards(address userAddr) internal {
        Stake storage user = stakes[userAddr];
        if (user.amount > 0) {
            uint256 timeElapsed = block.timestamp - user.timestamp;
            uint256 reward = timeElapsed * rewardRatePerSecond * user.amount / 1e18;
            user.rewardDebt += reward;
        }
        user.timestamp = block.timestamp;
    }

    function claim() external {
        _updateRewards(msg.sender);
        uint256 reward = stakes[msg.sender].rewardDebt;
        require(reward > 0, "No rewards");
        stakes[msg.sender].rewardDebt = 0;

        token.transfer(msg.sender, reward);
    }

    function withdraw(uint256 amount) external {
        Stake storage user = stakes[msg.sender];
        require(user.amount >= amount, "Withdraw too much");
        _updateRewards(msg.sender);

        user.amount -= amount;
        token.transfer(msg.sender, amount);
    }

    function updateRewardRate(uint256 newRate) external onlyOwner {
        rewardRatePerSecond = newRate;
    }

    function emergencyWithdraw() external onlyOwner {
        token.transfer(owner, tokenBalance());
    }

    function tokenBalance() public view returns (uint256) {
        return address(token).balance;
    }
}
