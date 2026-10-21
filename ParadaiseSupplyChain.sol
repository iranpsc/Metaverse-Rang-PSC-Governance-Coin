// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ============================================================
// IMPORTS (OpenZeppelin Contracts v5.x)
// ============================================================
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

// ============================================================
// CONTRACT 1: PSCToken
// ============================================================
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

    uint256 public constant TOTAL_SUPPLY = 200_000_000 * 10**18;

    address public immutable deployer;
    address public treasury;
    bool public treasurySet;

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
        if (treasurySet) revert AlreadySet();
        if (_treasury == address(0)) revert InvalidTreasuryAddress();

        treasury = _treasury;
        treasurySet = true;

        uint256 balance = balanceOf(msg.sender);
        if (balance == 0) revert NoTokensToTransfer();

        _transfer(msg.sender, _treasury, balance);

        emit TreasurySet(_treasury);
    }
}

// ============================================================
// CONTRACT 2: PSCTreasury
// ============================================================
/**
 * @title PSCTreasury
 * @notice Treasury contract managing first-year allocations, multi-wallet team distribution,
 *         and an annual exponential decay release mechanism governed by AccessControl/Timelock.
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
    uint256 public constant ANNUAL_RELEASE_BPS = 1000; // 10.00%
    uint256 public constant DEVELOPER_BPS = 1000;      // 10.00% of annual release
    uint256 public constant FOUNDERS_BPS = 5000;       // 50.00% of annual release
    uint256 public constant PUBLIC_BPS = 4000;         // 40.00% of annual release

    // November 6, 2027 00:00:00 UTC = 1825545600
    uint256 public constant INITIAL_RELEASE_DATE = 1825545600;

    // First-Year Distribution (20,000,000 PSC)
    uint256 public constant TOTAL_SUPPLY_CAP = 200_000_000 * 10**18;
    uint256 public constant TEAM_AMOUNT = 2_000_000 * 10**18;
    uint256 public constant FOUNDERS_AMOUNT = 10_000_000 * 10**18;
    uint256 public constant AIRDROP_AMOUNT = 4_000_000 * 10**18;
    uint256 public constant PUBLIC_OFFERING_AMOUNT = 4_000_000 * 10**18;

    // --- Immutables ---
    IERC20 public immutable pscToken;
    address public immutable developerWallet;
    address public immutable founder1;
    address public immutable founder2;
    address public immutable publicOfferingWallet;
    address public immutable publicDistributionWallet;

    // --- State Variables ---
    uint256 public remainingSupply;
    uint256 public lastReleaseTime;
    uint256 public totalReleased;
    bool public initialized;

    // --- Events ---
    event Initialized(address indexed timelock, uint256 remainingSupply);
    event FirstYearDistributed(
        uint256 teamTotal,
        uint256 founder1Amount,
        uint256 founder2Amount,
        uint256 airdropAmount,
        uint256 publicOfferingAmount
    );
    event AnnualReleaseExecuted(
        uint256 totalReleasedThisYear,
        uint256 developerAmount,
        uint256 founder1Amount,
        uint256 founder2Amount,
        uint256 publicAmount,
        uint256 nextReleaseTimestamp
    );
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    constructor(
        address _pscToken,
        address _developerWallet,
        address _founder1,
        address _founder2,
        address _publicOfferingWallet,
        address _publicDistributionWallet
    ) {
        if (
            _pscToken == address(0) ||
            _developerWallet == address(0) ||
            _founder1 == address(0) ||
            _founder2 == address(0) ||
            _publicOfferingWallet == address(0) ||
            _publicDistributionWallet == address(0)
        ) revert InvalidParameters();

        pscToken = IERC20(_pscToken);
        developerWallet = _developerWallet;
        founder1 = _founder1;
        founder2 = _founder2;
        publicOfferingWallet = _publicOfferingWallet;
        publicDistributionWallet = _publicDistributionWallet;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        lastReleaseTime = INITIAL_RELEASE_DATE;
    }

    /**
     * @notice Distributes Year 1 tokens according to tokenomics and transfers control to TimelockController.
     * @param timelockAddress The TimelockController address handling admin governance.
     * @param airdropContract The MerkleAirdrop contract address.
     * @param teamWallets Individual verified wallets of core team members.
     * @param teamAmounts Respective token allocations for each team wallet (Sum must strictly equal 2M PSC).
     */
    function initialize(
        address timelockAddress,
        address airdropContract,
        address[] calldata teamWallets,
        uint256[] calldata teamAmounts
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (initialized) revert AlreadyInitialized();
        if (timelockAddress == address(0) || airdropContract == address(0)) revert InvalidParameters();
        if (teamWallets.length != teamAmounts.length || teamWallets.length == 0) revert InvalidParameters();

        uint256 currentBalance = pscToken.balanceOf(address(this));
        if (currentBalance != TOTAL_SUPPLY_CAP) revert InvalidParameters();

        // 1. Distribute Year-1 Team Allocation to individual verified addresses
        uint256 distributedTeamTotal = 0;
        for (uint256 i = 0; i < teamWallets.length; ) {
            if (teamWallets[i] == address(0) || teamAmounts[i] == 0) revert InvalidParameters();
            distributedTeamTotal += teamAmounts[i];
            pscToken.safeTransfer(teamWallets[i], teamAmounts[i]);
            unchecked { ++i; }
        }
        if (distributedTeamTotal != TEAM_AMOUNT) revert InvalidDistributionSum();

        // 2. Distribute to Founders (5M each)
        uint256 perFounder = FOUNDERS_AMOUNT / 2;
        pscToken.safeTransfer(founder1, perFounder);
        pscToken.safeTransfer(founder2, perFounder);

        // 3. Fund Merkle Airdrop Contract (4M)
        pscToken.safeTransfer(airdropContract, AIRDROP_AMOUNT);

        // 4. Send Public Offering allocation to the dedicated ICO/sale wallet (4M)
        pscToken.safeTransfer(publicOfferingWallet, PUBLIC_OFFERING_AMOUNT);

        // 5. Update Treasury remaining balance (180M)
        remainingSupply = TOTAL_SUPPLY_CAP - (TEAM_AMOUNT + FOUNDERS_AMOUNT + AIRDROP_AMOUNT + PUBLIC_OFFERING_AMOUNT);
        initialized = true;

        emit FirstYearDistributed(
            TEAM_AMOUNT,
            perFounder,
            perFounder,
            AIRDROP_AMOUNT,
            PUBLIC_OFFERING_AMOUNT
        );

        // 6. Transfer Governance Roles entirely to TimelockController
        _grantRole(DEFAULT_ADMIN_ROLE, timelockAddress);
        _grantRole(TIMELOCK_ROLE, timelockAddress);
        _grantRole(EXECUTOR_ROLE, timelockAddress);

        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);

        emit Initialized(timelockAddress, remainingSupply);
    }

    /**
     * @notice Releases 10% annual decay supply to stakeholders after November 6, 2027.
     */
    function releaseAnnual() external onlyRole(EXECUTOR_ROLE) nonReentrant {
        if (!initialized) revert NotInitialized();
        if (block.timestamp < lastReleaseTime + SECONDS_IN_YEAR) revert TooEarlyForRelease();
        if (remainingSupply == 0) revert NoRemainingSupply();

        uint256 annualAmount = (remainingSupply * ANNUAL_RELEASE_BPS) / 10000;

        uint256 developerAmount = (annualAmount * DEVELOPER_BPS) / 10000;
        uint256 foundersAmount = (annualAmount * FOUNDERS_BPS) / 10000;
        uint256 publicAmount = (annualAmount * PUBLIC_BPS) / 10000;

        uint256 founder1Amount = foundersAmount / 2;
        uint256 founder2Amount = foundersAmount - founder1Amount;

        pscToken.safeTransfer(developerWallet, developerAmount);
        pscToken.safeTransfer(founder1, founder1Amount);
        pscToken.safeTransfer(founder2, founder2Amount);
        pscToken.safeTransfer(publicDistributionWallet, publicAmount);

        remainingSupply -= annualAmount;
        totalReleased += annualAmount;
        lastReleaseTime += SECONDS_IN_YEAR;

        emit AnnualReleaseExecuted(
            annualAmount,
            developerAmount,
            founder1Amount,
            founder2Amount,
            publicAmount,
            lastReleaseTime
        );
    }

    /**
     * @notice Rescue trapped foreign tokens, callable exclusively via TimelockController.
     */
    function rescueTokens(address token, address to) external onlyRole(TIMELOCK_ROLE) nonReentrant {
        if (to == address(0)) revert InvalidParameters();
        if (token == address(pscToken)) revert CannotRescuePSCTokens();

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) revert NoRemainingSupply();

        IERC20(token).safeTransfer(to, balance);
        emit TokensRescued(token, to, balance);
    }

    function getTimeUntilNextRelease() external view returns (uint256) {
        uint256 nextTime = lastReleaseTime + SECONDS_IN_YEAR;
        if (block.timestamp >= nextTime) return 0;
        return nextTime - block.timestamp;
    }
}

// ============================================================
// CONTRACT 3: MerkleAirdrop
// ============================================================
/**
 * @title MerkleAirdrop
 * @notice Merkle-tree airdrop with a 90-day claim window, 60-day cliff/lock,
 *         and 365-day linear vesting. Clawback strictly protects vested user allocations.
 */
contract MerkleAirdrop is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error AirdropNotActive();
    error ClaimWindowClosed();
    error AlreadyClaimed();
    error InvalidMerkleProof();
    error ZeroAllocation();
    error ClawbackTooEarly();
    error ClawbackAlreadyDone();
    error NothingToRelease();
    error InsufficientContractBalance();
    error InvalidAddress();

    bytes32 public constant TIMELOCK_ROLE = keccak256("TIMELOCK_ROLE");

    uint256 public constant CLAIM_WINDOW = 90 days;
    uint256 public constant LOCK_DURATION = 60 days;
    uint256 public constant VESTING_DURATION = 365 days;
    uint256 public constant CLAWBACK_DELAY = 180 days;

    IERC20 public immutable pscToken;
    address public immutable treasury;

    bytes32 public merkleRoot;
    uint256 public airdropStartTime;
    uint256 public totalAirdropAmount;
    uint256 public totalAllocatedClaimed;
    uint256 public totalDistributed;
    bool public airdropInitialized;
    bool public clawbackExecuted;

    struct ClaimInfo {
        uint128 totalAllocation;
        uint128 claimedAmount;
        uint64 startTime;
    }

    mapping(address => ClaimInfo) public claims;
    mapping(address => bool) public hasClaimed;

    event AirdropInitialized(bytes32 indexed merkleRoot, uint256 totalAmount, uint256 startTime);
    event AirdropClaimed(address indexed recipient, uint256 amount, uint256 vestingStartTime);
    event TokensReleased(address indexed recipient, uint256 amount);
    event ClawbackExecuted(uint256 amountClawedBack, address indexed treasury);

    constructor(address _pscToken, address _treasury, address _timelock) {
        if (_pscToken == address(0) || _treasury == address(0) || _timelock == address(0)) {
            revert InvalidAddress();
        }
        pscToken = IERC20(_pscToken);
        treasury = _treasury;

        _grantRole(DEFAULT_ADMIN_ROLE, _timelock);
        _grantRole(TIMELOCK_ROLE, _timelock);
    }

    function initializeAirdrop(bytes32 _merkleRoot, uint256 _totalAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (airdropInitialized) revert AirdropNotActive();
        if (_merkleRoot == bytes32(0) || _totalAmount == 0) revert InvalidAddress();

        merkleRoot = _merkleRoot;
        totalAirdropAmount = _totalAmount;
        airdropStartTime = block.timestamp;
        airdropInitialized = true;

        emit AirdropInitialized(_merkleRoot, _totalAmount, airdropStartTime);
    }

    function claimAirdrop(uint256 amount, bytes32[] calldata merkleProof) external nonReentrant {
        if (!airdropInitialized) revert AirdropNotActive();
        if (block.timestamp > airdropStartTime + CLAIM_WINDOW) revert ClaimWindowClosed();
        if (hasClaimed[msg.sender]) revert AlreadyClaimed();
        if (amount == 0) revert ZeroAllocation();

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender, amount))));
        if (!MerkleProof.verify(merkleProof, merkleRoot, leaf)) revert InvalidMerkleProof();

        hasClaimed[msg.sender] = true;
        totalAllocatedClaimed += amount;

        claims[msg.sender] = ClaimInfo({
            totalAllocation: uint128(amount),
            claimedAmount: 0,
            startTime: uint64(block.timestamp)
        });

        emit AirdropClaimed(msg.sender, amount, block.timestamp);
    }

    function releaseVested() external nonReentrant {
        if (!airdropInitialized) revert AirdropNotActive();

        ClaimInfo storage info = claims[msg.sender];
        if (info.totalAllocation == 0) revert ZeroAllocation();

        uint256 claimable = _getClaimableAmount(msg.sender);
        if (claimable == 0) revert NothingToRelease();

        info.claimedAmount += uint128(claimable);
        totalDistributed += claimable;

        pscToken.safeTransfer(msg.sender, claimable);
        emit TokensReleased(msg.sender, claimable);
    }

    function executeClawback() external onlyRole(TIMELOCK_ROLE) nonReentrant {
        if (!airdropInitialized) revert AirdropNotActive();
        if (clawbackExecuted) revert ClawbackAlreadyDone();

        uint256 clawbackAvailableTime = airdropStartTime + LOCK_DURATION + VESTING_DURATION + CLAWBACK_DELAY;
        if (block.timestamp < clawbackAvailableTime) revert ClawbackTooEarly();

        uint256 currentBalance = pscToken.balanceOf(address(this));
        uint256 activeVestingObligations = totalAllocatedClaimed - totalDistributed;
        
        if (currentBalance <= activeVestingObligations) revert InsufficientContractBalance();
        
        uint256 clawbackAmount = currentBalance - activeVestingObligations;
        clawbackExecuted = true;

        pscToken.safeTransfer(treasury, clawbackAmount);
        emit ClawbackExecuted(clawbackAmount, treasury);
    }

    function _getClaimableAmount(address user) internal view returns (uint256) {
        ClaimInfo memory info = claims[user];
        if (info.totalAllocation == 0) return 0;

        uint256 elapsed = block.timestamp - info.startTime;
        if (elapsed < LOCK_DURATION) return 0;

        if (elapsed >= LOCK_DURATION + VESTING_DURATION) {
            return uint256(info.totalAllocation) - uint256(info.claimedAmount);
        }

        uint256 vestingElapsed = elapsed - LOCK_DURATION;
        uint256 vestedTotal = (uint256(info.totalAllocation) * vestingElapsed) / VESTING_DURATION;

        if (vestedTotal > info.claimedAmount) {
            return vestedTotal - info.claimedAmount;
        }
        return 0;
    }

    function getClaimableAmount(address user) external view returns (uint256) {
        return _getClaimableAmount(user);
    }
}

// ============================================================
// CONTRACT 4: SupplyChainModule
// ============================================================
/**
 * @title SupplyChainModule
 * @notice Fee collection module supporting both direct caller payments and operator-mediated EIP-2612 Permit pulls.
 */
contract SupplyChainModule is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error InvalidAddress();
    error ZeroAmount();

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

    constructor(address _pscToken, address _treasury, address _timelock) {
        if (_pscToken == address(0) || _treasury == address(0) || _timelock == address(0)) {
            revert InvalidAddress();
        }
        pscToken = IERC20(_pscToken);
        treasury = _treasury;

        _grantRole(DEFAULT_ADMIN_ROLE, _timelock);
        _grantRole(TIMELOCK_ROLE, _timelock);
        _grantRole(OPERATOR_ROLE, _timelock);
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

        IERC20Permit(address(pscToken)).permit(payer, address(this), amount, deadline, v, r, s);
        _executeFeeDistribution(payer, amount);
    }

    function _executeFeeDistribution(address payer, uint256 amount) internal {
        pscToken.safeTransferFrom(payer, address(this), amount);

        uint256 burnAmount = (amount * BURN_BPS) / 10000;
        uint256 treasuryAmount = amount - burnAmount;

        ERC20Burnable(address(pscToken)).burn(burnAmount);
        pscToken.safeTransfer(treasury, treasuryAmount);

        totalFeesProcessed += amount;
        totalBurned += burnAmount;
        totalToTreasury += treasuryAmount;

        emit FeeProcessed(payer, amount, burnAmount, treasuryAmount);
    }
}
