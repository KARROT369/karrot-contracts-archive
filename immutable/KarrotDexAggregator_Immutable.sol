// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Karrot DEX Aggregator - IMMUTABLE VERSION
/// @notice Adapter-based router with V2/V3 DEX support - NO ADMIN, NO PAUSE
/// @dev All parameters set at deployment. Cannot be changed. No owner.

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function decimals() external view returns (uint8);
}

interface IUniswapV2Router02 {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
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

contract KarrotDexAggregator_Immutable is ReentrancyGuard {
    // ============ Structs ============
    struct V2Router { string name; IUniswapV2Router02 router; bool active; }
    struct V3Router { string name; IUniswapV3Router router; bool active; }
    struct RelayerConfig { address relayer; bool active; uint256 maxDeadline; }
    
    // ============ Immutable State ============
    mapping(bytes32 => V2Router) public v2Routers;
    mapping(bytes32 => V3Router) public v3Routers;
    mapping(bytes32 => RelayerConfig) public relayers;
    
    mapping(bytes32 => mapping(bytes32 => bool)) public settled;
    mapping(bytes32 => uint256) public requestDeadlines;
    mapping(bytes32 => address) public requestTokens;
    mapping(bytes32 => uint256) public requestAmounts;
    
    uint256 public constant MAX_DEADLINE = 24 hours;
    uint256 public constant MIN_AMOUNT = 1000;
    
    // ============ Events ============
    event RouterSet(string indexed venue, address indexed router, bool isV3, bool active);
    event RelayerSet(string indexed relayerType, address indexed relayer, bool active);
    event V2Swap(string indexed venue, address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    event V3Swap(string indexed venue, address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    event ThorRequested(bytes32 indexed requestId, address indexed user, address tokenIn, uint256 amountIn, string chain, string memo, uint256 deadline);
    event ThorSettled(bytes32 indexed requestId, address indexed to, address tokenOut, uint256 amountOut);
    event ZKSwapRequested(bytes32 indexed requestId, address indexed user, address tokenIn, uint256 amountIn, string memo, uint256 deadline);
    event ZKSwapSettled(bytes32 indexed requestId, address indexed to, address tokenOut, uint256 amountOut);
    event XStocksRayRequested(bytes32 indexed requestId, address indexed user, address tokenIn, uint256 amountIn, uint256 deadline);
    event XStocksRaySettled(bytes32 indexed requestId, address indexed to, address tokenOut, uint256 amountOut);
    event XStocksJupRequested(bytes32 indexed requestId, address indexed user, address tokenIn, uint256 amountIn, uint256 deadline);
    event XStocksJupSettled(bytes32 indexed requestId, address indexed to, address tokenOut, uint256 amountOut);
    event RequestExpired(bytes32 indexed requestId, uint256 deadline, uint256 currentTime);
    event MinOutViolated(bytes32 indexed requestId, uint256 expected, uint256 actual);
    
    // ============ Modifiers ============
    modifier onlyRelayer(string memory relayerType) {
        bytes32 key = keccak256(bytes(relayerType));
        require(relayers[key].active, "Relayer not active");
        require(msg.sender == relayers[key].relayer, "Unauthorized relayer");
        _;
    }
    
    // ============ Constructor - ALL PARAMETERS SET HERE ============
    constructor(
        // V2 Routers
        string[] memory v2Names,
        address[] memory v2Addresses,
        // V3 Routers
        string[] memory v3Names,
        address[] memory v3Addresses,
        // Relayers
        address thorRelayer,
        address zkRelayer,
        address rayRelayer,
        address jupRelayer
    ) {
        require(v2Names.length == v2Addresses.length, "V2 arrays mismatch");
        require(v3Names.length == v3Addresses.length, "V3 arrays mismatch");
        
        // Set V2 routers
        for (uint i = 0; i < v2Names.length; i++) {
            require(v2Addresses[i] != address(0), "Invalid V2 router");
            v2Routers[keccak256(bytes(v2Names[i]))] = V2Router(v2Names[i], IUniswapV2Router02(v2Addresses[i]), true);
            emit RouterSet(v2Names[i], v2Addresses[i], false, true);
        }
        
        // Set V3 routers
        for (uint i = 0; i < v3Names.length; i++) {
            require(v3Addresses[i] != address(0), "Invalid V3 router");
            v3Routers[keccak256(bytes(v3Names[i]))] = V3Router(v3Names[i], IUniswapV3Router(v3Addresses[i]), true);
            emit RouterSet(v3Names[i], v3Addresses[i], true, true);
        }
        
        // Set relayers
        if (thorRelayer != address(0)) {
            relayers[keccak256("THOR")] = RelayerConfig(thorRelayer, true, MAX_DEADLINE);
            emit RelayerSet("THOR", thorRelayer, true);
        }
        if (zkRelayer != address(0)) {
            relayers[keccak256("ZK")] = RelayerConfig(zkRelayer, true, MAX_DEADLINE);
            emit RelayerSet("ZK", zkRelayer, true);
        }
        if (rayRelayer != address(0)) {
            relayers[keccak256("RAY")] = RelayerConfig(rayRelayer, true, MAX_DEADLINE);
            emit RelayerSet("RAY", rayRelayer, true);
        }
        if (jupRelayer != address(0)) {
            relayers[keccak256("JUP")] = RelayerConfig(jupRelayer, true, MAX_DEADLINE);
            emit RelayerSet("JUP", jupRelayer, true);
        }
    }
    
    // ============ Internal Helpers ============
    
    function _pull(IERC20 token, address from, uint256 amount) internal {
        require(token.transferFrom(from, address(this), amount), "Pull failed");
    }
    
    function _approveMax(IERC20 token, address spender) internal {
        uint256 currentAllowance = token.allowance(address(this), spender);
        if (currentAllowance < type(uint256).max / 2) {
            token.approve(spender, type(uint256).max);
        }
    }
    
    function _checkDeadline(uint256 deadline) internal view {
        require(deadline >= block.timestamp, "Deadline passed");
    }
    
    function _generateRequestId(
        address user,
        address tokenIn,
        uint256 amountIn,
        uint256 deadline,
        string memory extra
    ) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            user,
            tokenIn,
            amountIn,
            deadline,
            extra,
            block.number,
            block.timestamp
        ));
    }
    
    function _storeRequest(bytes32 requestId, address tokenIn, uint256 amountIn, uint256 deadline) internal {
        requestDeadlines[requestId] = deadline;
        requestTokens[requestId] = tokenIn;
        requestAmounts[requestId] = amountIn;
    }
    
    function _settleRequest(
        bytes32 requestId,
        address to,
        address tokenOut,
        uint256 amountOut,
        string memory relayerType
    ) internal nonReentrant {
        bytes32 relayerKey = keccak256(bytes(relayerType));
        require(block.timestamp <= requestDeadlines[requestId], "Request expired");
        require(!settled[relayerKey][requestId], "Already settled");
        settled[relayerKey][requestId] = true;
        require(IERC20(tokenOut).transfer(to, amountOut), "Transfer failed");
    }
    
    // ============ V2 Swap ============
    
    function swapV2(
        string calldata venue,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut,
        address[] calldata path,
        uint256 deadline
    ) external nonReentrant returns (uint256 amountOut) {
        require(amountIn >= MIN_AMOUNT, "Amount too small");
        _checkDeadline(deadline);
        
        V2Router memory r = v2Routers[keccak256(bytes(venue))];
        require(r.active, "V2 router inactive");
        
        _pull(IERC20(tokenIn), msg.sender, amountIn);
        _approveMax(IERC20(tokenIn), address(r.router));
        
        uint[] memory amounts = r.router.swapExactTokensForTokens(
            amountIn,
            minOut,
            path,
            msg.sender,
            deadline
        );
        
        amountOut = amounts[amounts.length - 1];
        emit V2Swap(venue, msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }
    
    // ============ V3 Swap ============
    
    function swapV3(
        string calldata venue,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut,
        uint24 fee,
        uint256 deadline
    ) external nonReentrant returns (uint256 amountOut) {
        require(amountIn >= MIN_AMOUNT, "Amount too small");
        _checkDeadline(deadline);
        
        V3Router memory r = v3Routers[keccak256(bytes(venue))];
        require(r.active, "V3 router inactive");
        
        _pull(IERC20(tokenIn), msg.sender, amountIn);
        _approveMax(IERC20(tokenIn), address(r.router));
        
        IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: msg.sender,
            deadline: deadline,
            amountIn: amountIn,
            amountOutMinimum: minOut,
            sqrtPriceLimitX96: 0
        });
        
        amountOut = r.router.exactInputSingle(params);
        emit V3Swap(venue, msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }
    
    // ============ THORChain Relayer ============
    
    function requestThorSwap(
        address tokenIn,
        uint256 amountIn,
        string calldata chain,
        string calldata memo,
        uint256 deadline
    ) external nonReentrant returns (bytes32 requestId) {
        require(amountIn >= MIN_AMOUNT, "Amount too small");
        _checkDeadline(deadline);
        
        RelayerConfig memory config = relayers[keccak256("THOR")];
        require(config.active, "THOR relayer not active");
        
        _pull(IERC20(tokenIn), msg.sender, amountIn);
        
        requestId = _generateRequestId(msg.sender, tokenIn, amountIn, deadline, abi.encode(chain, memo));
        _storeRequest(requestId, tokenIn, amountIn, deadline);
        
        emit ThorRequested(requestId, msg.sender, tokenIn, amountIn, chain, memo, deadline);
    }
    
    function settleThorSwap(
        bytes32 requestId,
        address to,
        address tokenOut,
        uint256 amountOut
    ) external nonReentrant onlyRelayer("THOR") {
        _settleRequest(requestId, to, tokenOut, amountOut, "THOR");
        emit ThorSettled(requestId, to, tokenOut, amountOut);
    }
    
    // ============ ZK Relayer ============
    
    function requestZKSwap(
        address tokenIn,
        uint256 amountIn,
        string calldata memo,
        uint256 deadline
    ) external nonReentrant returns (bytes32 requestId) {
        require(amountIn >= MIN_AMOUNT, "Amount too small");
        _checkDeadline(deadline);
        
        RelayerConfig memory config = relayers[keccak256("ZK")];
        require(config.active, "ZK relayer not active");
        
        _pull(IERC20(tokenIn), msg.sender, amountIn);
        
        requestId = _generateRequestId(msg.sender, tokenIn, amountIn, deadline, bytes(memo));
        _storeRequest(requestId, tokenIn, amountIn, deadline);
        
        emit ZKSwapRequested(requestId, msg.sender, tokenIn, amountIn, memo, deadline);
    }
    
    function settleZKSwap(
        bytes32 requestId,
        address to,
        address tokenOut,
        uint256 amountOut
    ) external nonReentrant onlyRelayer("ZK") {
        _settleRequest(requestId, to, tokenOut, amountOut, "ZK");
        emit ZKSwapSettled(requestId, to, tokenOut, amountOut);
    }
    
    // ============ xStocks Raydium Relayer ============
    
    function requestXStocksRaySwap(
        address tokenIn,
        uint256 amountIn,
        uint256 deadline
    ) external nonReentrant returns (bytes32 requestId) {
        require(amountIn >= MIN_AMOUNT, "Amount too small");
        _checkDeadline(deadline);
        
        RelayerConfig memory config = relayers[keccak256("RAY")];
        require(config.active, "RAY relayer not active");
        
        _pull(IERC20(tokenIn), msg.sender, amountIn);
        
        requestId = _generateRequestId(msg.sender, tokenIn, amountIn, deadline, "RAY");
        _storeRequest(requestId, tokenIn, amountIn, deadline);
        
        emit XStocksRayRequested(requestId, msg.sender, tokenIn, amountIn, deadline);
    }
    
    function settleXStocksRaySwap(
        bytes32 requestId,
        address to,
        address tokenOut,
        uint256 amountOut
    ) external nonReentrant onlyRelayer("RAY") {
        _settleRequest(requestId, to, tokenOut, amountOut, "RAY");
        emit XStocksRaySettled(requestId, to, tokenOut, amountOut);
    }
    
    // ============ xStocks Jupiter Relayer ============
    
    function requestXStocksJupSwap(
        address tokenIn,
        uint256 amountIn,
        uint256 deadline
    ) external nonReentrant returns (bytes32 requestId) {
        require(amountIn >= MIN_AMOUNT, "Amount too small");
        _checkDeadline(deadline);
        
        RelayerConfig memory config = relayers[keccak256("JUP")];
        require(config.active, "JUP relayer not active");
        
        _pull(IERC20(tokenIn), msg.sender, amountIn);
        
        requestId = _generateRequestId(msg.sender, tokenIn, amountIn, deadline, "JUP");
        _storeRequest(requestId, tokenIn, amountIn, deadline);
        
        emit XStocksJupRequested(requestId, msg.sender, tokenIn, amountIn, deadline);
    }
    
    function settleXStocksJupSwap(
        bytes32 requestId,
        address to,
        address tokenOut,
        uint256 amountOut
    ) external nonReentrant onlyRelayer("JUP") {
        _settleRequest(requestId, to, tokenOut, amountOut, "JUP");
        emit XStocksJupSettled(requestId, to, tokenOut, amountOut);
    }
    
    // ============ Emergency Functions - NONE (Immutable) ============
    // No recoverTokens - if tokens get stuck, they stay stuck
    // No pause - contract always operates
    // No admin - no one can change anything
}
