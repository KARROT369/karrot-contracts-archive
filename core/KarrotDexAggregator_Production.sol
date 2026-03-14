// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Karrot DEX Aggregator - Production Modular Router
/// @notice Adapter-based router with V2/V3 DEX support, THORChain, ZK, and xStocks relayers
/// @dev Production: Fixed tokenOut parameter, reentrancy protection, deadline validation, emergency controls

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

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

contract KarrotDexAggregator is Ownable, ReentrancyGuard, Pausable {
    // ============ Structs ============
    struct V2Router { string name; IUniswapV2Router02 router; bool active; }
    struct V3Router { string name; IUniswapV3Router router; bool active; }
    struct RelayerConfig { address relayer; bool active; uint256 maxDeadline; }
    
    // ============ State ============
    mapping(bytes32 => V2Router) public v2Routers;
    mapping(bytes32 => V3Router) public v3Routers;
    
    mapping(bytes32 => RelayerConfig) public relayers; // keccak256("THOR"/"ZK"/"RAY"/"JUP") => config
    mapping(bytes32 => mapping(bytes32 => bool)) public settled; // relayerType => requestId => settled
    mapping(bytes32 => uint256) public requestDeadlines; // requestId => deadline
    mapping(bytes32 => address) public requestTokens; // requestId => tokenIn
    mapping(bytes32 => uint256) public requestAmounts; // requestId => amountIn
    
    uint256 public constant MAX_DEADLINE = 24 hours;
    uint256 public constant MIN_AMOUNT = 1000; // Minimum amount to prevent dust attacks
    
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
    
    // ============ Constructor ============
    constructor() {}
    
    // ============ Admin Functions ============
    
    /// @notice Set a V2 router
    function setV2Router(string calldata name, address router, bool active) external onlyOwner {
        require(router != address(0), "Invalid router");
        v2Routers[keccak256(bytes(name))] = V2Router(name, IUniswapV2Router02(router), active);
        emit RouterSet(name, router, false, active);
    }
    
    /// @notice Set a V3 router
    function setV3Router(string calldata name, address router, bool active) external onlyOwner {
        require(router != address(0), "Invalid router");
        v3Routers[keccak256(bytes(name))] = V3Router(name, IUniswapV3Router(router), active);
        emit RouterSet(name, router, true, active);
    }
    
    /// @notice Set a relayer
    function setRelayer(string calldata relayerType, address relayer, bool active) external onlyOwner {
        require(relayer != address(0), "Invalid relayer");
        relayers[keccak256(bytes(relayerType))] = RelayerConfig(relayer, active, MAX_DEADLINE);
        emit RelayerSet(relayerType, relayer, active);
    }
    
    /// @notice Pause/unpause contract
    function togglePause() external onlyOwner {
        paused() ? _unpause() : _pause();
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
    
    /// @notice Generate unique request ID
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
    
    /// @notice Store request data for settlement verification
    function _storeRequest(bytes32 requestId, address tokenIn, uint256 amountIn, uint256 deadline) internal {
        requestDeadlines[requestId] = deadline;
        requestTokens[requestId] = tokenIn;
        requestAmounts[requestId] = amountIn;
    }
    
    /// @notice Check and settle a request
    function _settleRequest(
        bytes32 requestId,
        address to,
        address tokenOut,
        uint256 amountOut,
        string memory relayerType
    ) internal nonReentrant {
        bytes32 relayerKey = keccak256(bytes(relayerType));
        
        // Check deadline
        require(block.timestamp <= requestDeadlines[requestId], "Request expired");
        
        // Check not already settled
        require(!settled[relayerKey][requestId], "Already settled");
        settled[relayerKey][requestId] = true;
        
        // FIX: Transfer tokenOut (not 'to' which was the bug!)
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
    ) external nonReentrant whenNotPaused returns (uint256 amountOut) {
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
    ) external nonReentrant whenNotPaused returns (uint256 amountOut) {
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
    ) external nonReentrant whenNotPaused returns (bytes32 requestId) {
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
    ) external nonReentrant whenNotPaused onlyRelayer("THOR") {
        _settleRequest(requestId, to, tokenOut, amountOut, "THOR");
        emit ThorSettled(requestId, to, tokenOut, amountOut);
    }
    
    // ============ ZK Relayer ============
    
    function requestZKSwap(
        address tokenIn,
        uint256 amountIn,
        string calldata memo,
        uint256 deadline
    ) external nonReentrant whenNotPaused returns (bytes32 requestId) {
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
    ) external nonReentrant whenNotPaused onlyRelayer("ZK") {
        _settleRequest(requestId, to, tokenOut, amountOut, "ZK");
        emit ZKSwapSettled(requestId, to, tokenOut, amountOut);
    }
    
    // ============ xStocks Raydium Relayer ============
    
    function requestXStocksRaySwap(
        address tokenIn,
        uint256 amountIn,
        uint256 deadline
    ) external nonReentrant whenNotPaused returns (bytes32 requestId) {
        require(amountIn >= MIN_AMOUNT, "Amount too small");
        _checkDeadline(deadline);
        
        RelayerConfig memory config = relayers[keccak256("RAY")];
        require(config.active, "RAY relayer not active");
        
        _pull(IERC20(tokenIn), msg.sender, amountIn);
        
        requestId = _generateRequestId(msg.sender, tokenIn, amountIn, deadline, "RAY");
        _storeRequest(requestId, tokenIn, amountIn, deadline);
        
        emit XStocksRayRequested(requestId, msg.sender, tokenIn, amountIn, deadline);
    }
    
    /// @notice Settle Raydium swap - FIX: Uses tokenOut parameter correctly
    function settleXStocksRaySwap(
        bytes32 requestId,
        address to,
        address tokenOut,
        uint256 amountOut
    ) external nonReentrant whenNotPaused onlyRelayer("RAY") {
        _settleRequest(requestId, to, tokenOut, amountOut, "RAY");
        emit XStocksRaySettled(requestId, to, tokenOut, amountOut);
    }
    
    // ============ xStocks Jupiter Relayer ============
    
    function requestXStocksJupSwap(
        address tokenIn,
        uint256 amountIn,
        uint256 deadline
    ) external nonReentrant whenNotPaused returns (bytes32 requestId) {
        require(amountIn >= MIN_AMOUNT, "Amount too small");
        _checkDeadline(deadline);
        
        RelayerConfig memory config = relayers[keccak256("JUP")];
        require(config.active, "JUP relayer not active");
        
        _pull(IERC20(tokenIn), msg.sender, amountIn);
        
        requestId = _generateRequestId(msg.sender, tokenIn, amountIn, deadline, "JUP");
        _storeRequest(requestId, tokenIn, amountIn, deadline);
        
        emit XStocksJupRequested(requestId, msg.sender, tokenIn, amountIn, deadline);
    }
    
    /// @notice Settle Jupiter swap - FIX: Uses tokenOut parameter correctly
    function settleXStocksJupSwap(
        bytes32 requestId,
        address to,
        address tokenOut,
        uint256 amountOut
    ) external nonReentrant whenNotPaused onlyRelayer("JUP") {
        _settleRequest(requestId, to, tokenOut, amountOut, "JUP");
        emit XStocksJupSettled(requestId, to, tokenOut, amountOut);
    }
    
    // ============ Emergency Functions ============
    
    /// @notice Recover stuck tokens (owner only)
    function recoverTokens(address token, uint256 amount) external onlyOwner {
        require(IERC20(token).transfer(owner(), amount), "Recovery failed");
    }
    
    /// @notice Expire stale requests (anyone can call for cleanup)
    function expireRequest(bytes32 requestId) external {
        require(block.timestamp > requestDeadlines[requestId], "Not expired yet");
        require(requestDeadlines[requestId] > 0, "Request does not exist");
        
        // Mark as settled to prevent future settlement
        settled[keccak256("THOR")][requestId] = true;
        settled[keccak256("ZK")][requestId] = true;
        settled[keccak256("RAY")][requestId] = true;
        settled[keccak256("JUP")][requestId] = true;
        
        emit RequestExpired(requestId, requestDeadlines[requestId], block.timestamp);
    }
    
    // ============ View Functions ============
    
    function getV2Router(string calldata name) external view returns (V2Router memory) {
        return v2Routers[keccak256(bytes(name))];
    }
    
    function getV3Router(string calldata name) external view returns (V3Router memory) {
        return v3Routers[keccak256(bytes(name))];
    }
    
    function getRequestData(bytes32 requestId) external view returns (
        uint256 deadline,
        address tokenIn,
        uint256 amountIn
    ) {
        return (requestDeadlines[requestId], requestTokens[requestId], requestAmounts[requestId]);
    }
    
    function isRequestSettled(string calldata relayerType, bytes32 requestId) external view returns (bool) {
        return settled[keccak256(bytes(relayerType))][requestId];
    }
}
