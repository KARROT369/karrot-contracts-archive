// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title MonBattle
 * @notice Simple battle game for Mons
 */
contract MonBat is Ownable, ReentrancyGuard {
    struct Mon {
        string name;
        uint256 power;
        address owner;
        bool exists;
    }

    mapping(uint256 => Mon) public mons;
    mapping(address => uint256[]) public ownedMons;
    uint256 public nextMonId;
    uint256 public battleFee = 0.001 ether;
    uint256 public totalBattles;

    event MonCreated(uint256 indexed monId, string name, uint256 power, address owner);
    event BattleResult(uint256 indexed mon1, uint256 indexed mon2, address winner, uint256 prize);
    event FeeUpdated(uint256 newFee);

    constructor() Ownable(msg.sender) {}

    function createMon(string memory name, uint256 power) external returns (uint256) {
        require(bytes(name).length > 0, "Name required");
        require(power > 0, "Power must be > 0");
        
        uint256 monId = nextMonId;
        mons[monId] = Mon(name, power, msg.sender, true);
        ownedMons[msg.sender].push(monId);
        nextMonId++;
        
        emit MonCreated(monId, name, power, msg.sender);
        return monId;
    }

    function battle(uint256 monId1, uint256 monId2) external payable nonReentrant returns (address) {
        require(msg.value >= battleFee, "Insufficient battle fee");
        require(monId1 != monId2, "Cannot battle self");
        
        Mon storage mon1 = mons[monId1];
        Mon storage mon2 = mons[monId2];

        require(mon1.exists && mon2.exists, "Mons must exist");
        require(mon1.owner == msg.sender || mon2.owner == msg.sender, "Must own one Mon");

        address winner = mon1.power >= mon2.power ? mon1.owner : mon2.owner;
        totalBattles++;
        
        (bool sent, ) = payable(winner).call{value: msg.value}("");
        require(sent, "Prize transfer failed");

        emit BattleResult(monId1, monId2, winner, msg.value);
        return winner;
    }

    function setBattleFee(uint256 _fee) external onlyOwner {
        battleFee = _fee;
        emit FeeUpdated(_fee);
    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees");
        (bool sent, ) = payable(owner()).call{value: balance}("");
        require(sent, "Withdraw failed");
    }

    function getOwnedMons(address owner) external view returns (uint256[] memory) {
        return ownedMons[owner];
    }

    receive() external payable {}
}
