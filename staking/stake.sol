// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
}

contract MockNcelbi2Staking {
    address public owner;
    IERC20 public ncelbi2Token;
    mapping(address => uint256) public stakedAmount;

    constructor(address _token) {
        owner = msg.sender;
        ncelbi2Token = IERC20(_token);
    }

    function stake(uint256 amount) public {
        require(amount > 0, "Cannot stake 0");
        require(ncelbi2Token.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        stakedAmount[msg.sender] += amount;
    }

    function withdraw(uint256 amount) public {
        require(stakedAmount[msg.sender] >= amount, "Insufficient staked");
        stakedAmount[msg.sender] -= amount;
        require(ncelbi2Token.transfer(msg.sender, amount), "Transfer failed");
    }
}
