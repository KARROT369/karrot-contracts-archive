// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IDex {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}

contract KarrotDexAggregator {
    address public owner;
    mapping(string => address) public dexRouters;

    event DexAdded(string name, address router);
    event TokensSwapped(address indexed user, uint amountIn, uint amountOut, string dexUsed);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function addDex(string calldata name, address router) external onlyOwner {
        dexRouters[name] = router;
        emit DexAdded(name, router);
    }

    function getBestDex(address[] calldata path, uint amountIn) public view returns (string memory bestDex, uint bestAmountOut) {
        bestAmountOut = 0;
        bestDex = "";

        for (uint i = 0; i < dexList.length; i++) {
            address router = dexRouters[dexList[i]];
            if (router == address(0)) continue;

            try IDex(router).getAmountsOut(amountIn, path) returns (uint[] memory amounts) {
                if (amounts[amounts.length - 1] > bestAmountOut) {
                    bestAmountOut = amounts[amounts.length - 1];
                    bestDex = dexList[i];
                }
            } catch {}
        }
    }

    string[] public dexList;

    function registerDex(string calldata name, address router) external onlyOwner {
        dexRouters[name] = router;
        dexList.push(name);
        emit DexAdded(name, router);
    }

    function swapTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        uint deadline
    ) external returns (uint amountOut, string memory dexUsed) {
        require(path.length >= 2, "Invalid path");

        (dexUsed, amountOut) = getBestDex(path, amountIn);
        require(dexRouters[dexUsed] != address(0), "No DEX found");

        address router = dexRouters[dexUsed];

        require(
            IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn),
            "Transfer failed"
        );

        require(
            IERC20(path[0]).approve(router, amountIn),
            "Approval failed"
        );

        uint[] memory amounts = IDex(router).swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            msg.sender,
            deadline
        );

        emit TokensSwapped(msg.sender, amountIn, amounts[amounts.length - 1], dexUsed);
        return (amounts[amounts.length - 1], dexUsed);
    }
}

interface IERC20 {
    function transferFrom(address sender, address recipient, uint amount) external returns (bool);
    function approve(address spender, uint amount) external returns (bool);
}
