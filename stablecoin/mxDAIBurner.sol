
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function burn(uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
}

contract mxDAIBurner {
    IERC20 public immutable mxDAI;
    address public immutable treasury;

    mapping(address => uint256) public totalBurnedByUser;
    uint256 public totalBurnedGlobal;

    event Burned(address indexed burner, uint256 amount, uint256 timestamp);

    constructor(address _mxDAI, address _treasury) {
        mxDAI = IERC20(_mxDAI);
        treasury = _treasury;
    }

    function defendPeg(uint256 amount) external {
        require(amount > 0, "Nothing to burn");

        require(mxDAI.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        totalBurnedByUser[msg.sender] += amount;
        totalBurnedGlobal += amount;

        try mxDAI.burn(amount) {
        } catch {
            require(mxDAI.transfer(treasury, amount), "Fallback transfer failed");
        }

        emit Burned(msg.sender, amount, block.timestamp);
    }

    function getMyContribution(address user) external view returns (uint256) {
        return totalBurnedByUser[user];
    }

    function getTotalBurned() external view returns (uint256) {
        return totalBurnedGlobal;
    }
}
