// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract KarrotEscrow {
    address public oracle; // To approve minting
    address public owner;

    mapping(bytes32 => bool) public usedProofs;

    event AssetLocked(address indexed user, string assetSymbol, uint256 amount, bytes32 proofHash);
    event AssetBurned(address indexed user, string assetSymbol, uint256 amount);

    modifier onlyOracle() {
        require(msg.sender == oracle, "Not oracle");
        _;
    }

    constructor(address _oracle) {
        oracle = _oracle;
        owner = msg.sender;
    }

    function lockAsset(string calldata assetSymbol, uint256 amount, bytes calldata lockProof) external {
        bytes32 proofHash = keccak256(lockProof);
        require(!usedProofs[proofHash], "Proof already used");

        usedProofs[proofHash] = true;
        emit AssetLocked(msg.sender, assetSymbol, amount, proofHash);
        // Off-chain process listens, mints pxAsset
    }

    function burnWrappedAsset(string calldata assetSymbol, uint256 amount) external {
        emit AssetBurned(msg.sender, assetSymbol, amount);
        // Off-chain listener or bridge initiates unlock
    }

    function updateOracle(address _oracle) external {
        require(msg.sender == owner, "Not owner");
        oracle = _oracle;
    }
}
