// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Verifier.sol";

contract Unlocker is Verifier {
    address public owner;
    mapping(bytes32 => bool) public usedNullifiers;

    event Unlock(address indexed user, string symbol, uint256 amount, bytes32 burnId);

    constructor() {
        owner = msg.sender;
    }

    function unlockWithZKProof(
        address user,
        string memory symbol,
        uint256 amount,
        bytes32 burnId,
        uint[2] memory a,
        uint[2][2] memory b,
        uint[2] memory c,
        uint[] memory input
    ) external {
        require(!usedNullifiers[burnId], "Burn ID already processed");

        bool success = verifyProof(a, b, c, input);
        require(success, "Invalid zk proof");

        usedNullifiers[burnId] = true;

        emit Unlock(user, symbol, amount, burnId);
    }
}
