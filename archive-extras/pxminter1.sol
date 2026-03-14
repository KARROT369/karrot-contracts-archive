event PxAssetBurned(string symbol, address user, uint256 amount, bytes32 burnId);

function burnForUnlock(
    string calldata symbol,
    uint256 amount
) external {
    require(amount > 0, "Zero burn");

    IERC20Mintable pxToken = pxAssets[symbol];
    require(address(pxToken) != address(0), "Unknown pxAsset");

    // Burn from sender (token must implement a burnFrom or similar)
    // You can use OpenZeppelin ERC20Burnable interface
    pxToken.burnFrom(msg.sender, amount);

    // Burn ID for deduplication
    bytes32 burnId = keccak256(abi.encode(symbol, msg.sender, amount, block.timestamp, blockhash(block.number - 1)));

    emit PxAssetBurned(symbol, msg.sender, amount, burnId);
}
