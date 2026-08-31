// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title PSC (Paradaise Supply Chain)
 * @notice Fully decentralized token with automated annual release and immutable wallets
 * @dev No owner, no pause, no wallet changes after deployment.
 *      Anyone can trigger annual release (timelocked to 365 days).
 *      Airdrop is protected by owner-only access.
 * 
 * @dev Distribution (Year 1):
 *      - Team: 1% → sent directly to developer wallet (no 58-loop)
 *      - Founders: 4% (2 founders, 2% each)
 *      - Consultants: 1% (single wallet)
 *      - Airdrop: 2% (manual list, owner-only)
 *      - Public Offering: 2% (Uniswap initial liquidity)
 * 
 * @dev Annual Release (Year 2+):
 *      - Developer: 1%
 *      - Founders: 4% (2% each)
 *      - Consultants: 1%
 *      - Public Distribution: 4%
 */
contract PSC is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============================
    // CONSTANTS
    // ============================
    uint256 public constant TOTAL_SUPPLY = 200_000_000 * 10**18;
    uint256 public constant INITIAL_RELEASE_PERCENT = 10;
    uint256 public constant ANNUAL_RELEASE_PERCENT = 10;
    uint256 public constant SECONDS_IN_YEAR = 365 days;

    uint256 public constant MAX_AIRDROP_RECIPIENTS = 1000;
    uint256 public constant AIRDROP_AMOUNT = (TOTAL_SUPPLY * 2) / 100;
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

    // ✅ تایم‌استمپ اصلاح‌شده
    uint256 public constant RELEASE_START_DATE = 1740000000; // Aug 23, 2027

    // ============================
    // OWNER (برای کنترل دسترسی ایردراپ)
    // ============================
    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    // ============================
    // IMMUTABLE WALLETS
    // ============================
    address public immutable developerWallet;
    address public immutable founder1;
    address public immutable founder2;
    address public immutable consultantWallet;
    address public immutable publicOfferingWallet;
    address public immutable publicDistributionWallet;

    // ============================
    // STATE VARIABLES
    // ============================
    uint256 public remainingSupply;
    uint256 public lastReleaseTime;
    bool public airdropDistributed;

    // ============================
    // AIRDROP VESTING
    // ============================
    struct AirdropInfo {
        uint256 totalAllocation;
        uint256 claimedAmount;
        uint256 startTime;
    }

    mapping(address => AirdropInfo) public airdropInfo;
    address[] public airdropRecipients;

    // ============================
    // EVENTS
    // ============================
    event InitialDistributionDone(uint256 teamAmount, uint256 founder1Amount, uint256 founder2Amount, uint256 consultantAmount, uint256 publicOfferingAmount, uint256 airdropAmount);
    event AnnualReleaseDone(uint256 totalReleased, uint256 developerAmount, uint256 founder1Amount, uint256 founder2Amount, uint256 consultantAmount, uint256 publicAmount);
    event AirdropDistributed(address[] recipients, uint256 eachAmount, uint256 lockDuration, uint256 vestingDuration);
    event AirdropClaimed(address indexed recipient, uint256 amount);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ============================
    // CONSTRUCTOR — بدون حلقه‌ی ۵۸ تایی
    // ============================
    constructor()
        ERC20("Paradaise Supply Chain", "PSC")
    {
        owner = msg.sender;

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

        // ════════════════════════════════════════════════════════════
        // توزیع اولیه — بدون حلقه‌ی ۵۸ تایی
        // ۱٪ تیم → مستقیماً به کیف‌پول توسعه‌دهنده
        // ════════════════════════════════════════════════════════════

        // 1% — Team (مستقیماً به developerWallet)
        uint256 teamTotalAmount = (TOTAL_SUPPLY * TEAM_PERCENT) / 100;
        _mint(developerWallet, teamTotalAmount);

        // 4% — Founders (2% each)
        uint256 founderTotalAmount = (TOTAL_SUPPLY * FOUNDERS_PERCENT) / 100;
        uint256 perFounder = founderTotalAmount / 2;
        _mint(founder1, perFounder);
        _mint(founder2, perFounder);

        // 1% — Consultants
        uint256 consultantAmount = (TOTAL_SUPPLY * CONSULTANTS_PERCENT) / 100;
        _mint(consultantWallet, consultantAmount);

        // 2% — Public Offering
        uint256 publicOfferingAmount = (TOTAL_SUPPLY * INITIAL_OFFERING_PERCENT) / 100;
        _mint(publicOfferingWallet, publicOfferingAmount);

        // محاسبه‌ی موجودی باقی‌مانده
        uint256 totalDistributed = teamTotalAmount + founderTotalAmount + consultantAmount + publicOfferingAmount;
        remainingSupply = TOTAL_SUPPLY - totalDistributed;

        // ضرب باقی‌مانده به خود قرارداد
        _mint(address(this), remainingSupply);

        emit InitialDistributionDone(
            teamTotalAmount,
            perFounder,
            perFounder,
            consultantAmount,
            publicOfferingAmount,
            AIRDROP_AMOUNT
        );

        lastReleaseTime = RELEASE_START_DATE;
    }

    // ============================
    // TRANSFER OWNERSHIP
    // ============================
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner is zero address");
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    // ============================
    // AIRDROP — فقط توسط OWNER قابل اجراست
    // ============================
    function distributeAirdrop(address[] calldata recipients) external onlyOwner nonReentrant {
        require(!airdropDistributed, "Airdrop already distributed");
        require(recipients.length > 0 && recipients.length <= MAX_AIRDROP_RECIPIENTS, "Invalid recipients count");

        uint256 eachAmount = AIRDROP_AMOUNT / recipients.length;
        require(eachAmount > 0, "Amount per recipient is too small");
        require(balanceOf(address(this)) >= AIRDROP_AMOUNT, "Insufficient balance in contract");

        uint256 length = recipients.length;
        for (uint256 i = 0; i < length; ) {
            address recipient = recipients[i];
            require(recipient != address(0), "Invalid recipient address");

            airdropInfo[recipient] = AirdropInfo({
                totalAllocation: eachAmount,
                claimedAmount: 0,
                startTime: block.timestamp
            });
            airdropRecipients.push(recipient);
            unchecked { ++i; }
        }

        remainingSupply -= AIRDROP_AMOUNT;
        airdropDistributed = true;

        emit AirdropDistributed(recipients, eachAmount, AIRDROP_LOCK_DURATION, AIRDROP_VESTING_DURATION);
    }

    // ============================
    // AIRDROP CLAIM
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

    function getAirdropRecipientsCount() external view returns (uint256) {
        return airdropRecipients.length;
    }

    function getAirdropRecipients() external view returns (address[] memory) {
        return airdropRecipients;
    }

    // ============================
    // ANNUAL RELEASE — Anyone can call, timelocked to 365 days
    // ============================
    function releaseAnnual() public nonReentrant {
        require(block.timestamp >= lastReleaseTime + SECONDS_IN_YEAR, "Too early: must wait 1 year");
        require(remainingSupply > 0, "No remaining supply to release");
        require(airdropDistributed, "Airdrop must be distributed first");

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
    // RESCUE — Only non‑PSC tokens
    // ============================
    function rescueTokens(address token, address to) external nonReentrant {
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