// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Karrot DEX Aggregator — Modular Routing (PulseX, LibertySwap, ZKSwap, Thor, Uniswap V3)
/// @notice Adapter-based, permissioned router with off-chain quoting
/// @dev Off-chain quoting with on-chain minOut safety. ZK/Thor handled via relayer

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface IUniswapV2Router02 {
    function swapExactTokensForTokens(
        uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline
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
    /* -------------------- ROUTER STRUCTS -------------------- */
    struct V2Router { string name; IUniswapV2Router02 router; bool active; }
    struct V3Router { string name; IUniswapV3Router router; bool active; }

    mapping(bytes32 => V2Router) public v2Routers;
    mapping(bytes32 => V3Router) public v3Routers;

    /* -------------------- RELAYER SYSTEM -------------------- */
    address public thorRelayer;
    address public zkRelayer;
    mapping(bytes32 => bool) public thorSettled;
    mapping(bytes32 => bool) public zkSettled;

    /* -------------------- EVENTS -------------------- */
    event RouterSet(string venue, address router, bool isV3, bool active);
    event V2Swap(string indexed venue, address user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    event V3Swap(string indexed venue, address user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    event ThorRequested(bytes32 requestId, address user, address tokenIn, uint256 amountIn, string chain, string memo);
    event ThorSettled(bytes32 requestId, address to, address tokenOut, uint256 amountOut);
    event ZKSwapRequested(bytes32 requestId, address user, address tokenIn, uint256 amountIn, string memo);
    event ZKSwapSettled(bytes32 requestId, address to, address tokenOut, uint256 amountOut);

    /* -------------------- ADMIN -------------------- */
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

    /* -------------------- INTERNAL HELPERS -------------------- */
    function _pull(IERC20 t, address from, uint amt) internal {
        require(t.transferFrom(from, address(this), amt), "pull fail");
    }
    function _approveMax(IERC20 t, address router) internal {
        if (t.allowance(address(this), router) == 0) {
            t.approve(router, type(uint256).max);
        }
    }

    /* -------------------- SWAP FUNCTIONS -------------------- */
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

    /* -------------------- RELAYER: Thor -------------------- */
    function requestThorSwap(address tokenIn, uint256 amountIn, string calldata chain, string calldata memo)
        external returns (bytes32 requestId)
    {
        _pull(IERC20(tokenIn), msg.sender, amountIn);
        requestId = keccak256(abi.encode(msg.sender, tokenIn, amountIn, chain, memo, block.number));
        emit ThorRequested(requestId, msg.sender, tokenIn, amountIn, chain, memo);
    }

    function settleThorSwap(bytes32 requestId, address to, address tokenOut, uint256 amountOut, bytes calldata proof) external {
        require(msg.sender == thorRelayer, "unauth");
        require(!thorSettled[requestId], "settled");
        thorSettled[requestId] = true;
        require(IERC20(tokenOut).transfer(to, amountOut), "transfer fail");
        emit ThorSettled(requestId, to, tokenOut, amountOut);
    }

    /* -------------------- RELAYER: ZK -------------------- */
    function requestZKSwap(address tokenIn, uint256 amountIn, string calldata memo)
        external returns (bytes32 requestId)
    {
        _pull(IERC20(tokenIn), msg.sender, amountIn);
        requestId = keccak256(abi.encode(msg.sender, tokenIn, amountIn, memo, block.number));
        emit ZKSwapRequested(requestId, msg.sender, tokenIn, amountIn, memo);
    }

    function settleZKSwap(bytes32 requestId, address to, address tokenOut, uint256 amountOut, bytes calldata proof) external {
        require(msg.sender == zkRelayer, "unauth");
        require(!zkSettled[requestId], "settled");
        zkSettled[requestId] = true;
        require(IERC20(tokenOut).transfer(to, amountOut), "transfer fail");
        emit ZKSwapSettled(requestId, to, tokenOut, amountOut);
    }
}
