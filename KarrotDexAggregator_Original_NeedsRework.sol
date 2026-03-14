// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Karrot DEX Aggregator — Modular Routing (V2 DEX | V3 | Thor | ZK | xStocks Ray | xStocks Jup)
/// @notice Adapter-based router with off-chain quoting and relayer bridges for Solana xStocks
/// @dev On-chain enforces slippage (minOut), settlement via relayers

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface IUniswapV2Router02 {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

interface IUniswapV3Router {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

abstract contract Ownable {
    address public owner;
    modifier onlyOwner() { require(msg.sender == owner, "not owner"); _; }
    event OwnershipTransferred(address indexed from, address indexed to);
    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}

contract KarrotDexAggregator is Ownable {
    /*---------- Router Structs ----------*/
    struct V2Router { string name; IUniswapV2Router02 router; bool active; }
    struct V3Router { string name; IUniswapV3Router router; bool active; }

    mapping(bytes32 => V2Router) public v2Routers;
    mapping(bytes32 => V3Router) public v3Routers;

    /*---------- Relayer Addresses ----------*/
    address public thorRelayer;
    address public zkRelayer;
    address public xStocksRayRelayer;
    address public xStocksJupRelayer;

    mapping(bytes32 => bool) public thorSettled;
    mapping(bytes32 => bool) public zkSettled;
    mapping(bytes32 => bool) public xStocksRaySettled;
    mapping(bytes32 => bool) public xStocksJupSettled;

    /*---------- Events ----------*/
    event RouterSet(string venue, address router, bool isV3, bool active);
    event V2Swap(string indexed venue, address user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    event V3Swap(string indexed venue, address user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    event ThorRequested(bytes32 requestId, address user, address tokenIn, uint256 amountIn, string chain, string memo);
    event ThorSettled(bytes32 requestId, address to, address tokenOut, uint256 amountOut);
    event ZKSwapRequested(bytes32 requestId, address user, address tokenIn, uint256 amountIn, string memo);
    event ZKSwapSettled(bytes32 requestId, address to, address tokenOut, uint256 amountOut);
    event XStocksRayRequested(bytes32 requestId, address user, address tokenIn, uint256 amountIn);
    event XStocksRaySettled(bytes32 requestId, address to, uint256 amountOut);
    event XStocksJupRequested(bytes32 requestId, address user, address tokenIn, uint256 amountIn);
    event XStocksJupSettled(bytes32 requestId, address to, uint256 amountOut);

    /*---------- Admin ----------*/
    function setV2Router(string calldata name, address router, bool active) external onlyOwner {
        v2Routers[keccak256(bytes(name))] = V2Router(name, IUniswapV2Router02(router), active);
        emit RouterSet(name, router, false, active);
    }

    function setV3Router(string calldata name, address router, bool active) external onlyOwner {
        v3Routers[keccak256(bytes(name))] = V3Router(name, IUniswapV3Router(router), active);
        emit RouterSet(name, router, true, active);
    }

    function setThorRelayer(address r) external onlyOwner { thorRelayer = r; }
    function setZKRelayer(address r) external onlyOwner { zkRelayer = r; }
    function setXStocksRayRelayer(address r) external onlyOwner { xStocksRayRelayer = r; }
    function setXStocksJupRelayer(address r) external onlyOwner { xStocksJupRelayer = r; }

    /*---------- Internal Helpers ----------*/
    function _pull(IERC20 t, address from, uint256 amt) internal {
        require(t.transferFrom(from, address(this), amt), "pull fail");
    }

    function _approveMax(IERC20 t, address router) internal {
        if (t.allowance(address(this), router) == 0) {
            t.approve(router, type(uint256).max);
        }
    }

    /*---------- Swap Functions ----------*/
    function swapV2(
        string calldata venue,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut,
        address[] calldata path,
        uint256 deadline
    ) external returns (uint256 amountOut) {
        V2Router memory r = v2Routers[keccak256(bytes(venue))];
        require(r.active, "inactive V2");
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        _approveMax(IERC20(tokenIn), address(r.router));
        uint[] memory out = r.router.swapExactTokensForTokens(amountIn, minOut, path, msg.sender, deadline);
        amountOut = out[out.length - 1];
        emit V2Swap(venue, msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    function swapV3(
        string calldata venue,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut,
        uint24 fee,
        uint256 deadline
    ) external returns (uint256 amountOut) {
        V3Router memory r = v3Routers[keccak256(bytes(venue))];
        require(r.active, "inactive V3");
        _pull(IERC20(tokenIn), msg.sender, amountIn);
        _approveMax(IERC20(tokenIn), address(r.router));
        IUniswapV3Router.ExactInputSingleParams memory p = IUniswapV3Router.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: msg.sender,
            deadline: deadline,
            amountIn: amountIn,
            amountOutMinimum: minOut,
            sqrtPriceLimitX96: 0
        });
        amountOut = r.router.exactInputSingle(p);
        emit V3Swap(venue, msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    /*---------- Thor Relayer ----------*/
    function requestThorSwap(
        address tokenIn,
        uint256 amountIn,
        string calldata chain,
        string calldata memo
    ) external returns (bytes32 requestId) {
        _pull(IERC20(tokenIn), msg.sender, amountIn);
        requestId = keccak256(abi.encode(msg.sender, tokenIn, amountIn, chain, memo, block.number));
        emit ThorRequested(requestId, msg.sender, tokenIn, amountIn, chain, memo);
    }

    function settleThorSwap(
        bytes32 requestId,
        address to,
        address tokenOut,
        uint256 amountOut,
        bytes calldata proof
    ) external {
        require(msg.sender == thorRelayer, "unauth");
        require(!thorSettled[requestId], "settled");
        thorSettled[requestId] = true;
        require(IERC20(tokenOut).transfer(to, amountOut), "transfer fail");
        emit ThorSettled(requestId, to, tokenOut, amountOut);
    }

    /*---------- ZK Relayer ----------*/
    function requestZKSwap(address tokenIn, uint256 amountIn, string calldata memo)
        external returns (bytes32 requestId)
    {
        _pull(IERC20(tokenIn), msg.sender, amountIn);
        requestId = keccak256(abi.encode(msg.sender, tokenIn, amountIn, memo, block.number));
        emit ZKSwapRequested(requestId, msg.sender, tokenIn, amountIn, memo);
    }

    function settleZKSwap(
        bytes32 requestId,
        address to,
        address tokenOut,
        uint256 amountOut,
        bytes calldata proof
    ) external {
        require(msg.sender == zkRelayer, "unauth");
        require(!zkSettled[requestId], "settled");
        zkSettled[requestId] = true;
        require(IERC20(tokenOut).transfer(to, amountOut), "transfer fail");
        emit ZKSwapSettled(requestId, to, tokenOut, amountOut);
    }

    /*---------- xStocks Raydium Relayer ----------*/
    function requestXStocksRaySwap(address tokenIn, uint256 amountIn)
        external returns (bytes32 requestId)
    {
        _pull(IERC20(tokenIn), msg.sender, amountIn);
        requestId = keccak256(abi.encode(msg.sender, tokenIn, amountIn, "RAY", block.number));
        emit XStocksRayRequested(requestId, msg.sender, tokenIn, amountIn);
    }

    function settleXStocksRaySwap(bytes32 requestId, address to, uint256 amountOut) external {
        require(msg.sender == xStocksRayRelayer, "unauth");
        require(!xStocksRaySettled[requestId], "settled");
        xStocksRaySettled[requestId] = true;
        require(IERC20(to).transfer(to, amountOut), "transfer fail"); // assuming `to` token is xStock
        emit XStocksRaySettled(requestId, to, amountOut);
    }

    /*---------- xStocks Jupiter Relayer ----------*/
    function requestXStocksJupSwap(address tokenIn, uint256 amountIn)
        external returns (bytes32 requestId)
    {
        _pull(IERC20(tokenIn), msg.sender, amountIn);
        requestId = keccak256(abi.encode(msg.sender, tokenIn, amountIn, "JUP", block.number));
        emit XStocksJupRequested(requestId, msg.sender, tokenIn, amountIn);
    }

    function settleXStocksJupSwap(bytes32 requestId, address to, uint256 amountOut) external {
        require(msg.sender == xStocksJupRelayer, "unauth");
        require(!xStocksJupSettled[requestId], "settled");
        xStocksJupSettled[requestId] = true;
        require(IERC20(to).transfer(to, amountOut), "transfer fail"); // assuming to is xStock token
        emit XStocksJupSettled(requestId, to, amountOut);
    }
}
