// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SupplyChainModule
 * @notice Fee collection module supporting front-running protected Permits and backend operators.
 */
contract SupplyChainModule is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error InvalidAddress();
    error ZeroAmount();
    error CannotRescuePSCTokens();
    error NothingToRescue();
    error InsufficientAllowance();

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant TIMELOCK_ROLE = keccak256("TIMELOCK_ROLE");

    uint256 public constant BURN_BPS = 1000;     // 10.00%
    uint256 public constant TREASURY_BPS = 9000; // 90.00%

    IERC20 public immutable pscToken;
    address public immutable treasury;

    uint256 public totalFeesProcessed;
    uint256 public totalBurned;
    uint256 public totalToTreasury;

    event FeeProcessed(address indexed payer, uint256 amount, uint256 burned, uint256 toTreasury);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    constructor(
        address _pscToken,
        address _treasury,
        address _timelock,
        address _operator
    ) {
        if (
            _pscToken == address(0) ||
            _treasury == address(0) ||
            _timelock == address(0) ||
            _operator == address(0)
        ) {
            revert InvalidAddress();
        }
        pscToken = IERC20(_pscToken);
        treasury = _treasury;

        _grantRole(DEFAULT_ADMIN_ROLE, _timelock);
        _grantRole(TIMELOCK_ROLE, _timelock);
        _grantRole(OPERATOR_ROLE, _operator);
    }

    function processFee(address payer, uint256 amount) external onlyRole(OPERATOR_ROLE) nonReentrant {
        if (payer == address(0)) revert InvalidAddress();
        if (amount == 0) revert ZeroAmount();

        _executeFeeDistribution(payer, amount);
    }

    function processFeeWithPermit(
        address payer,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external onlyRole(OPERATOR_ROLE) nonReentrant {
        if (payer == address(0)) revert InvalidAddress();
        if (amount == 0) revert ZeroAmount();

        try IERC20Permit(address(pscToken)).permit(payer, address(this), amount, deadline, v, r, s) {} 
        catch {
            if (pscToken.allowance(payer, address(this)) < amount) {
                revert InsufficientAllowance();
            }
        }

        _executeFeeDistribution(payer, amount);
    }

    function rescueTokens(address token, address to) external onlyRole(TIMELOCK_ROLE) nonReentrant {
        if (to == address(0)) revert InvalidAddress();
        if (token == address(pscToken)) revert CannotRescuePSCTokens();

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) revert NothingToRescue();

        IERC20(token).safeTransfer(to, balance);
        emit TokensRescued(token, to, balance);
    }

    function _executeFeeDistribution(address payer, uint256 amount) internal {
        pscToken.safeTransferFrom(payer, address(this), amount);

        uint256 burnAmount = (amount * BURN_BPS) / 10000;
        uint256 treasuryAmount;

        unchecked {
            treasuryAmount = amount - burnAmount;
            totalFeesProcessed += amount;
            totalBurned += burnAmount;
            totalToTreasury += treasuryAmount;
        }

        ERC20Burnable(address(pscToken)).burn(burnAmount);
        pscToken.safeTransfer(treasury, treasuryAmount);

        emit FeeProcessed(payer, amount, burnAmount, treasuryAmount);
    }
}