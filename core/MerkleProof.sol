// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

interface ZkSnarkVerifier {
    function verify(uint256[] calldata proof, uint256[] calldata inputs, bytes32 vkId) external returns (bool);
}

contract CrossChainUnlock {
    bytes32 public trustedRoot;
    ZkSnarkVerifier public zkVerifier;
    mapping(bytes32 => bool) public processedBurnIds;

    event AssetUnlocked(address user, uint256 amount, bytes32 burnId);

    constructor(bytes32 _root, address _zkVerifier) {
        trustedRoot = _root;
        zkVerifier = ZkSnarkVerifier(_zkVerifier);
    }

    function unlockViaMerkle(
        address user,
        uint256 amount,
        bytes32 burnId,
        bytes32[] calldata merkleProof,
        bytes32 leaf
    ) external {
        require(!processedBurnIds[burnId], "Replay attack");
        require(MerkleProof.verify(merkleProof, trustedRoot, leaf), "Invalid proof");

        processedBurnIds[burnId] = true;
        emit AssetUnlocked(user, amount, burnId);
        // transfer logic ...
    }

    function unlockViaZk(
        address user,
        uint256 amount,
        bytes32 burnId,
        uint256[] calldata proof,
        uint256[] calldata inputs,
        bytes32 vkId
    ) external {
        require(!processedBurnIds[burnId], "Replay attack");
        bool ok = zkVerifier.verify(proof, inputs, vkId);
        require(ok, "zk proof invalid");

        processedBurnIds[burnId] = true;
        emit AssetUnlocked(user, amount, burnId);
        // transfer logic ...
    }
}
