// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract MonBattle {
    struct Mon {
        string name;
        uint256 power;
        address owner;
    }

    mapping(uint256 => Mon) public mons;
    uint256 public nextMonId;

    event BattleResult(uint256 mon1, uint256 mon2, address winner);

    function createMon(string memory name, uint256 power) external {
        mons[nextMonId] = Mon(name, power, msg.sender);
        nextMonId++;
    }

    function battle(uint256 monId1, uint256 monId2) external returns (address) {
        Mon storage mon1 = mons[monId1];
        Mon storage mon2 = mons[monId2];

        require(mon1.owner == msg.sender || mon2.owner == msg.sender, "Must own one Mon");
        require(mon1.owner != address(0) && mon2.owner != address(0), "Mons must exist");
