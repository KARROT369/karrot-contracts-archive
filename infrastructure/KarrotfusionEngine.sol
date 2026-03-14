// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IERC20 {
    function transfer(address to, uint amount) external returns (bool);
    function burn(uint amount) external;
    function mint(address to, uint amount) external;
}

contract KarrotFusionEngine is Ownable {
    IERC20 public karrot;
    
    // Commit-reveal scheme for entropy
    mapping(address => bytes32) public commitHashes;
    mapping(address => uint256) public commitBlock;
    
    uint256 public constant BLOCKS_TO_WAIT = 10;
    uint256 public constant MIN_DECAY = 1;
    uint256 public constant MAX_DECAY = 5;

    event EntropyDecay(address indexed user, uint decayAmount, uint decayRate);
    event HyperNovaBlast(address indexed triggeredBy, uint novaAmount, bool minted);
    event EntropyCommitted(address indexed user, bytes32 hash);
    event EntropyRevealed(address indexed user, uint256 reveal);

    constructor(address _karrot) Ownable(msg.sender) {
        require(_karrot != address(0), "Invalid karrot address");
        karrot = IERC20(_karrot);
    }

    modifier onlyOwner() {
        require(msg.sender == owner(), "Sigma Mother says no.");
        _;
    }

    // Commit-reveal for entropy: prevents miner manipulation
    function commitEntropy(bytes32 _hash) external {
        require(commitHashes[msg.sender] == bytes32(0), "Already committed");
        commitHashes[msg.sender] = _hash;
        commitBlock[msg.sender] = block.number;
        emit EntropyCommitted(msg.sender, _hash);
    }

    function triggerEntropy(uint userBalance, uint256 _reveal, bytes32 _salt) external returns (uint) {
        require(commitHashes[msg.sender] != bytes32(0), "No commit found");
        require(block.number >= commitBlock[msg.sender] + BLOCKS_TO_WAIT, "Too early");
        require(keccak256(abi.encodePacked(_reveal, _salt)) == commitHashes[msg.sender], "Invalid reveal");
        
        // Use reveal + blockhash for randomness (safer but still not VRF)
        bytes32 randomness = keccak256(abi.encodePacked(_reveal, blockhash(commitBlock[msg.sender])));
        uint decayRate = (uint256(randomness) % (MAX_DECAY - MIN_DECAY + 1)) + MIN_DECAY;
        uint decayAmount = (userBalance * decayRate) / 100;

        karrot.burn(decayAmount);
        emit EntropyDecay(msg.sender, decayAmount, decayRate);
        
        // Clear commit
        commitHashes[msg.sender] = bytes32(0);
        commitBlock[msg.sender] = 0;
        
        emit EntropyRevealed(msg.sender, _reveal);
        return decayAmount;
    }

    function triggerHyperNova(bool mintInstead) external onlyOwner {
        // Use blockhash for some randomness (owner-only, less critical)
        uint256 randomSeed = uint256(blockhash(block.number - 1));
        uint novaAmount = (randomSeed % 1000) + 1000;
        
        if (mintInstead) {
            karrot.mint(owner(), novaAmount);
        } else {
            karrot.burn(novaAmount);
        }

        emit HyperNovaBlast(msg.sender, novaAmount, mintInstead);
    }

    function updateKarrot(address _newKarrot) external onlyOwner {
        require(_newKarrot != address(0), "Invalid address");
        karrot = IERC20(_newKarrot);
    }
}
