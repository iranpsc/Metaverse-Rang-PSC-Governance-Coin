// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title PSC (Paradise Supply Chain)
 * @notice Automated distribution architecture with decentralized governance
 * @dev Combines:
 *      - Batch transfer via calldata at initialization time
 *      - Multi-Sig wallet based management
 *      - Merkle Tree for scalable airdrop (supports 1000+ users)
 *      - Removed auto-correction logic for team allocations
 *      - Full role transfer to Multi-Sig after initialization
 *      - Rescue function accessible only via Multi-Sig
 */
contract PSC is ERC20, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    // ============================
    // ROLES
    // ============================
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MULTI_SIG_ROLE = keccak256("MULTI_SIG_ROLE");

    // ============================
    // CONSTANTS
    // ============================
    uint256 public constant TOTAL_SUPPLY = 200_000_000 * 10**18;
    uint256 public constant INITIAL_RELEASE_PERCENT = 10;
    uint256 public constant ANNUAL_RELEASE_PERCENT = 10;
    uint256 public constant SECONDS_IN_YEAR = 365 days;

    uint256 public constant MAX_AIRDROP_RECIPIENTS = 1000;
    uint256 public constant AIRDROP_AMOUNT = (TOTAL_SUPPLY * 2) / 100; // 4,000,000 PSC
    uint256 public constant AIRDROP_LOCK_DURATION = 60 days;
    uint256 public constant AIRDROP_VESTING_DURATION = 365 days;

    uint256 public constant TEAM_PERCENT = 1;
    uint256 public constant FOUNDERS_PERCENT = 4;
    uint256 public constant CONSULTANTS_PERCENT = 1;
    uint256 public constant INITIAL_OFFERING_PERCENT = 2;

    uint256 public constant ANNUAL_DEVELOPER_PERCENT = 1;
    uint256 public constant ANNUAL_FOUNDERS_PERCENT = 4;
    uint256 public constant ANNUAL_CONSULTANTS_PERCENT = 1;
    uint256 public constant ANNUAL_PUBLIC_PERCENT = 4;

    // RELEASE_START_DATE: November 6, 2027 00:00:00 UTC = 1825545600 (15 Aban 1406)
    uint256 public constant RELEASE_START_DATE = 1825545600;

    // ============================
    // MUTABLE WALLETS — Upgradable only by MULTI_SIG_ROLE
    // ============================
    address public developerWallet;
    address public founder1;
    address public founder2;
    address public consultantWallet;
    address public publicOfferingWallet;
    address public publicDistributionWallet;

    // ============================
    // STATE VARIABLES
    // ============================
    uint256 public remainingSupply;
    uint256 public lastReleaseTime;
    bool public airdropDistributed;
    bool public initialized;

    // Merkle Tree for scalable airdrop
    bytes32 public merkleRoot;
    mapping(address => bool) public airdropClaimed;

    // ============================
    // AIRDROP VESTING
    // ============================
    struct AirdropInfo {
        uint256 totalAllocation;
        uint256 claimedAmount;
        uint256 startTime;
    }

    mapping(address => AirdropInfo) public airdropInfo;

    // ============================
    // MODIFIERS
    // ============================
    modifier onlyExecutor() {
        require(hasRole(EXECUTOR_ROLE, msg.sender), "Not executor");
        _;
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Not admin");
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
    // EVENTS
    // ============================
    event InitialDistributionDone(
        uint256 teamAmount,
        uint256 founder1Amount,
        uint256 founder2Amount,
        uint256 consultantAmount,
        uint256 publicOfferingAmount,
        uint256 airdropAmount
    );
    event AnnualReleaseDone(
        uint256 totalReleased,
        uint256 developerAmount,
        uint256 founder1Amount,
        uint256 founder2Amount,
        uint256 consultantAmount,
        uint256 publicAmount
    );
    event AirdropClaimed(address indexed recipient, uint256 amount);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);
    event WalletsUpdated(
        address developer,
        address f1,
        address f2,
        address consultant,
        address offering,
        address distribution
    );
    event Initialized(address indexed by);
    event RolesTransferredToMultiSig(address indexed multiSigAddress);
    event MerkleRootSet(bytes32 indexed merkleRoot, uint256 airdropAmount);

    // ============================
    // CONSTRUCTOR
    // ============================
    constructor()
        ERC20("Paradise Supply Chain", "PSC")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(EXECUTOR_ROLE, msg.sender);

        developerWallet = 0xD47A6b5C4829Ad840890B2df076a4210D96dd1bf;
        founder1 = 0x5496Be16c5098E87F757236E9ba87b487db34b59;
        founder2 = 0x38ABF89F423D18c35770Ca6e0245DADCe08e8Bae;
        consultantWallet = 0x884593e1570DE2C5Aa89d3e93D2d22e8EE2a7416;
        publicOfferingWallet = 0x2f7a74Ab84B87D3aa3B05EDb4454bf149d606404;
        publicDistributionWallet = 0xe80E5D6d3a8C534C29972C9b520ba252e16193Af;

        require(developerWallet != address(0), "Invalid developer wallet");
        require(founder1 != address(0), "Invalid founder1");
        require(founder2 != address(0), "Invalid founder2");
        require(consultantWallet != address(0), "Invalid consultant wallet");
        require(publicOfferingWallet != address(0), "Invalid public offering wallet");
        require(publicDistributionWallet != address(0), "Invalid public distribution wallet");

        airdropDistributed = false;
        initialized = false;
        merkleRoot = bytes32(0);

        _mint(address(this), TOTAL_SUPPLY);
        remainingSupply = TOTAL_SUPPLY;
    }

    // ============================
    // INITIALIZE — Initial distribution via Calldata
    // ============================
    function initialize(
        address[] calldata teamAddresses,
        uint256[] calldata teamAmounts,
        address multiSigAddress
    ) external onlyAdmin onlyUninitialized {
        require(teamAddresses.length == teamAmounts.length, "Team addresses and amounts length mismatch");
        require(teamAddresses.length > 0, "Team must have at least one member");
        require(multiSigAddress != address(0), "Invalid multi-sig address");

        uint256 totalTeamAllocation = 0;
        for (uint256 i = 0; i < teamAddresses.length; ) {
            require(teamAddresses[i] != address(0), "Invalid team address");
            require(teamAmounts[i] > 0, "Team amount must be > 0");
            totalTeamAllocation += teamAmounts[i];
            unchecked { ++i; }
        }

        uint256 targetAllocation = (TOTAL_SUPPLY * TEAM_PERCENT) / 100;
        require(totalTeamAllocation == targetAllocation, "Total team allocation must exactly equal 2,000,000");

        for (uint256 i = 0; i < teamAddresses.length; ) {
            _transfer(address(this), teamAddresses[i], teamAmounts[i]);
            unchecked { ++i; }
        }

        uint256 founderTotalAmount = (TOTAL_SUPPLY * FOUNDERS_PERCENT) / 100;
        uint256 perFounder = founderTotalAmount / 2;
        _transfer(address(this), founder1, perFounder);
        _transfer(address(this), founder2, perFounder);

        uint256 consultantAmount = (TOTAL_SUPPLY * CONSULTANTS_PERCENT) / 100;
        _transfer(address(this), consultantWallet, consultantAmount);

        uint256 publicOfferingAmount = (TOTAL_SUPPLY * INITIAL_OFFERING_PERCENT) / 100;
        _transfer(address(this), publicOfferingWallet, publicOfferingAmount);

        uint256 teamTotalAmount = (TOTAL_SUPPLY * TEAM_PERCENT) / 100;
        uint256 totalDistributed = teamTotalAmount + founderTotalAmount + consultantAmount + publicOfferingAmount;
        remainingSupply = TOTAL_SUPPLY - totalDistributed;

        _grantRole(DEFAULT_ADMIN_ROLE, multiSigAddress);
        _grantRole(ADMIN_ROLE, multiSigAddress);
        _grantRole(EXECUTOR_ROLE, multiSigAddress);
        _grantRole(MULTI_SIG_ROLE, multiSigAddress);

        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _revokeRole(ADMIN_ROLE, msg.sender);
        _revokeRole(EXECUTOR_ROLE, msg.sender);

        emit InitialDistributionDone(
            teamTotalAmount,
            perFounder,
            perFounder,
            consultantAmount,
            publicOfferingAmount,
            AIRDROP_AMOUNT
        );

        emit RolesTransferredToMultiSig(multiSigAddress);

        lastReleaseTime = RELEASE_START_DATE;
        initialized = true;
        emit Initialized(msg.sender);
    }

    // ============================
    // MERKLE TREE — Scalable Airdrop (integrated)
    // ============================
    function setMerkleRoot(bytes32 _merkleRoot) external onlyMultiSig {
        require(!airdropDistributed, "Airdrop already distributed");
        require(_merkleRoot != bytes32(0), "Invalid root");
        require(initialized, "Contract not initialized");

        merkleRoot = _merkleRoot;
        airdropDistributed = true;

        require(remainingSupply >= AIRDROP_AMOUNT, "Insufficient remaining supply for airdrop");
        remainingSupply -= AIRDROP_AMOUNT;

        emit MerkleRootSet(_merkleRoot, AIRDROP_AMOUNT);
    }

    function claimAirdropMerkle(
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external nonReentrant {
        require(merkleRoot != bytes32(0), "Merkle root not set");
        require(!airdropClaimed[msg.sender], "Already claimed");
        require(amount > 0, "Amount must be > 0");

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));

        require(MerkleProof.verify(merkleProof, merkleRoot, leaf), "Invalid merkle proof");

        airdropClaimed[msg.sender] = true;

        airdropInfo[msg.sender] = AirdropInfo({
            totalAllocation: amount,
            claimedAmount: 0,
            startTime: block.timestamp
        });

        emit AirdropClaimed(msg.sender, amount);
    }

    // ============================
    // AIRDROP CLAIM (vesting release)
    // ============================
    function claimAirdrop() external nonReentrant {
        require(airdropDistributed, "Airdrop not distributed yet");

        uint256 claimable = getClaimableAmount(msg.sender);
        require(claimable > 0, "Nothing to claim");

        airdropInfo[msg.sender].claimedAmount += claimable;
        _transfer(address(this), msg.sender, claimable);

        emit AirdropClaimed(msg.sender, claimable);
    }

    // ============================
    // AIRDROP VIEWS
    // ============================
    function getClaimableAmount(address user) public view returns (uint256) {
        AirdropInfo storage info = airdropInfo[user];
        if (info.totalAllocation == 0) return 0;

        uint256 elapsed = block.timestamp - info.startTime;

        if (elapsed < AIRDROP_LOCK_DURATION) {
            return 0;
        }

        if (elapsed >= AIRDROP_LOCK_DURATION + AIRDROP_VESTING_DURATION) {
            return info.totalAllocation - info.claimedAmount;
        }

        uint256 vestingElapsed = elapsed - AIRDROP_LOCK_DURATION;
        uint256 vestedTotal = (info.totalAllocation * vestingElapsed) / AIRDROP_VESTING_DURATION;

        if (vestedTotal > info.claimedAmount) {
            return vestedTotal - info.claimedAmount;
        }
        return 0;
    }

    function getVestedAmount(address user) public view returns (uint256) {
        AirdropInfo storage info = airdropInfo[user];
        if (info.totalAllocation == 0) return 0;

        uint256 elapsed = block.timestamp - info.startTime;

        if (elapsed < AIRDROP_LOCK_DURATION) {
            return 0;
        }

        if (elapsed >= AIRDROP_LOCK_DURATION + AIRDROP_VESTING_DURATION) {
            return info.totalAllocation;
        }

        uint256 vestingElapsed = elapsed - AIRDROP_LOCK_DURATION;
        return (info.totalAllocation * vestingElapsed) / AIRDROP_VESTING_DURATION;
    }

    function getTotalClaimable(address user) public view returns (uint256) {
        AirdropInfo storage info = airdropInfo[user];
        if (info.totalAllocation == 0) return 0;

        uint256 elapsed = block.timestamp - info.startTime;

        if (elapsed < AIRDROP_LOCK_DURATION) {
            return 0;
        }

        if (elapsed >= AIRDROP_LOCK_DURATION + AIRDROP_VESTING_DURATION) {
            return info.totalAllocation - info.claimedAmount;
        }

        uint256 vestingElapsed = elapsed - AIRDROP_LOCK_DURATION;
        uint256 vestedTotal = (info.totalAllocation * vestingElapsed) / AIRDROP_VESTING_DURATION;

        if (vestedTotal > info.claimedAmount) {
            return vestedTotal - info.claimedAmount;
        }
        return 0;
    }

    function getAirdropInfo(address user) external view returns (uint256 totalAllocation, uint256 claimedAmount, uint256 startTime) {
        AirdropInfo storage info = airdropInfo[user];
        return (info.totalAllocation, info.claimedAmount, info.startTime);
    }

    // ============================
    // UPDATE WALLETS — Only by MULTI_SIG_ROLE
    // ============================
    function setWallets(
        address _developerWallet,
        address _founder1,
        address _founder2,
        address _consultantWallet,
        address _publicOfferingWallet,
        address _publicDistributionWallet
    ) external onlyMultiSig {
        require(_developerWallet != address(0), "Invalid developer wallet");
        require(_founder1 != address(0), "Invalid founder1");
        require(_founder2 != address(0), "Invalid founder2");
        require(_consultantWallet != address(0), "Invalid consultant wallet");
        require(_publicOfferingWallet != address(0), "Invalid public offering wallet");
        require(_publicDistributionWallet != address(0), "Invalid public distribution wallet");

        developerWallet = _developerWallet;
        founder1 = _founder1;
        founder2 = _founder2;
        consultantWallet = _consultantWallet;
        publicOfferingWallet = _publicOfferingWallet;
        publicDistributionWallet = _publicDistributionWallet;

        emit WalletsUpdated(
            _developerWallet,
            _founder1,
            _founder2,
            _consultantWallet,
            _publicOfferingWallet,
            _publicDistributionWallet
        );
    }

    // ============================
    // ANNUAL RELEASE — Only by EXECUTOR_ROLE (Multi-Sig)
    // ============================
    function releaseAnnual() external onlyExecutor nonReentrant {
        require(initialized, "Contract not initialized");
        require(block.timestamp >= lastReleaseTime + SECONDS_IN_YEAR, "Too early: must wait 1 year");
        require(remainingSupply > 0, "No remaining supply to release");
        require(airdropDistributed, "Airdrop must be set first");

        uint256 annualAmount = (remainingSupply * ANNUAL_RELEASE_PERCENT) / 100;

        uint256 developerAmount = (remainingSupply * ANNUAL_DEVELOPER_PERCENT) / 100;
        _transfer(address(this), developerWallet, developerAmount);

        uint256 founderTotalAmount = (remainingSupply * ANNUAL_FOUNDERS_PERCENT) / 100;
        uint256 perFounder = founderTotalAmount / 2;
        _transfer(address(this), founder1, perFounder);
        _transfer(address(this), founder2, perFounder);

        uint256 consultantAmount = (remainingSupply * ANNUAL_CONSULTANTS_PERCENT) / 100;
        _transfer(address(this), consultantWallet, consultantAmount);

        uint256 publicAmount = (remainingSupply * ANNUAL_PUBLIC_PERCENT) / 100;
        _transfer(address(this), publicDistributionWallet, publicAmount);

        remainingSupply -= annualAmount;
        lastReleaseTime = block.timestamp;

        emit AnnualReleaseDone(
            annualAmount,
            developerAmount,
            perFounder,
            perFounder,
            consultantAmount,
            publicAmount
        );
    }

    // ============================
    // RESCUE — Only by MULTI_SIG_ROLE
    // ============================
    function rescueTokens(address token, address to) external onlyMultiSig nonReentrant {
        require(to != address(0), "Invalid recipient");
        require(token != address(this), "Cannot rescue PSC tokens");

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

    function getCirculatingSupply() external view returns (uint256) {
        return totalSupply() - remainingSupply;
    }

    function getAirdropAmountPerRecipient(uint256 recipientsCount) external pure returns (uint256) {
        require(recipientsCount > 0 && recipientsCount <= MAX_AIRDROP_RECIPIENTS, "Invalid count");
        return AIRDROP_AMOUNT / recipientsCount;
    }
}
