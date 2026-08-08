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
 *      Airdrop recipients are passed manually at distribution time.
 * 
 * @dev Distribution (Year 1):
 *      - Team: 1% (58 members)
 *      - Founders: 4% (2 founders, 2% each)
 *      - Consultants: 1% (single wallet)
 *      - Airdrop: 2% (manual list)
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

    // Year 1 Distribution Percentages
    uint256 public constant TEAM_PERCENT = 1;
    uint256 public constant FOUNDERS_PERCENT = 4;      // 4% total (2% each)
    uint256 public constant CONSULTANTS_PERCENT = 1;    // 1% to consultants wallet
    uint256 public constant INITIAL_OFFERING_PERCENT = 2;

    // Annual Release Percentages (from remaining supply)
    uint256 public constant ANNUAL_DEVELOPER_PERCENT = 1;
    uint256 public constant ANNUAL_FOUNDERS_PERCENT = 4;    // 4% total (2% each)
    uint256 public constant ANNUAL_CONSULTANTS_PERCENT = 1; // 1% to consultants
    uint256 public constant ANNUAL_PUBLIC_PERCENT = 4;

    uint256 public constant RELEASE_START_DATE = 1724284800; // Aug 23, 2027

    // ============================
    // IMMUTABLE WALLETS (set once, never change)
    // ============================
    address public immutable developerWallet;
    address public immutable founder1;
    address public immutable founder2;
    address public immutable consultantWallet;          // ✅ NEW: 1% to consultants
    address public immutable publicOfferingWallet;
    address public immutable publicDistributionWallet;

    // ============================
    // TEAM MEMBERS (58 addresses with full details)
    // ============================
    address[] private TEAM_ADDRESSES = [
        // ===== Development Team (9 members) =====
        0x13C31F9B11AeCA3cE989A00C3E26C6d429d67C88, // Abbas Ajorlo
        0x370FafefDE558D6830a064D52C7f1e4198E0e453, // Ali Khani
        0xd46EC90073F37EADF3Ba6Cef880666e16b0027dC, // Ramtin Golben
        0xac4B2e88b43962bB8Abd1D53f27d4BD5dB6cF19C, // Mohammad Amir Kheradmand
        0xe081c7F619633493E168Fb1134CFabAE52e3cC29, // Mahan Jamali
        0x2a3e069FFaFc915796a97C18C3504632EB95CdFF, // Mohammad Saleh Hemmati
        0xc6865b8402f7d87089372c1e42dB77201668b6De, // Amir Hossein Amini
        0x1829cb039A429FF8e89657aAFdD45704B7Bd08A2, // Parham Aminloo
        0xd8412BE075EC223a81b7392c14aD0B642d50D818, // Mobina Nematy
        // ===== Frontend & UI/UX (14 members) =====
        0x1a8E19974E522Ff8171080F7979073d53bA0Df8D, // Amin Dehghannejad
        0xaf45634d04973786D16b19637498E370182531bE, // Parsa Bahrami
        0x6B3b636FDe6a9304541103C0a4E63894E4ff1aFC, // Reyhaneh Ghanbari
        0x5Ef7Bc8045DDE0440564A4977B9D06E4Bf460E5B, // Amir Mohseni
        0xf9cbcf9472f012e225871aE0e737abA22FEAF94C, // Helia Idehloo
        0x3AFaF4551c2B937c0f8ef8f9E8DF6cb421794c9e, // Mehdi Gholamhosseini
        0xA400905e502f8Ef9ce0a0015D8aC261eB5a43BaE, // Mohammadreza Vahabi
        0xEaDA44094abBc1E501167f124489B697f8fB2351, // Yousef Khodri
        0x4194e119880cBD7d40621327A9294F19826AC48D, // Ehsan Markazi
        0x08434e1b7e240dEC4df6b015563b49A888fa8FBA, // Abolfazl Vedaeian
        0x24911C287a8E56930e54E6c75f0142478Cf6ba77, // Seyed Mohammadreza Naghipour
        0x42103977D4355d913930b4cB2fad2445A8DCd8a1, // Kasra Ardakani
        0x92e10341dcDF40e957520DcCE4076D2b58083e40, // Kianoush Karjibani
        0x06BB67e27796f40F1871D58e3C1d03f37915BaEa, // Aytay Maleki
        // ===== UI/UX Design (3 members) =====
        0x32cd648720B1092ae257093c6124f2C1A00d7745, // Mohammadreza Asghari
        0x7B17D6f14d27be7a405015C6C823bB82411090C2, // Mohammad Hossein Baghalha
        0x703Af6A7A9FB6088d887e4B17147F2baF3aE6659, // Mehdi Ghorbanzadeh
        // ===== Management & Prompt (4 members) =====
        0x7367c473Aa39dbfcCe1f20B2b7A6eea2b993442c, // Marzieh Sagheb Alizadeh
        0x7c0557C674871bb5e898A69f8b4d4ed86C25f2d7, // Tanin Anbasati
        0xe02691fA092c2874719962c8e046fE93c072006D, // Mohammad Falah Sheykhlari
        0xB5169259FbaF35174954a1CDBCd4cc7A5A6a1687, // Zahra Mohammadi
        // ===== Game Development & 3D (8 members) =====
        0xd194B36bcF4872303FD1f27e442DB04494B7a846, // Mohammad Javad Garaei
        0x60f36385E8B584bf983830D6C3b97ed13C670a37, // Siamak Saadatpour
        0x2b648129BebdB9E29A93e0b607fba280361b4815, // Benyamin Nouri
        0x7e6b5E8772EC51B83ddCCE0caA0B8445081A1E09, // Arman Yeganehkhah
        0xAf083804eCd488B722D1aedD2A962BB7DDddcb5F, // Amirali Dolati
        0x540fB674160e0aed8180e626438D154D6D9052D9, // Erfaneh Jokar
        0xe4D4b6fA97b813c30A3fAF7C98bA39eFEb2cDDbb, // Anahita Karami
        0x24B10361E6b48ebCD736D50e7d478e897E1f9d03, // Amirhossein Emamgholi
        // ===== Founders & Board (9 members) =====
        0x5496Be16c5098E87F757236E9ba87b487db34b59, // Hossein Ghadiri
        0xfF89C699C93F0BfB9FBE6d328E911a6Ba17b656b, // Parvin Saeidi
        0xD437b46d330B9DfcFc70E6E4Aee76b8DF9F81637, // Mostafa Ghadiri
        0x1a97F949B5dc4674d6eC1FFa98fb6298c96B2068, // Abolfazl Ghadiri
        0xF2BEc95049CDc30F1011D006eE170a31A538B033, // Majid Khalegha
        0x863408DdEC15dDb6e4b6f4574aD3d510246EB718, // Afshin Vaezi
        0x38ABF89F423D18c35770Ca6e0245DADCe08e8Bae, // Amir Madani Far
        0x782f1c52f5ACE3F0eb84933c03A28F3B62130B29, // Kioumars Mohammadi
        // ===== AI & Content (9 members) =====
        0x4AD8E256C6A8d07958D22aE7EDf3827807F3942E, // Vahid Sadri
        0x151b28b72b71CB8F9875b5A0fA6520d28Aa8CE4E, // Fatemeh Nasiri
        0x06c056FcCaD76D401cCD94105b02F7F99f3319a8, // Nazanin Heshmati
        0x70bF5Df9AafBE5CE8822322767916246d8da84Da, // Saeed Zajkani
        0x8EFAe745a063F7E587A34aaEE61630c4D435333B, // Majid Majidi
        0x7ce09d075156487DCd59B1a48E359613d634A8bC, // Amin Habibi Anbuhi
        0xde59431E70981c8c6722CaE4f9B5720988C35b37, // Behdad Bahadvand
        0x6CB0a5f838a80D42ef852dee312Fb861277D46Ab, // Hossein Nasiri
        0xC78D24c971E3d324830d6B3b1C598141D2D1D868, // Sina Sheikhi
        // ===== Blockchain (3 members) =====
        0x7b8F6BC781df2040CB38C6B734B40973Cb3a05e0, // Parsa Abolhasani Rad
        0x295514b1462EAFeb5B10cF7Eb439194f178c4d86, // Mohammad Ghiasvand
        0x319999319dF38ce00Ec43208F4DAdaF61310b7f6  // Ali Nasirloo
    ];

    uint256[] private TEAM_AMOUNTS = [
        52390 * 10**18 + (54555 * 10**13),
        40013 * 10**18 + (94255 * 10**13),
        14262 * 10**18 + (9495 * 10**15),
        14232 * 10**18 + (24058 * 10**15),
        14033 * 10**18 + (21146 * 10**15),
        14222 * 10**18 + (28912 * 10**15),
        30395 * 10**18 + (2479 * 10**17),
        31884 * 10**18 + (46485 * 10**15),
        44324 * 10**18 + (8905 * 10**17),
        57920 * 10**18 + (79076 * 10**15),
        50785 * 10**18 + (59685 * 10**15),
        10999 * 10**18 + (67597 * 10**15),
        36193 * 10**18 + (44528 * 10**15),
        11099 * 10**18 + (19053 * 10**15),
        49884 * 10**18 + (62151 * 10**15),
        10999 * 10**18 + (67597 * 10**15),
        47585 * 10**18 + (9804 * 10**17),
        37933 * 10**18 + (56792 * 10**15),
        14630 * 10**18 + (29882 * 10**15),
        14082 * 10**18 + (96874 * 10**15),
        13983 * 10**18 + (45418 * 10**15),
        10101 * 10**18 + (28064 * 10**15),
        43055 * 10**18 + (52701 * 10**15),
        34906 * 10**18 + (39031 * 10**15),
        14092 * 10**18 + (9202 * 10**17),
        33462 * 10**18 + (32348 * 10**15),
        59343 * 10**18 + (84896 * 10**15),
        39125 * 10**18 + (80763 * 10**15),
        34825 * 10**18 + (12009 * 10**17),
        43708 * 10**18 + (45309 * 10**15),
        50672 * 10**18 + (44511 * 10**15),
        21145 * 10**18 + (18531 * 10**15),
        52701 * 10**18 + (80498 * 10**15),
        21905 * 10**18 + (91883 * 10**15),
        16515 * 10**18 + (54686 * 10**15),
        27988 * 10**18 + (10128 * 10**17),
        14033 * 10**18 + (21146 * 10**15),
        29001 * 10**18 + (30692 * 10**15),
        60538 * 10**18 + (2368 * 10**17),
        54069 * 10**18 + (57731 * 10**15),
        54069 * 10**18 + (57731 * 10**15),
        54069 * 10**18 + (57731 * 10**15),
        54069 * 10**18 + (57731 * 10**15),
        54069 * 10**18 + (57731 * 10**15),
        58202 * 10**18 + (19582 * 10**17),
        54069 * 10**18 + (57731 * 10**15),
        28014 * 10**18 + (45421 * 10**15),
        54472 * 10**18 + (88771 * 10**15),
        32967 * 10**18 + (1464 * 10**18),
        46937 * 10**18 + (70055 * 10**15),
        23351 * 10**18 + (9138 * 10**17),
        30929 * 10**18 + (67794 * 10**15),
        30929 * 10**18 + (67794 * 10**15),
        30929 * 10**18 + (67794 * 10**15),
        30929 * 10**18 + (67794 * 10**15),
        33083 * 10**18 + (6153 * 10**17),
        24603 * 10**18 + (3982 * 10**17),
        31251 * 10**18 + (16525 * 10**15)
    ];

    // ============================
    // STATE VARIABLES
    // ============================
    uint256 public remainingSupply;
    uint256 public lastReleaseTime;
    bool public airdropDistributed;

    address[] public teamMembers;
    mapping(address => uint256) public teamAllocations;

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

    // ============================
    // CONSTRUCTOR — GAS OPTIMIZED
    // ============================
    constructor()
        ERC20("Paradaise Supply Chain", "PSC")
    {
        // Immutable wallets
        developerWallet = 0xD47A6b5C4829Ad840890B2df076a4210D96dd1bf;
        founder1 = 0x5496Be16c5098E87F757236E9ba87b487db34b59;
        founder2 = 0x38ABF89F423D18c35770Ca6e0245DADCe08e8Bae;
        consultantWallet = 0x884593e1570DE2C5Aa89d3e93D2d22e8EE2a7416; // ✅ NEW
        publicOfferingWallet = 0x2f7a74Ab84B87D3aa3B05EDb4454bf149d606404; // ✅ UPDATED
        publicDistributionWallet = 0xe80E5D6d3a8C534C29972C9b520ba252e16193Af; // ✅ UPDATED

        require(developerWallet != address(0), "Invalid developer wallet");
        require(founder1 != address(0), "Invalid founder1");
        require(founder2 != address(0), "Invalid founder2");
        require(consultantWallet != address(0), "Invalid consultant wallet");
        require(publicOfferingWallet != address(0), "Invalid public offering wallet");
        require(publicDistributionWallet != address(0), "Invalid public distribution wallet");

        uint256 teamCount = TEAM_ADDRESSES.length;
        require(teamCount == TEAM_AMOUNTS.length, "Length mismatch");
        require(teamCount > 0, "Team must have at least one member");

        // Store team members
        teamMembers = TEAM_ADDRESSES;
        for (uint256 i = 0; i < teamCount; ) {
            address member = TEAM_ADDRESSES[i];
            require(member != address(0), "Invalid team address");
            require(TEAM_AMOUNTS[i] > 0, "Team amount must be > 0");
            teamAllocations[member] = TEAM_AMOUNTS[i];
            unchecked { ++i; }
        }

        // Auto-correct total team allocation if needed
        uint256 targetAllocation = (TOTAL_SUPPLY * TEAM_PERCENT) / 100;
        uint256 totalTeamAllocation = 0;
        for (uint256 i = 0; i < teamCount; ) {
            totalTeamAllocation += TEAM_AMOUNTS[i];
            unchecked { ++i; }
        }

        if (totalTeamAllocation != targetAllocation) {
            if (totalTeamAllocation < targetAllocation) {
                teamAllocations[TEAM_ADDRESSES[0]] += targetAllocation - totalTeamAllocation;
            } else {
                teamAllocations[TEAM_ADDRESSES[0]] -= totalTeamAllocation - targetAllocation;
            }
        }

        airdropDistributed = false;

        // ════════════════════════════════════════════════════════════════
        // GAS OPTIMIZATION: Use _mint() directly for all initial distributions
        // ════════════════════════════════════════════════════════════════

        // 1% — Mint directly to team members
        for (uint256 i = 0; i < teamCount; ) {
            uint256 amount = teamAllocations[TEAM_ADDRESSES[i]];
            if (amount > 0) {
                _mint(TEAM_ADDRESSES[i], amount);
            }
            unchecked { ++i; }
        }

        // 4% — Mint to founders (2% each)
        uint256 founderTotalAmount = (TOTAL_SUPPLY * FOUNDERS_PERCENT) / 100;
        uint256 perFounder = founderTotalAmount / 2;
        _mint(founder1, perFounder);
        _mint(founder2, perFounder);

        // 1% — Mint to consultants
        uint256 consultantAmount = (TOTAL_SUPPLY * CONSULTANTS_PERCENT) / 100;
        _mint(consultantWallet, consultantAmount);

        // 2% — Mint to public offering wallet
        uint256 publicOfferingAmount = (TOTAL_SUPPLY * INITIAL_OFFERING_PERCENT) / 100;
        _mint(publicOfferingWallet, publicOfferingAmount);

        // Calculate remaining supply
        uint256 teamTotalAmount = (TOTAL_SUPPLY * TEAM_PERCENT) / 100;
        uint256 totalDistributed = teamTotalAmount + founderTotalAmount + consultantAmount + publicOfferingAmount;
        remainingSupply = TOTAL_SUPPLY - totalDistributed;

        // Mint remaining tokens to the contract itself
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
    // AIRDROP — Manual distribution (anyone can call, only once)
    // ============================
    function distributeAirdrop(address[] calldata recipients) public nonReentrant {
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

        // 1% to developer wallet
        uint256 developerAmount = (remainingSupply * ANNUAL_DEVELOPER_PERCENT) / 100;
        _transfer(address(this), developerWallet, developerAmount);

        // 4% to founders (2% each)
        uint256 founderTotalAmount = (remainingSupply * ANNUAL_FOUNDERS_PERCENT) / 100;
        uint256 perFounder = founderTotalAmount / 2;
        _transfer(address(this), founder1, perFounder);
        _transfer(address(this), founder2, perFounder);

        // 1% to consultants
        uint256 consultantAmount = (remainingSupply * ANNUAL_CONSULTANTS_PERCENT) / 100;
        _transfer(address(this), consultantWallet, consultantAmount);

        // 4% to public distribution wallet
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

    function getTeamMembers() external view returns (address[] memory) {
        return teamMembers;
    }

    function getTeamMembersCount() external view returns (uint256) {
        return teamMembers.length;
    }

    function getTeamAllocation(address member) external view returns (uint256) {
        return teamAllocations[member];
    }

    function getAirdropAmountPerRecipient(uint256 recipientsCount) external pure returns (uint256) {
        require(recipientsCount > 0 && recipientsCount <= MAX_AIRDROP_RECIPIENTS, "Invalid count");
        return AIRDROP_AMOUNT / recipientsCount;
    }
}
