// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title PSCTreasury
 * @notice Treasury contract managing Year 1 distributions and annual dynamic decay release.
 */
contract PSCTreasury is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- Custom Errors ---
    error NotInitialized();
    error AlreadyInitialized();
    error TooEarlyForRelease();
    error NoRemainingSupply();
    error InvalidParameters();
    error InvalidDistributionSum();
    error CannotRescuePSCTokens();

    // --- Roles ---
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant TIMELOCK_ROLE = keccak256("TIMELOCK_ROLE");

    // --- Constants ---
    uint256 public constant SECONDS_IN_YEAR = 365 days;
    uint256 public constant ANNUAL_RELEASE_BPS = 1000;    // 10.00%

    uint256 public constant DEVELOPER_BPS = 1000;         // 10.00%
    uint256 public constant FOUNDERS_BPS = 4000;          // 40.00%
    uint256 public constant CONSULTANT_BPS = 1000;        // 10.00%
    uint256 public constant PUBLIC_BPS = 4000;            // 40.00%

    // November 6, 2027 00:00:00 UTC = 1825545600 (Launch & Year 1 distribution date)
    uint256 public constant INITIAL_RELEASE_DATE = 1825545600;

    // First-Year Distribution (20,000,000 PSC)
    uint256 public constant TOTAL_SUPPLY_CAP = 200_000_000 * 1e18;
    uint256 public constant TEAM_AMOUNT = 2_000_000 * 1e18;
    uint256 public constant FOUNDERS_AMOUNT = 8_000_000 * 1e18;
    uint256 public constant CONSULTANT_AMOUNT = 2_000_000 * 1e18;
    uint256 public constant AIRDROP_AMOUNT = 4_000_000 * 1e18;
    uint256 public constant PUBLIC_OFFERING_AMOUNT = 4_000_000 * 1e18;

    // --- Immutables ---
    IERC20 public immutable pscToken;
    address public immutable publicOfferingWallet;

    // --- Mutable Wallets (Upgradable via TIMELOCK_ROLE) ---
    address public developerWallet;
    address public founder1;
    address public founder2;
    address public consultantWallet;
    address public publicDistributionWallet;

    // --- State Variables ---
    uint256 public lastReleaseTime;
    uint256 public totalReleased;
    bool public initialized;

    // --- Events ---
    event Initialized(address indexed timelock, uint256 remainingSupply);
    event FirstYearDistributed(
        uint256 teamTotal,
        uint256 founder1Amount,
        uint256 founder2Amount,
        uint256 consultantAmount,
        uint256 airdropAmount,
        uint256 publicOfferingAmount
    );
    event AnnualReleaseExecuted(
        uint256 totalReleasedThisYear,
        uint256 developerAmount,
        uint256 founder1Amount,
        uint256 founder2Amount,
        uint256 consultantAmount,
        uint256 publicAmount,
        uint256 nextReleaseTimestamp,
        uint256 newBalance
    );
    event WalletsUpdated(
        address developer,
        address founder1,
        address founder2,
        address consultant,
        address publicDistribution
    );
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    constructor(
        address _pscToken,
        address _developerWallet,
        address _founder1,
        address _founder2,
        address _consultantWallet,
        address _publicOfferingWallet,
        address _publicDistributionWallet
    ) {
        if (
            _pscToken == address(0) ||
            _developerWallet == address(0) ||
            _founder1 == address(0) ||
            _founder2 == address(0) ||
            _consultantWallet == address(0) ||
            _publicOfferingWallet == address(0) ||
            _publicDistributionWallet == address(0)
        ) revert InvalidParameters();

        pscToken = IERC20(_pscToken);
        developerWallet = _developerWallet;
        founder1 = _founder1;
        founder2 = _founder2;
        consultantWallet = _consultantWallet;
        publicOfferingWallet = _publicOfferingWallet;
        publicDistributionWallet = _publicDistributionWallet;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        // First annual release (Year 2) permitted 1 year after launch date (Nov 6, 2028)
        lastReleaseTime = INITIAL_RELEASE_DATE + SECONDS_IN_YEAR;
    }

    function initialize(
        address timelockAddress,
        address airdropContract,
        address[] calldata teamWallets,
        uint256[] calldata teamAmounts
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        if (initialized) revert AlreadyInitialized();
        if (timelockAddress == address(0) || airdropContract == address(0)) revert InvalidParameters();

        uint256 len = teamWallets.length;
        if (len != teamAmounts.length || len == 0) revert InvalidParameters();

        if (pscToken.balanceOf(address(this)) != TOTAL_SUPPLY_CAP) revert InvalidParameters();

        initialized = true;

        uint256 distributedTeamTotal = 0;
        for (uint256 i = 0; i < len; ) {
            address member = teamWallets[i];
            uint256 amt = teamAmounts[i];
            if (member == address(0) || amt == 0) revert InvalidParameters();
            distributedTeamTotal += amt;
            pscToken.safeTransfer(member, amt);
            unchecked { ++i; }
        }
        if (distributedTeamTotal != TEAM_AMOUNT) revert InvalidDistributionSum();

        uint256 perFounder = FOUNDERS_AMOUNT / 2;
        pscToken.safeTransfer(founder1, perFounder);
        pscToken.safeTransfer(founder2, perFounder);

        pscToken.safeTransfer(consultantWallet, CONSULTANT_AMOUNT);
        pscToken.safeTransfer(airdropContract, AIRDROP_AMOUNT);
        pscToken.safeTransfer(publicOfferingWallet, PUBLIC_OFFERING_AMOUNT);

        emit FirstYearDistributed(
            TEAM_AMOUNT,
            perFounder,
            perFounder,
            CONSULTANT_AMOUNT,
            AIRDROP_AMOUNT,
            PUBLIC_OFFERING_AMOUNT
        );

        _grantRole(DEFAULT_ADMIN_ROLE, timelockAddress);
        _grantRole(TIMELOCK_ROLE, timelockAddress);
        _grantRole(EXECUTOR_ROLE, timelockAddress);

        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);

        emit Initialized(timelockAddress, pscToken.balanceOf(address(this)));
    }

    function updateWallets(
        address _developerWallet,
        address _founder1,
        address _founder2,
        address _consultantWallet,
        address _publicDistributionWallet
    ) external onlyRole(TIMELOCK_ROLE) {
        if (
            _developerWallet == address(0) ||
            _founder1 == address(0) ||
            _founder2 == address(0) ||
            _consultantWallet == address(0) ||
            _publicDistributionWallet == address(0)
        ) revert InvalidParameters();

        developerWallet = _developerWallet;
        founder1 = _founder1;
        founder2 = _founder2;
        consultantWallet = _consultantWallet;
        publicDistributionWallet = _publicDistributionWallet;

        emit WalletsUpdated(
            _developerWallet,
            _founder1,
            _founder2,
            _consultantWallet,
            _publicDistributionWallet
        );
    }

    function releaseAnnual() external onlyRole(EXECUTOR_ROLE) nonReentrant {
        if (!initialized) revert NotInitialized();
        uint256 nextRelease = lastReleaseTime;
        if (block.timestamp < nextRelease) revert TooEarlyForRelease();

        uint256 currentBalance = pscToken.balanceOf(address(this));
        if (currentBalance == 0) revert NoRemainingSupply();

        uint256 annualAmount = (currentBalance * ANNUAL_RELEASE_BPS) / 10000;

        uint256 developerAmount = (annualAmount * DEVELOPER_BPS) / 10000;
        uint256 foundersAmount = (annualAmount * FOUNDERS_BPS) / 10000;
        uint256 consultantAmount = (annualAmount * CONSULTANT_BPS) / 10000;

        uint256 publicAmount;
        uint256 founder1Amount = foundersAmount / 2;
        uint256 founder2Amount;

        unchecked {
            publicAmount = annualAmount - (developerAmount + foundersAmount + consultantAmount);
            founder2Amount = foundersAmount - founder1Amount;
            nextRelease += SECONDS_IN_YEAR;
            totalReleased += annualAmount;
        }

        lastReleaseTime = nextRelease;

        pscToken.safeTransfer(developerWallet, developerAmount);
        pscToken.safeTransfer(founder1, founder1Amount);
        pscToken.safeTransfer(founder2, founder2Amount);
        pscToken.safeTransfer(consultantWallet, consultantAmount);
        pscToken.safeTransfer(publicDistributionWallet, publicAmount);

        emit AnnualReleaseExecuted(
            annualAmount,
            developerAmount,
            founder1Amount,
            founder2Amount,
            consultantAmount,
            publicAmount,
            nextRelease,
            pscToken.balanceOf(address(this))
        );
    }

    function rescueTokens(address token, address to) external onlyRole(TIMELOCK_ROLE) nonReentrant {
        if (to == address(0)) revert InvalidParameters();
        if (token == address(pscToken)) revert CannotRescuePSCTokens();

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) revert NoRemainingSupply();

        IERC20(token).safeTransfer(to, balance);
        emit TokensRescued(token, to, balance);
    }

    function getRemainingSupply() external view returns (uint256) {
        return pscToken.balanceOf(address(this));
    }

    function getTimeUntilNextRelease() external view returns (uint256) {
        uint256 nextRelease = lastReleaseTime;
        if (block.timestamp >= nextRelease) return 0;
        unchecked {
            return nextRelease - block.timestamp;
        }
    }
}