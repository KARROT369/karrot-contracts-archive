// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IERC20 {
  function balanceOf(address) external view returns (uint256);
  function burn(uint256) external;
  function transfer(address, uint256) external returns (bool);
}

contract BurnController is ReentrancyGuard, Ownable {
  address public burnAddress = 0x0000000000000000000000000000000000000369;
  mapping(address => bool) public allowedTokens;

  event TokenAllowed(address indexed token, bool allowed);
  event BurnExecuted(address indexed token, uint256 amount, uint256 ts, string method);

  constructor() Ownable(msg.sender) {}

  function setAllowedToken(address token, bool allow) external onlyOwner {
    require(token != address(0), "Invalid token");
    allowedTokens[token] = allow;
    emit TokenAllowed(token, allow);
  }

  function burnToken(address token, uint256 amount) external nonReentrant onlyOwner {
    require(token != address(0), "Invalid token");
    require(amount > 0, "Amount must be > 0");
    require(allowedTokens[token], "Token not allowed");

    // Try burn() first, fallback to transfer to burn address
    try IERC20(token).burn(amount) {
      emit BurnExecuted(token, amount, block.timestamp, "burn");
    } catch {
      require(IERC20(token).transfer(burnAddress, amount), "Transfer failed");
      emit BurnExecuted(token, amount, block.timestamp, "transfer");
    }
  }

  function getTokenBalance(address token) external view returns (uint256) {
    return IERC20(token).balanceOf(address(this));
  }
}
