// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IKarrotToken {
    function mint(address to, uint256 amount) external;
    function burnFrom(address account, uint256 amount) external;
}

contract VividIntegration is Ownable, ReentrancyGuard {
    address public vividToken;
    address public karrotToken;
    address public fusion;
    uint256 public constant BOOST_DIVISOR = 1000;
    uint256 public maxBoostPercent = 100; // Max 100% boost

    event SignalBoosted(address indexed user, uint256 karrotAmount, uint256 boostAmount);
    event TokensUpdated(address indexed vivid, address indexed karrot);
    event FusionUpdated(address indexed fusion);

    constructor(address _vivid, address _karrot, address _fusion) Ownable(msg.sender) {
        require(_vivid != address(0), "Invalid vivid token");
        require(_karrot != address(0), "Invalid karrot token");
        require(_fusion != address(0), "Invalid fusion");
        
        vividToken = _vivid;
        karrotToken = _karrot;
        fusion = _fusion;
    }

    modifier onlyFusion() {
        require(msg.sender == fusion, "Only Fusion");
        _;
    }

    function applySignalBoost(address user, uint256 karrotAmount) external onlyFusion nonReentrant {
        require(user != address(0), "Invalid user");
        require(karrotAmount > 0, "Amount must be > 0");
        
        uint256 vividBalance = IERC20(vividToken).balanceOf(user);
        require(vividBalance > 0, "No vivid signal");

        uint256 rawBoost = (karrotAmount * vividBalance) / BOOST_DIVISOR;
        uint256 maxBoost = (karrotAmount * maxBoostPercent) / 100;
        uint256 boost = rawBoost > maxBoost ? maxBoost : rawBoost;
        
        IKarrotToken(karrotToken).mint(user, boost);
        emit SignalBoosted(user, karrotAmount, boost);
    }

    function setTokens(address _vivid, address _karrot) external onlyOwner {
        require(_vivid != address(0), "Invalid vivid");
        require(_karrot != address(0), "Invalid karrot");
        vividToken = _vivid;
        karrotToken = _karrot;
        emit TokensUpdated(_vivid, _karrot);
    }

    function setFusion(address _fusion) external onlyOwner {
        require(_fusion != address(0), "Invalid fusion");
        fusion = _fusion;
        emit FusionUpdated(_fusion);
    }

    function setMaxBoostPercent(uint256 _percent) external onlyOwner {
        require(_percent <= 1000, "Max 1000%");
        maxBoostPercent = _percent;
    }
}
