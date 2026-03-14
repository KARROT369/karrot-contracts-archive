// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IKarrot.sol";

contract EntropyEngine is Ownable {
    IKarrot public karrot;
    address public fusionEngine;
    
    uint256 public constant MIN_DECAY = 1;
    uint256 public constant MAX_DECAY = 5;
    
    event DecayApplied(address indexed user, uint256 decayAmount, uint256 decayRate);
    event FusionEngineUpdated(address indexed newEngine);
    event DecayPaused(bool paused);
    
    bool public paused;

    constructor(address _karrot, address _fusionEngine) Ownable(msg.sender) {
        require(_karrot != address(0), "Invalid karrot");
        require(_fusionEngine != address(0), "Invalid fusion engine");
        karrot = IKarrot(_karrot);
        fusionEngine = _fusionEngine;
    }

    modifier onlyFusion() {
        require(msg.sender == fusionEngine, "Only Sigma Fusion Engine.");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Decay is paused");
        _;
    }

    function applyDecay(address user) external onlyFusion whenNotPaused {
        require(user != address(0), "Invalid user");
        uint256 balance = karrot.balanceOf(user);
        require(balance > 0, "Zero balance");
        
        // Use blockhash for deterministic pseudo-randomness (miners can't easily manipulate for single block)
        uint256 randomSeed = uint256(blockhash(block.number - 1));
        uint256 decayRate = (randomSeed % (MAX_DECAY - MIN_DECAY + 1)) + MIN_DECAY;
        uint256 decayAmount = (balance * decayRate) / 100;
        
        require(decayAmount <= balance, "Decay exceeds balance");

        karrot.burnFrom(user, decayAmount);
        emit DecayApplied(user, decayAmount, decayRate);
    }

    function setFusionEngine(address _fusionEngine) external onlyOwner {
        require(_fusionEngine != address(0), "Invalid address");
        fusionEngine = _fusionEngine;
        emit FusionEngineUpdated(_fusionEngine);
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit DecayPaused(_paused);
    }
}
