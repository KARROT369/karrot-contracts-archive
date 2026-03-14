
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IKarrot {
    function balanceOf(address account) external view returns (uint);
    function burnFrom(address account, uint amount) external;
    function burn(uint amount) external;
    function mint(address to, uint amount) external;
}
