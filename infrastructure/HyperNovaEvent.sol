// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IKarrot.sol";

contract EntropyEngine {
    IKarrot public karrot;
    address public fusionEngine;

    constructor(address _karrot, address _fusionEngine) {
        karrot = IKarrot(_karrot);
        fusionEngine = _fusionEngine;
    }

    modifier onlyFusion() {
        require(msg.sender == fusionEngine, "Only Sigma Fusion Engine.");
        _;
    }

    function applyDecay(address user) external onlyFusion {
        uint balance = karrot.balanceOf(user);
        uint decayRate = (block.timestamp % 5) + 1;
        uint decayAmount = (balance * decayRate) / 100;

        karrot.burnFrom(user, decayAmount);
    }
}
