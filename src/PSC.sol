// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;


import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MyToken is ERC20, Ownable {
    uint256 private constant INITIAL_SUPPLY = 20_000_000 * 10 ** 18;

    constructor()
        ERC20("Paradaise Supply Chain", "PSC")
        Ownable(msg.sender)
    {
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}


