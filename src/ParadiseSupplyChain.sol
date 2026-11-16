// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title PSCToken (Paradise Supply Chain Token)
 * @notice Standard ERC20 token with Burnable and Permit extensions.
 * @dev Deployer holds total supply temporarily and transfers custody
 *      to PSCTreasury via setTreasury() exactly once.
 */
contract PSCToken is ERC20, ERC20Burnable, ERC20Permit {
    error AlreadySet();
    error InvalidTreasuryAddress();
    error OnlyDeployer();
    error NoTokensToTransfer();

    uint256 public constant TOTAL_SUPPLY = 200_000_000 * 1e18;

    address public immutable deployer;
    address public treasury;

    event TreasurySet(address indexed treasury);

    constructor()
        ERC20("Paradise Supply Chain", "PSC")
        ERC20Permit("Paradise Supply Chain")
    {
        deployer = msg.sender;
        _mint(msg.sender, TOTAL_SUPPLY);
    }

    /**
     * @notice Transfers all tokens to the PSCTreasury contract (one-time only).
     * @param _treasury Address of the deployed PSCTreasury contract.
     */
    function setTreasury(address _treasury) external {
        if (msg.sender != deployer) revert OnlyDeployer();
        if (treasury != address(0)) revert AlreadySet();
        if (_treasury == address(0) || _treasury.code.length == 0) revert InvalidTreasuryAddress();

        treasury = _treasury;

        uint256 balance = balanceOf(msg.sender);
        if (balance == 0) revert NoTokensToTransfer();

        _transfer(msg.sender, _treasury, balance);

        emit TreasurySet(_treasury);
    }

    /**
     * @notice Helper view for backward compatibility checking if treasury is set.
     */
    function treasurySet() external view returns (bool) {
        return treasury != address(0);
    }
}