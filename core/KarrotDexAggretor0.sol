// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Karrot DEX Aggregator v2 — PulseX, 9mm, Pancake (V2), Uniswap V3, ThorSwap relay
/// @notice Minimal gas, adapter-based routing. Oracle hints off-chain; on-chain checks minOut.
/// @dev This contract assumes off-chain quoting. On-chain we verify slippage via minOut.
/// @dev ThorSwap is handled via a relayer (off-chain) with on-chain settlement hook.

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function decimals() external view returns (uint8);
}

/* ---------- Uniswap V2-style (PulseX, 9mm, Pancake) ---------- */
interface IUniswapV2Router02 {
    function swapExactTokensForTokens(
        uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline
    ) external returns (uint[] memory amounts);
}

/* ---------- Uniswap V3 Router ---------- */
interface IUniswapV3Router {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;           // 500, 3000, 10000 etc
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96; // 0 for no limit
    }
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

/* ---------- ThorSwap Relayer Settlement ---------- */
interface IThorRelayer {
    /// off-chain executes cross-chain trade, then calls settle() with proof
    function verify(bytes calldata proof) external pure returns (bool);
}

/// @dev Minimal access control
abstract contract Ownable {
    address public owner;
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    modifier onlyOwner() { require(msg.sender == owner, "not owner"); _; }
    constructor() { owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    function transferOwnership(address n) external onlyOwner { require(n != address(0), "zero"); emit OwnershipTransferred(owner, n); owner = n; }
}

contract KarrotDexAggregator is Ownable {
    /* ---------- Routers ---------- */
    struct V2Router {
        string name;              // "PulseX" | "9mm" | "Pancake"
        IUniswapV2Router02 router;
        bool active;
    }

    struct V3Router {
        string name;              // "UniswapV3"
        IUniswapV3Router router;
        bool active;
    }

    mapping(bytes32 => V2Router) public v2Routers; // keccak256(name) => router
    mapping(bytes32 => V3Router) public v3Routers; // keccak256(name) => router

    /* ---------- ThorSwap relay ---------- */
    address public thorRelayer;               // trusted relayer addr (multisig/contract)
    mapping(bytes32 => bool) public thorSettled; // settlement ids
    event ThorRequested(bytes32 indexed requestId, address indexed user, address tokenIn, uint256 amountIn, string targetChain, string memo);
    event ThorSettled(bytes32 indexed requestId, address indexed to, address tokenOut, uint256 amountOut);

    /* ---------- Generic events ---------- */
    event V2Swap(string indexed venue, address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    event V3Swap(string indexed venue, address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    event RouterSet(string venue, address router, bool v3, bool active);

    /* ---------- Admin ---------- */
    function setV2Router(string calldata name, address router, bool active) external onlyOwner {
        bytes32 key = keccak256(bytes(name));
        v2Routers[key] = V2Router({ name: name, router: IUniswapV2Router02(router), active: active });
        emit RouterSet(name, router, false, active);
    }

    function setV3Router(string calldata name, address router, bool active) external onlyOwner {
        bytes32 key = keccak256(bytes(name));
        v3Routers[key] = V3Router({ name: name, router: IUniswapV3Router(router), active: active });
        emit RouterSet(name, router, true, active);
    }

    function setThorRelayer(address relayer) external onlyOwner { thorRelayer = relayer; }

    /* ---------- Internal helpers ---------- */
    function _pull(IERC20 t, address from, uint256 amt) internal {
        require(t.transferFrom(from, address(this), amt), "pull fail");
    }
    function _approveMax(IERC20 t, address router) internal {
        if (t.allowance(address(this), router) == 0) { t.approve(router, type(uint256).max); }
    }

    /* ---------- V2 Swap (PulseX / 9mm / Pancake) ---------- */
    function swapV2(
        string calldata venue,            // "PulseX" | "9mm" | "Pancake"
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut,
        address[] calldata path,
        uint256 deadline
    ) external returns (uint256 amountOut) {
        bytes32 key = keccak256(bytes(venue));
        V2Router memory r = v2Routers[key];
        require(r.active, "router inactive");

        IERC20 inT = IERC20(tokenIn);
        _pull(inT, msg.sender, amountIn);
        _approveMax(inT, address(r.router));

        uint[] memory amounts = r.router.swapExactTokensForTokens(
            amountIn, minOut, path, msg.sender, deadline
        );
        amountOut = amounts[amounts.length - 1];

        emit V2Swap(venue, msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    /* ---------- V3 Swap (Uniswap V3) ---------- */
    function swapV3(
        string calldata venue,            // "UniswapV3"
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut,
        uint24 fee,                       // 500 / 3000 / 10000
        uint256 deadline
    ) external returns (uint256 amountOut) {
        bytes32 key = keccak256(bytes(venue));
        V3Router memory r = v3Routers[key];
        require(r.active, "router inactive");

        IERC20 inT = IERC20(tokenIn);
        _pull(inT, msg.sender, amountIn);
        _approveMax(inT, address(r.router));

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

    /* ---------- ThorSwap (off-chain) request/settlement ---------- */
    /// @notice Emit an intent for ThorSwap cross-chain; off-chain relayer executes
    function requestThorSwap(
        address tokenIn,
        uint256 amountIn,
        string calldata targetChain,   // e.g. "BTC", "BNB", "ETH", "COSMOS"
        string calldata memo           // arbitrary routing memo for Thor
    ) external returns (bytes32 requestId) {
        _pull(IERC20(tokenIn), msg.sender, amountIn);
        // Funds remain here until relayer consumes/bridges via its flow
        requestId = keccak256(abi.encode(msg.sender, tokenIn, amountIn, targetChain, memo, block.number));
        emit ThorRequested(requestId, msg.sender, tokenIn, amountIn, targetChain, memo);
    }

    /// @notice Relayer settles (e.g. returning tokenOut after cross-chain swap)
    function settleThorSwap(
        bytes32 requestId,
        address to,
        address tokenOut,
        uint256 amountOut,
        bytes calldata proof
    ) external {
        require(msg.sender == thorRelayer, "not relayer");
        require(!thorSettled[requestId], "already settled");
        // optional: IThorRelayer(thorRelayer).verify(proof); // if relayer exposes verify
        thorSettled[requestId] = true;
        require(IERC20(tokenOut).transfer(to, amountOut), "transfer fail");
        emit ThorSettled(requestId, to, tokenOut, amountOut);
    }
}

