// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract KarrotEscrow {
    address public oracle;
    address public owner;

    mapping(bytes32 => bool) public processedProofs;

    event AssetLocked(address indexed user, bytes32 lockHash, string assetSymbol, uint amount);
    event AssetReleased(address indexed user, string assetSymbol, uint amount);

    modifier onlyOracle() {
        require(msg.sender == oracle, "Not authorized");
        _;
    }

    constructor(address _oracle) {
        oracle = _oracle;
        owner = msg.sender;
    }

    function submitLockProof(bytes calldata zkOrMultisigProof, string calldata assetSymbol, uint amount) external {
        bytes32 lockHash = keccak256(zkOrMultisigProof);
        require(!processedProofs[lockHash], "Proof already processed");

        processedProofs[lockHash] = true;
        emit AssetLocked(msg.sender, lockHash, assetSymbol, amount);
        // pxAsset mint logic handled off-chain or by listener
    }

    function burnPxAssetAndRelease(string calldata assetSymbol, uint amount) external onlyOracle {
        emit AssetReleased(msg.sender, assetSymbol, amount);
        // Signal unlock back to source chain
    }
}
