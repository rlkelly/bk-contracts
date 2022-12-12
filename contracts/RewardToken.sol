// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract RewardToken is ERC20Burnable, Ownable {
    mapping (address => bool) public minters;
    event MinterAdded(address minter);
    event MinterRemoved(address minter);

    constructor() ERC20("Bookie Rewards", "BoR") {
        // make owner a minter
        minters[msg.sender] = true;
    }

    function addMinter(address minter) public onlyOwner {
        minters[minter] = true;
    }

    function removeMinter(address minter) public onlyOwner {
        minters[minter] = false;
    }

    function mint(address receiver, uint amount) external {
        require(minters[msg.sender], "only minters can mint");
        _mint(receiver, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }
}
