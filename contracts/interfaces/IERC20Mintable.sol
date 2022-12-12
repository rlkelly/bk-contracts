// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IERC20Mintable {
    function mint(address recipient, uint256 amount) external;
    function burn(uint256 amount) external returns (bool);
}
