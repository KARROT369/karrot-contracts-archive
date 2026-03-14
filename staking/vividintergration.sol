// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IKarrotToken {
    function mint(address to, uint256 amount) external;
}

/**
 * @title VividIntegration
 * @notice Integration between Vivid token signals and Karrot rewards
 */
contract VividIntegration is Ownable, ReentrancyGuard {
    address public vividToken;
    address public karrotToken;
    address public fusion;
    uint256 public boostDenominator;
    uint256 public constant MAX_DENOMINATOR = 1000000;

    event SignalBoosted(address indexed user, uint256 karrotAmount, uint256 boostAmount);
    event DenominatorUpdated(uint256 newDenominator);
    event TokensUpdated(address indexed vivid, address indexed karrot, address indexed fusion);

    constructor(address _vivid, address _karrot, address _fusion) Ownable(msg.sender) {
        require(_vivid != address(0), "Invalid vivid");
        require(_karrot != address(0), "Invalid karrot");
        require(_fusion != address(0), "Invalid fusion");
        
        vividToken = _vivid;
        karrotToken = _karrot;
        fusion = _fusion;
        boostDenominator = 1000;
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

        uint256 boost = (karrotAmount * vividBalance) / boostDenominator;
        IKarrotToken(karrotToken).mint(user, boost);
        
        emit SignalBoosted(user, karrotAmount, boost);
    }

    function updateDenominator(uint256 newDenominator) external onlyOwner {
        require(newDenominator > 0, "Invalid denominator");
        require(newDenominator <= MAX_DENOMINATOR, "Denominator too high");
        boostDenominator = newDenominator;
        emit DenominatorUpdated(newDenominator);
    }

    function updateTokens(address _vivid, address _karrot, address _fusion) external onlyOwner {
        require(_vivid != address(0), "Invalid vivid");
        require(_karrot != address(0), "Invalid karrot");
        require(_fusion != address(0), "Invalid fusion");
        
        vividToken = _vivid;
        karrotToken = _karrot;
        fusion = _fusion;
        emit TokensUpdated(_vivid, _karrot, _fusion);
    }
}
