pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract pxAsset is ERC20 {
    address public minter;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        minter = msg.sender;
    }

    function mint(address to, uint amount) external {
        require(msg.sender == minter, "Only minter");
        _mint(to, amount);
    }

    function burn(address from, uint amount) external {
        require(msg.sender == minter, "Only minter");
        _burn(from, amount);
    }
}

