// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title MerkleAirdrop
 * @notice Merkle-tree airdrop with 90-day claim window, 60-day cliff,
 *         and 365-day linear vesting synchronized from airdrop launch.
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
    error CannotRescuePSCTokens();

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
    }

    mapping(address => ClaimInfo) public claims;
    mapping(address => bool) public hasClaimed;

    event AirdropInitialized(bytes32 indexed merkleRoot, uint256 totalAmount, uint256 startTime);
    event AirdropClaimed(address indexed recipient, uint256 amount);
    event TokensReleased(address indexed recipient, uint256 amount);
    event ClawbackExecuted(uint256 amountClawedBack, address indexed treasury);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    constructor(address _pscToken, address _treasury) {
        if (_pscToken == address(0) || _treasury == address(0)) {
            revert InvalidAddress();
        }
        pscToken = IERC20(_pscToken);
        treasury = _treasury;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function initializeAirdrop(
        bytes32 _merkleRoot,
        uint256 _totalAmount,
        address _timelock
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (airdropInitialized) revert AirdropNotActive();
        if (_merkleRoot == bytes32(0) || _totalAmount == 0 || _timelock == address(0)) revert InvalidAddress();
        if (pscToken.balanceOf(address(this)) < _totalAmount) revert InsufficientContractBalance();

        merkleRoot = _merkleRoot;
        totalAirdropAmount = _totalAmount;
        airdropStartTime = block.timestamp;
        airdropInitialized = true;

        _grantRole(DEFAULT_ADMIN_ROLE, _timelock);
        _grantRole(TIMELOCK_ROLE, _timelock);
        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);

        emit AirdropInitialized(_merkleRoot, _totalAmount, block.timestamp);
    }

    function claimAirdrop(uint256 amount, bytes32[] calldata merkleProof) external nonReentrant {
        if (!airdropInitialized) revert AirdropNotActive();
        if (block.timestamp > airdropStartTime + CLAIM_WINDOW) revert ClaimWindowClosed();
        if (hasClaimed[msg.sender]) revert AlreadyClaimed();
        if (amount == 0 || amount > type(uint128).max) revert ZeroAllocation();

        uint256 newTotalClaimed = totalAllocatedClaimed + amount;
        if (newTotalClaimed > totalAirdropAmount) revert InsufficientContractBalance();

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender, amount))));
        if (!MerkleProof.verify(merkleProof, merkleRoot, leaf)) revert InvalidMerkleProof();

        hasClaimed[msg.sender] = true;
        totalAllocatedClaimed = newTotalClaimed;

        claims[msg.sender] = ClaimInfo({
            totalAllocation: uint128(amount),
            claimedAmount: 0
        });

        emit AirdropClaimed(msg.sender, amount);
    }

    function releaseVested() external nonReentrant {
        if (!airdropInitialized) revert AirdropNotActive();

        ClaimInfo storage info = claims[msg.sender];
        if (info.totalAllocation == 0) revert ZeroAllocation();

        uint256 claimable = _getClaimableAmount(msg.sender);
        if (claimable == 0) revert NothingToRelease();

        unchecked {
            info.claimedAmount += uint128(claimable);
            totalDistributed += claimable;
        }

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

        uint256 clawbackAmount;
        unchecked {
            clawbackAmount = currentBalance - activeVestingObligations;
        }
        clawbackExecuted = true;

        pscToken.safeTransfer(treasury, clawbackAmount);
        emit ClawbackExecuted(clawbackAmount, treasury);
    }

    function rescueTokens(address token, address to) external onlyRole(TIMELOCK_ROLE) nonReentrant {
        if (to == address(0)) revert InvalidAddress();
        if (token == address(pscToken)) revert CannotRescuePSCTokens();

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) revert NothingToRelease();

        IERC20(token).safeTransfer(to, balance);
        emit TokensRescued(token, to, balance);
    }

    function _getClaimableAmount(address user) internal view returns (uint256) {
        ClaimInfo memory info = claims[user];
        if (info.totalAllocation == 0) return 0;

        uint256 unlockTime = airdropStartTime + LOCK_DURATION;
        if (block.timestamp < unlockTime) return 0;

        uint256 elapsed;
        unchecked {
            elapsed = block.timestamp - unlockTime;
        }

        if (elapsed >= VESTING_DURATION) {
            return uint256(info.totalAllocation) - uint256(info.claimedAmount);
        }

        uint256 totalVested = (uint256(info.totalAllocation) * elapsed) / VESTING_DURATION;

        if (totalVested > info.claimedAmount) {
            unchecked {
                return totalVested - info.claimedAmount;
            }
        }
        return 0;
    }

    function getClaimableAmount(address user) external view returns (uint256) {
        return _getClaimableAmount(user);
    }
}