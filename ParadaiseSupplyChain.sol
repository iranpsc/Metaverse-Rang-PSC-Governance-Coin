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

// ============================================================
// CONTRACT 1: PSCToken — Base ERC20 with Burnable & Permit
// ============================================================
/**
 * @title PSCToken (Paradise Supply Chain Token)
 * @notice Standard ERC20 token with Burnable and Permit extensions
 * @dev Based on OpenZeppelin v5:
 *      - ERC20: base token standard
 *      - ERC20Burnable: supports burning (for 10% fee burn mechanism)
 *      - ERC20Permit (EIP-2612): gasless approvals via signatures
 *
 * Total supply is minted at deployment and transferred to the Treasury contract.
 * No further minting is possible.
 */
contract PSCToken is ERC20, ERC20Burnable, ERC20Permit {
    // ============================
    // CONSTANTS
    // ============================
    uint256 public constant TOTAL_SUPPLY = 200_000_000 * 10**18; // 200 million PSC

    // ============================
    // IMMUTABLE
    // ============================
    address public immutable treasury;

    // ============================
    // EVENTS
    // ============================
    event TreasurySet(address indexed treasury);

    // ============================
    // CONSTRUCTOR
    // ============================
    /**
     * @param _treasury Address of the Treasury contract that will hold all tokens
     */
    constructor(address _treasury)
        ERC20("Paradise Supply Chain", "PSC")
        ERC20Permit("Paradise Supply Chain")
    {
        require(_treasury != address(0), "Invalid treasury address");
        treasury = _treasury;

        // Mint entire supply to the Treasury contract
        _mint(_treasury, TOTAL_SUPPLY);

        emit TreasurySet(_treasury);
    }

    // ============================
    // OVERRIDES
    // ============================
    /**
     * @dev Override required by Solidity for multiple inheritance
     */
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20)
    {
        super._update(from, to, value);
    }

    /**
     * @dev Override required by Solidity for multiple inheritance
     */
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
 * @notice Treasury contract for PSC token with annual exponential decay release
 * @dev Manages:
 *      - Annual release of 10% of remaining supply
 *      - Multi-Sig based governance
 *      - Timelock for critical operations (48 hours)
 *      - Fixed calendar-based release dates (no time drift)
 */
contract PSCTreasury is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============================
    // ROLES
    // ============================
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant MULTI_SIG_ROLE = keccak256("MULTI_SIG_ROLE");
    bytes32 public constant TIMELOCK_ROLE = keccak256("TIMELOCK_ROLE");

    // ============================
    // CONSTANTS
    // ============================
    uint256 public constant SECONDS_IN_YEAR = 365 days;
    uint256 public constant TIMELOCK_DURATION = 48 hours;

    uint256 public constant ANNUAL_RELEASE_PERCENT = 10;   // 10% of remaining
    uint256 public constant DEVELOPER_PERCENT = 10;        // 10% of released amount
    uint256 public constant FOUNDERS_PERCENT = 50;         // 50% of released amount
    uint256 public constant PUBLIC_PERCENT = 40;           // 40% of released amount

    // Fixed calendar release date: August 23, 2027 = 1818979200
    uint256 public constant INITIAL_RELEASE_DATE = 1818979200;

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

    // Timelock operations
    struct TimelockOperation {
        bytes32 operationHash;
        uint256 executeAfter;
        bool executed;
        bool cancelled;
    }

    mapping(bytes32 => TimelockOperation) public timelockOperations;
    bytes32[] public pendingOperations;

    // ============================
    // EVENTS
    // ============================
    event Initialized(address indexed by, address multiSigAddress, uint256 initialSupply);
    event AnnualReleaseExecuted(
        uint256 totalReleased,
        uint256 developerAmount,
        uint256 founder1Amount,
        uint256 founder2Amount,
        uint256 publicAmount,
        uint256 nextReleaseTime
    );
    event TimelockScheduled(bytes32 indexed operationHash, uint256 executeAfter, bytes data);
    event TimelockExecuted(bytes32 indexed operationHash);
    event TimelockCancelled(bytes32 indexed operationHash);
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
    // INITIALIZE
    // ============================
    function initialize(address multiSigAddress) external onlyAdmin onlyUninitialized {
        require(multiSigAddress != address(0), "Invalid multi-sig address");

        remainingSupply = pscToken.balanceOf(address(this));

        _grantRole(DEFAULT_ADMIN_ROLE, multiSigAddress);
        _grantRole(ADMIN_ROLE, multiSigAddress);
        _grantRole(EXECUTOR_ROLE, multiSigAddress);
        _grantRole(MULTI_SIG_ROLE, multiSigAddress);
        _grantRole(TIMELOCK_ROLE, multiSigAddress);

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

        // FIXED: Fixed time step to prevent drift
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
    // TIMELOCK
    // ============================
    function scheduleOperation(bytes calldata data, bytes32 salt) external onlyMultiSig returns (bytes32) {
        bytes32 operationHash = keccak256(abi.encode(data, salt));
        require(timelockOperations[operationHash].executeAfter == 0, "Operation already scheduled");

        uint256 executeAfter = block.timestamp + TIMELOCK_DURATION;

        timelockOperations[operationHash] = TimelockOperation({
            operationHash: operationHash,
            executeAfter: executeAfter,
            executed: false,
            cancelled: false
        });

        pendingOperations.push(operationHash);

        emit TimelockScheduled(operationHash, executeAfter, data);
        return operationHash;
    }

    function executeOperation(bytes calldata data, bytes32 salt) external onlyMultiSig nonReentrant {
        bytes32 operationHash = keccak256(abi.encode(data, salt));
        TimelockOperation storage op = timelockOperations[operationHash];

        require(op.executeAfter != 0, "Operation not scheduled");
        require(!op.executed, "Already executed");
        require(!op.cancelled, "Operation cancelled");
        require(block.timestamp >= op.executeAfter, "Timelock not expired");

        op.executed = true;

        (bool success, ) = address(this).call(data);
        require(success, "Operation execution failed");

        emit TimelockExecuted(operationHash);
    }

    function cancelOperation(bytes32 operationHash) external onlyMultiSig {
        TimelockOperation storage op = timelockOperations[operationHash];
        require(op.executeAfter != 0, "Operation not scheduled");
        require(!op.executed, "Already executed");
        require(!op.cancelled, "Already cancelled");

        op.cancelled = true;
        emit TimelockCancelled(operationHash);
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
 * @notice Merkle Tree-based airdrop with vesting and clawback
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
 * @dev Features:
 *      - Collects fees in PSC tokens
 *      - Atomically burns 10% of collected fees
 *      - Transfers 90% to treasury
 *      - Multi-Sig controlled
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
    event FeeProcessed(address indexed payer, uint256 totalAmount, uint256 burnedAmount, uint256 treasuryAmount);
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
    // PROCESS FEE
    // ============================
    /**
     * @notice Process collected fees: burn 10%, transfer 90% to treasury
     * @param amount The amount of PSC tokens to process
     */
    function processFee(uint256 amount) external onlyOperator nonReentrant {
        require(amount > 0, "Amount must be > 0");
        require(pscToken.balanceOf(address(this)) >= amount, "Insufficient balance");

        uint256 burnAmount = (amount * BURN_PERCENT) / 100;
        uint256 treasuryAmount = amount - burnAmount;

        // Atomic burn — cast to ERC20Burnable to access burn()
        ERC20Burnable(address(pscToken)).burn(burnAmount);

        // Transfer to treasury
        pscToken.safeTransfer(treasury, treasuryAmount);

        totalFeesCollected += amount;
        totalBurned += burnAmount;
        totalToTreasury += treasuryAmount;

        emit FeeProcessed(msg.sender, amount, burnAmount, treasuryAmount);
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
