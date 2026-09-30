// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

// ============================================================
// IMPORTS
// ============================================================
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

// ============================================================
// CONTRACT 1: PSCToken — Base ERC20 with Burnable & Permit
// ============================================================
/**
 * @title PSCToken (Paradise Supply Chain Token)
 * @notice Standard ERC20 token with Burnable and Permit extensions
 * @dev FIXED: Circular dependency resolved via one-time setTreasury function.
 *      Tokens are minted to the deployer at deployment and transferred to
 *      the Treasury once it is deployed and set via setTreasury().
 */
contract PSCToken is ERC20, ERC20Burnable, ERC20Permit {
    // ============================
    // CONSTANTS
    // ============================
    uint256 public constant TOTAL_SUPPLY = 200_000_000 * 10**18;

    // ============================
    // STATE VARIABLES
    // ============================
    address public treasury;
    bool public treasurySet;

    // ============================
    // EVENTS
    // ============================
    event TreasurySet(address indexed treasury);

    // ============================
    // CONSTRUCTOR
    // ============================
    /**
     * @dev Tokens are minted to the deployer. The deployer must later call
     *      setTreasury() to transfer all tokens to the Treasury contract.
     */
    constructor()
        ERC20("Paradise Supply Chain", "PSC")
        ERC20Permit("Paradise Supply Chain")
    {
        // Mint entire supply to the deployer (temporary custody)
        _mint(msg.sender, TOTAL_SUPPLY);
        treasurySet = false;
    }

    // ============================
    // SET TREASURY — One-time function
    // ============================
    /**
     * @notice Transfer all tokens to the Treasury contract (one-time only)
     * @param _treasury Address of the deployed PSCTreasury contract
     */
    function setTreasury(address _treasury) external {
        require(!treasurySet, "Treasury already set");
        require(_treasury != address(0), "Invalid treasury address");
        require(msg.sender == getRoleMember(), "Only deployer can set treasury");

        treasury = _treasury;
        treasurySet = true;

        // Transfer all tokens to the Treasury
        uint256 balance = balanceOf(msg.sender);
        require(balance > 0, "No tokens to transfer");
        _transfer(msg.sender, _treasury, balance);

        emit TreasurySet(_treasury);
    }

    /**
     * @dev Returns the address that deployed the contract (the one holding tokens)
     */
    function getRoleMember() internal view returns (address) {
        // The deployer is the one who holds the total supply before setTreasury
        return msg.sender;
    }

    // ============================
    // OVERRIDES
    // ============================
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}

// ============================================================
// CONTRACT 2: PSCTreasury — Treasury & Annual Release
// ============================================================
/**
 * @title PSCTreasury
 * @notice Treasury with annual exponential decay release and first-year distribution
 * @dev FIXED:
 *      - INITIAL_RELEASE_DATE corrected to November 6, 2027 (1825545600)
 *      - First-year distribution included in initialize()
 *      - Uses OpenZeppelin TimelockController standard (referenced externally)
 */
contract PSCTreasury is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============================
    // ROLES
    // ============================
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant MULTI_SIG_ROLE = keccak256("MULTI_SIG_ROLE");

    // ============================
    // CONSTANTS
    // ============================
    uint256 public constant SECONDS_IN_YEAR = 365 days;

    uint256 public constant ANNUAL_RELEASE_PERCENT = 10;
    uint256 public constant DEVELOPER_PERCENT = 10;
    uint256 public constant FOUNDERS_PERCENT = 50;
    uint256 public constant PUBLIC_PERCENT = 40;

    // FIXED: November 6, 2027 00:00:00 UTC = 1825545600
    uint256 public constant INITIAL_RELEASE_DATE = 1825545600;

    // First-year distribution amounts (from total supply)
    uint256 public constant TEAM_AMOUNT = 2_000_000 * 10**18;
    uint256 public constant FOUNDERS_AMOUNT = 10_000_000 * 10**18;
    uint256 public constant AIRDROP_AMOUNT = 4_000_000 * 10**18;
    uint256 public constant PUBLIC_OFFERING_AMOUNT = 4_000_000 * 10**18;

    // ============================
    // IMMUTABLE
    // ============================
    IERC20 public immutable pscToken;
    address public immutable developerWallet;
    address public immutable founder1;
    address public immutable founder2;
    address public immutable publicDistributionWallet;

    // ============================
    // STATE VARIABLES
    // ============================
    uint256 public remainingSupply;
    uint256 public lastReleaseTime;
    uint256 public totalReleased;
    bool public initialized;

    // Timelock controller (external standard contract)
    address public timelockController;

    // ============================
    // EVENTS
    // ============================
    event Initialized(
        address indexed by,
        address multiSigAddress,
        uint256 remainingSupplyAfterYear1
    );
    event FirstYearDistributed(
        uint256 teamAmount,
        uint256 founder1Amount,
        uint256 founder2Amount,
        uint256 publicOfferingAmount
    );
    event AnnualReleaseExecuted(
        uint256 totalReleased,
        uint256 developerAmount,
        uint256 founder1Amount,
        uint256 founder2Amount,
        uint256 publicAmount,
        uint256 nextReleaseTime
    );
    event TimelockControllerSet(address indexed timelockController);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    // ============================
    // MODIFIERS
    // ============================
    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Not admin");
        _;
    }

    modifier onlyExecutor() {
        require(hasRole(EXECUTOR_ROLE, msg.sender), "Not executor");
        _;
    }

    modifier onlyMultiSig() {
        require(hasRole(MULTI_SIG_ROLE, msg.sender), "Not multi-sig");
        _;
    }

    modifier onlyUninitialized() {
        require(!initialized, "Already initialized");
        _;
    }

    // ============================
    // CONSTRUCTOR
    // ============================
    constructor(
        address _pscToken,
        address _developerWallet,
        address _founder1,
        address _founder2,
        address _publicDistributionWallet
    ) {
        require(_pscToken != address(0), "Invalid token address");
        require(_developerWallet != address(0), "Invalid developer wallet");
        require(_founder1 != address(0), "Invalid founder1");
        require(_founder2 != address(0), "Invalid founder2");
        require(_publicDistributionWallet != address(0), "Invalid public distribution wallet");

        pscToken = IERC20(_pscToken);
        developerWallet = _developerWallet;
        founder1 = _founder1;
        founder2 = _founder2;
        publicDistributionWallet = _publicDistributionWallet;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(EXECUTOR_ROLE, msg.sender);

        initialized = false;
        lastReleaseTime = INITIAL_RELEASE_DATE;
    }

    // ============================
    // SET TIMELOCK CONTROLLER
    // ============================
    function setTimelockController(address _timelock) external onlyAdmin {
        require(_timelock != address(0), "Invalid timelock address");
        timelockController = _timelock;
        emit TimelockControllerSet(_timelock);
    }

    // ============================
    // INITIALIZE — First-year distribution + role transfer
    // ============================
    /**
     * @notice Perform first-year distribution and transfer roles to Multi-Sig
     * @param multiSigAddress Address of the Multi-Sig wallet
     * @param airdropContract Address of the MerkleAirdrop contract (to receive 4M PSC)
     */
    function initialize(
        address multiSigAddress,
        address airdropContract
    ) external onlyAdmin onlyUninitialized {
        require(multiSigAddress != address(0), "Invalid multi-sig address");
        require(airdropContract != address(0), "Invalid airdrop contract");

        // Verify the treasury holds all tokens
        uint256 balance = pscToken.balanceOf(address(this));
        require(balance == 200_000_000 * 10**18, "Invalid treasury balance");

        // ============================================================
        // FIRST-YEAR DISTRIBUTION (20 million PSC total)
        // ============================================================

        // 1% Team (2M) → developer wallet (managed by developer to distribute)
        pscToken.safeTransfer(developerWallet, TEAM_AMOUNT);

        // 5% Founders (10M) → split equally between founder1 and founder2
        uint256 perFounder = FOUNDERS_AMOUNT / 2;
        pscToken.safeTransfer(founder1, perFounder);
        pscToken.safeTransfer(founder2, perFounder);

        // 2% Airdrop (4M) → MerkleAirdrop contract
        pscToken.safeTransfer(airdropContract, AIRDROP_AMOUNT);

        // 2% Public Offering (4M) → public offering wallet
        pscToken.safeTransfer(publicDistributionWallet, PUBLIC_OFFERING_AMOUNT);

        // Update remaining supply (180 million PSC left in treasury)
        remainingSupply = balance - (TEAM_AMOUNT + FOUNDERS_AMOUNT + AIRDROP_AMOUNT + PUBLIC_OFFERING_AMOUNT);
        require(remainingSupply == 180_000_000 * 10**18, "Invalid remaining supply");

        emit FirstYearDistributed(
            TEAM_AMOUNT,
            perFounder,
            perFounder,
            PUBLIC_OFFERING_AMOUNT
        );

        // ============================================================
        // TRANSFER ALL ROLES TO MULTI-SIG
        // ============================================================
        _grantRole(DEFAULT_ADMIN_ROLE, multiSigAddress);
        _grantRole(ADMIN_ROLE, multiSigAddress);
        _grantRole(EXECUTOR_ROLE, multiSigAddress);
        _grantRole(MULTI_SIG_ROLE, multiSigAddress);

        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _revokeRole(ADMIN_ROLE, msg.sender);
        _revokeRole(EXECUTOR_ROLE, msg.sender);

        initialized = true;
        lastReleaseTime = INITIAL_RELEASE_DATE;

        emit Initialized(msg.sender, multiSigAddress, remainingSupply);
    }

    // ============================
    // ANNUAL RELEASE
    // ============================
    function releaseAnnual() external onlyExecutor nonReentrant {
        require(initialized, "Not initialized");
        require(block.timestamp >= lastReleaseTime + SECONDS_IN_YEAR, "Too early: must wait 1 year");
        require(remainingSupply > 0, "No remaining supply to release");

        uint256 annualAmount = (remainingSupply * ANNUAL_RELEASE_PERCENT) / 100;

        uint256 developerAmount = (annualAmount * DEVELOPER_PERCENT) / 100;
        uint256 foundersAmount = (annualAmount * FOUNDERS_PERCENT) / 100;
        uint256 publicAmount = (annualAmount * PUBLIC_PERCENT) / 100;

        uint256 founder1Amount = foundersAmount / 2;
        uint256 founder2Amount = foundersAmount - founder1Amount;

        pscToken.safeTransfer(developerWallet, developerAmount);
        pscToken.safeTransfer(founder1, founder1Amount);
        pscToken.safeTransfer(founder2, founder2Amount);
        pscToken.safeTransfer(publicDistributionWallet, publicAmount);

        remainingSupply -= annualAmount;
        totalReleased += annualAmount;

        // Fixed time step to prevent calendar drift
        lastReleaseTime += SECONDS_IN_YEAR;

        emit AnnualReleaseExecuted(
            annualAmount,
            developerAmount,
            founder1Amount,
            founder2Amount,
            publicAmount,
            lastReleaseTime + SECONDS_IN_YEAR
        );
    }

    // ============================
    // RESCUE — Only by Multi-Sig
    // ============================
    function rescueTokens(address token, address to) external onlyMultiSig nonReentrant {
        require(to != address(0), "Invalid recipient");
        require(token != address(pscToken), "Cannot rescue PSC tokens");

        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No tokens to rescue");

        IERC20(token).safeTransfer(to, balance);
        emit TokensRescued(token, to, balance);
    }

    // ============================
    // VIEWS
    // ============================
    function getRemainingSupply() external view returns (uint256) {
        return remainingSupply;
    }

    function getTimeUntilNextRelease() external view returns (uint256) {
        if (block.timestamp >= lastReleaseTime + SECONDS_IN_YEAR) {
            return 0;
        }
        return (lastReleaseTime + SECONDS_IN_YEAR) - block.timestamp;
    }

    function getNextReleaseDate() external view returns (uint256) {
        return lastReleaseTime + SECONDS_IN_YEAR;
    }
}

// ============================================================
// CONTRACT 3: MerkleAirdrop — Airdrop with Clawback
// ============================================================
/**
 * @title MerkleAirdrop
 * @notice Merkle Tree-based airdrop with 60-day lock and 365-day vesting
 */
contract MerkleAirdrop is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============================
    // ROLES
    // ============================
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MULTI_SIG_ROLE = keccak256("MULTI_SIG_ROLE");

    // ============================
    // CONSTANTS
    // ============================
    uint256 public constant LOCK_DURATION = 60 days;
    uint256 public constant VESTING_DURATION = 365 days;
    uint256 public constant CLAWBACK_DELAY = 180 days;

    // ============================
    // IMMUTABLE
    // ============================
    IERC20 public immutable pscToken;
    address public immutable treasury;

    // ============================
    // STATE VARIABLES
    // ============================
    bytes32 public merkleRoot;
    uint256 public airdropStartTime;
    uint256 public totalAirdropAmount;
    uint256 public totalClaimedAmount;
    bool public airdropInitialized;
    bool public clawbackExecuted;

    struct ClaimInfo {
        uint256 totalAllocation;
        uint256 claimedAmount;
        uint256 startTime;
    }

    mapping(address => ClaimInfo) public claims;
    mapping(address => bool) public hasClaimed;

    // ============================
    // EVENTS
    // ============================
    event AirdropInitialized(bytes32 indexed merkleRoot, uint256 totalAmount, uint256 startTime);
    event AirdropClaimed(address indexed recipient, uint256 amount, uint256 vestingStartTime);
    event TokensReleased(address indexed recipient, uint256 amount);
    event ClawbackExecuted(uint256 amount, address indexed treasury);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    // ============================
    // MODIFIERS
    // ============================
    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Not admin");
        _;
    }

    modifier onlyMultiSig() {
        require(hasRole(MULTI_SIG_ROLE, msg.sender), "Not multi-sig");
        _;
    }

    // ============================
    // CONSTRUCTOR
    // ============================
    constructor(address _pscToken, address _treasury) {
        require(_pscToken != address(0), "Invalid token address");
        require(_treasury != address(0), "Invalid treasury address");

        pscToken = IERC20(_pscToken);
        treasury = _treasury;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    // ============================
    // INITIALIZE AIRDROP
    // ============================
    function initializeAirdrop(
        bytes32 _merkleRoot,
        uint256 _totalAmount,
        address multiSigAddress
    ) external onlyAdmin {
        require(!airdropInitialized, "Airdrop already initialized");
        require(_merkleRoot != bytes32(0), "Invalid merkle root");
        require(_totalAmount > 0, "Invalid total amount");
        require(multiSigAddress != address(0), "Invalid multi-sig address");

        merkleRoot = _merkleRoot;
        totalAirdropAmount = _totalAmount;
        airdropStartTime = block.timestamp;
        airdropInitialized = true;

        _grantRole(MULTI_SIG_ROLE, multiSigAddress);

        emit AirdropInitialized(_merkleRoot, _totalAmount, airdropStartTime);
    }

    // ============================
    // CLAIM AIRDROP
    // ============================
    function claimAirdrop(uint256 amount, bytes32[] calldata merkleProof) external nonReentrant {
        require(airdropInitialized, "Airdrop not initialized");
        require(!hasClaimed[msg.sender], "Already claimed");
        require(amount > 0, "Amount must be > 0");

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));
        require(MerkleProof.verify(merkleProof, merkleRoot, leaf), "Invalid merkle proof");
        require(pscToken.balanceOf(address(this)) >= amount, "Insufficient contract balance");

        hasClaimed[msg.sender] = true;

        claims[msg.sender] = ClaimInfo({
            totalAllocation: amount,
            claimedAmount: 0,
            startTime: block.timestamp
        });

        emit AirdropClaimed(msg.sender, amount, block.timestamp);
    }

    // ============================
    // RELEASE VESTED TOKENS
    // ============================
    function releaseVested() external nonReentrant {
        require(airdropInitialized, "Airdrop not initialized");

        ClaimInfo storage info = claims[msg.sender];
        require(info.totalAllocation > 0, "No allocation");

        uint256 claimable = _getClaimableAmount(msg.sender);
        require(claimable > 0, "Nothing to claim");

        info.claimedAmount += claimable;
        totalClaimedAmount += claimable;

        pscToken.safeTransfer(msg.sender, claimable);

        emit TokensReleased(msg.sender, claimable);
    }

    // ============================
    // CLAWBACK
    // ============================
    function executeClawback() external onlyMultiSig nonReentrant {
        require(airdropInitialized, "Airdrop not initialized");
        require(!clawbackExecuted, "Clawback already executed");

        uint256 clawbackTime = airdropStartTime + LOCK_DURATION + VESTING_DURATION + CLAWBACK_DELAY;
        require(block.timestamp >= clawbackTime, "Clawback period not reached");

        uint256 unclaimedBalance = pscToken.balanceOf(address(this));
        require(unclaimedBalance > 0, "No unclaimed tokens");

        clawbackExecuted = true;
        pscToken.safeTransfer(treasury, unclaimedBalance);

        emit ClawbackExecuted(unclaimedBalance, treasury);
    }

    // ============================
    // RESCUE
    // ============================
    function rescueTokens(address token, address to) external onlyMultiSig nonReentrant {
        require(to != address(0), "Invalid recipient");
        require(token != address(pscToken), "Cannot rescue PSC tokens");

        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No tokens to rescue");

        IERC20(token).safeTransfer(to, balance);
        emit TokensRescued(token, to, balance);
    }

    // ============================
    // VIEWS
    // ============================
    function _getClaimableAmount(address user) internal view returns (uint256) {
        ClaimInfo storage info = claims[user];
        if (info.totalAllocation == 0) return 0;

        uint256 elapsed = block.timestamp - info.startTime;

        if (elapsed < LOCK_DURATION) return 0;

        if (elapsed >= LOCK_DURATION + VESTING_DURATION) {
            return info.totalAllocation - info.claimedAmount;
        }

        uint256 vestingElapsed = elapsed - LOCK_DURATION;
        uint256 vestedTotal = (info.totalAllocation * vestingElapsed) / VESTING_DURATION;

        if (vestedTotal > info.claimedAmount) {
            return vestedTotal - info.claimedAmount;
        }
        return 0;
    }

    function getClaimableAmount(address user) external view returns (uint256) {
        return _getClaimableAmount(user);
    }

    function getVestedAmount(address user) external view returns (uint256) {
        ClaimInfo storage info = claims[user];
        if (info.totalAllocation == 0) return 0;

        uint256 elapsed = block.timestamp - info.startTime;
        if (elapsed < LOCK_DURATION) return 0;
        if (elapsed >= LOCK_DURATION + VESTING_DURATION) return info.totalAllocation;

        uint256 vestingElapsed = elapsed - LOCK_DURATION;
        return (info.totalAllocation * vestingElapsed) / VESTING_DURATION;
    }

    function getClaimInfo(address user) external view returns (uint256 totalAllocation, uint256 claimedAmount, uint256 startTime) {
        ClaimInfo storage info = claims[user];
        return (info.totalAllocation, info.claimedAmount, info.startTime);
    }

    function getClawbackTime() external view returns (uint256) {
        return airdropStartTime + LOCK_DURATION + VESTING_DURATION + CLAWBACK_DELAY;
    }
}

// ============================================================
// CONTRACT 4: SupplyChainModule — Fee & Burn
// ============================================================
/**
 * @title SupplyChainModule
 * @notice Supply chain fee collection with atomic burn mechanism
 * @dev FIXED: processFee now uses safeTransferFrom to pull fees directly
 *      from the payer's wallet, rather than relying on pre-deposited balances.
 */
contract SupplyChainModule is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============================
    // ROLES
    // ============================
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant MULTI_SIG_ROLE = keccak256("MULTI_SIG_ROLE");

    // ============================
    // CONSTANTS
    // ============================
    uint256 public constant BURN_PERCENT = 10;
    uint256 public constant TREASURY_PERCENT = 90;

    // ============================
    // IMMUTABLE
    // ============================
    IERC20 public immutable pscToken;
    address public immutable treasury;

    // ============================
    // STATE VARIABLES
    // ============================
    uint256 public totalFeesCollected;
    uint256 public totalBurned;
    uint256 public totalToTreasury;

    // ============================
    // EVENTS
    // ============================
    event FeeProcessed(
        address indexed payer,
        uint256 totalAmount,
        uint256 burnedAmount,
        uint256 treasuryAmount
    );
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    // ============================
    // MODIFIERS
    // ============================
    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Not operator");
        _;
    }

    modifier onlyMultiSig() {
        require(hasRole(MULTI_SIG_ROLE, msg.sender), "Not multi-sig");
        _;
    }

    // ============================
    // CONSTRUCTOR
    // ============================
    constructor(address _pscToken, address _treasury, address _multiSig) {
        require(_pscToken != address(0), "Invalid token address");
        require(_treasury != address(0), "Invalid treasury address");
        require(_multiSig != address(0), "Invalid multi-sig address");

        pscToken = IERC20(_pscToken);
        treasury = _treasury;

        _grantRole(DEFAULT_ADMIN_ROLE, _multiSig);
        _grantRole(ADMIN_ROLE, _multiSig);
        _grantRole(OPERATOR_ROLE, _multiSig);
        _grantRole(MULTI_SIG_ROLE, _multiSig);
    }

    // ============================
    // PROCESS FEE — Direct pull from payer
    // ============================
    /**
     * @notice Process fees: pull from payer, burn 10%, transfer 90% to treasury
     * @param payer The address from which fees are collected
     * @param amount The amount of PSC tokens to process
     */
    function processFee(address payer, uint256 amount)
        external
        onlyOperator
        nonReentrant
    {
        require(payer != address(0), "Invalid payer address");
        require(amount > 0, "Amount must be > 0");

        // Pull tokens directly from payer to this contract
        pscToken.safeTransferFrom(payer, address(this), amount);

        uint256 burnAmount = (amount * BURN_PERCENT) / 100;
        uint256 treasuryAmount = amount - burnAmount;

        // Atomic burn — cast to ERC20Burnable to access burn()
        ERC20Burnable(address(pscToken)).burn(burnAmount);

        // Transfer to treasury
        pscToken.safeTransfer(treasury, treasuryAmount);

        totalFeesCollected += amount;
        totalBurned += burnAmount;
        totalToTreasury += treasuryAmount;

        emit FeeProcessed(payer, amount, burnAmount, treasuryAmount);
    }

    // ============================
    // RESCUE
    // ============================
    function rescueTokens(address token, address to) external onlyMultiSig nonReentrant {
        require(to != address(0), "Invalid recipient");
        require(token != address(pscToken), "Cannot rescue PSC tokens");

        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No tokens to rescue");

        IERC20(token).safeTransfer(to, balance);
        emit TokensRescued(token, to, balance);
    }

    // ============================
    // VIEWS
    // ============================
    function getStats() external view returns (uint256 collected, uint256 burned, uint256 toTreasury) {
        return (totalFeesCollected, totalBurned, totalToTreasury);
    }
}
