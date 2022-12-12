// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TestToken is ERC20, Ownable {
    constructor() ERC20("BOOKIE USD", "BU") {}

    function mint(address receiver, uint amount) public onlyOwner {
        // anyone can mint.  convenient for testing.
        _mint(receiver, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}
