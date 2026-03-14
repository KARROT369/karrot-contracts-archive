// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IKarrot.sol";

contract HyperNovaEvent {
    IKarrot public karrot;
    address public fusionEngine;

    constructor(address _karrot, address _fusionEngine) {
        karrot = IKarrot(_karrot);
        fusionEngine = _fusionEngine;
    }

    modifier onlyFusion() {
        require(msg.sender == fusionEngine, "Not Fusion Engine.");
        _;
    }

    function triggerEvent(bool mintInstead) external onlyFusion {
        uint novaAmount = (block.number % 1000) + 500;

        if (mintInstead) {
            karrot.mint(fusionEngine, novaAmount);
        } else {
            karrot.burn(novaAmount);
        }
    }
}
