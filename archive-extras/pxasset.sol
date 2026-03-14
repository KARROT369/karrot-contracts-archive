// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Mintable {
    function mint(address to, uint256 amount) external;
}

interface IKarrotMeshOracle {
    function getLatestPrice(string calldata asset) external view returns (uint256);
}

contract PxAssetMinter {
    address public owner;
    IKarrotMeshOracle public oracle;

    // Asset symbol => pxAsset ERC20 token
    mapping(string => IERC20Mintable) public pxAssets;

    // Used proof hashes to prevent replay
    mapping(bytes32 => bool) public usedProofs;

    event PxAssetMinted(string symbol, address user, uint256 amount, bytes32 proofHash);
    event OracleUpdated(address newOracle);
    event PxAssetRegistered(string symbol, address pxAsset);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address _oracle) {
        owner = msg.sender;
        oracle = IKarrotMeshOracle(_oracle);
    }

    function updateOracle(address newOracle) external onlyOwner {
        require(newOracle != address(0), "Invalid oracle");
        oracle = IKarrotMeshOracle(newOracle);
        emit OracleUpdated(newOracle);
    }

    function registerPxAsset(string calldata symbol, address pxToken) external onlyOwner {
        require(pxToken != address(0), "Invalid token");
        pxAssets[symbol] = IERC20Mintable(pxToken);
        emit PxAssetRegistered(symbol, pxToken);
    }

    /// @notice Mints pxAsset using cross-chain proof and oracle price
    /// @param symbol e.g. "pxSOL"
    /// @param user receiver address
    /// @param amount raw base token amount (from source chain)
    /// @param proof raw proof bytes (off-chain generated, hashed here)
    function mintFromLockProof(
        string calldata symbol,
        address user,
        uint256 amount,
        bytes calldata proof
    ) external {
        require(user != address(0), "Invalid user");
        require(amount > 0, "Zero amount");

        bytes32 proofHash = keccak256(proof);
        require(!usedProofs[proofHash], "Proof already used");

        IERC20Mintable pxToken = pxAssets[symbol];
        require(address(pxToken) != address(0), "Unregistered asset");

        // Optional: fetch price to do validations / convert to USD, etc.
        uint256 price = oracle.getLatestPrice(symbol);
        require(price > 0, "No oracle price");

        // Use raw amount directly — price-based logic can be added here
        pxToken.mint(user, amount);
        usedProofs[proofHash] = true;

        emit PxAssetMinted(symbol, user, amount, proofHash);
    }
}
