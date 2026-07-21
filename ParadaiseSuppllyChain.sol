// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/finance/VestingWallet.sol";

/// @title Paradaise Supply Chain Token (PSC)
/// @notice ERC20 token with team linear vesting and investor step vesting
/// @dev Team members: Hosein Ghadiri (Project Owner), Amir Madani Far (Project Owner), Ajorlo (Backend), Parsa Abolhasani Rad (Blockchain)
contract MyToken is ERC20, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========================
    // ======== CONSTANTS ======
    // =========================

    uint256 public constant TOTAL_SUPPLY = 20_000_000 ether;
    uint256 public constant PUBLIC_PERCENT = 10;
    uint256 public constant TEAM_PERCENT = 3;

    // Team vesting
    uint64 public constant TEAM_CLIFF = 365 days;
    uint64 public constant TEAM_VESTING_DURATION = 730 days;

    // Investor step vesting
    uint64 public constant INVESTOR_STEP = 180 days; // 6 months
    uint8 public constant INVESTOR_STEPS = 4; // 24 months total

    // =========================
    // ======== STORAGE ========
    // =========================

    VestingWallet[] public teamVestings;
    InvestorStepVesting public investorVesting;

    // Team member names mapping (for transparency)
    mapping(address => string) public teamMemberNames;
    address[] public teamMemberAddresses;

    // =========================
    // ========= EVENTS ========
    // =========================

    event TeamVestingCreated(address indexed beneficiary, string name, address vestingWallet, uint256 amount);
    event InvestorVestingCreated(address indexed investor, address vestingWallet, uint256 amount);
    event PublicDistributed(address indexed publicWallet, uint256 amount);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);
    event ContractPaused(address indexed pausedBy);
    event ContractUnpaused(address indexed unpausedBy);

    // =========================
    // ======== CONSTRUCTOR ====
    // =========================

    constructor(
        address publicWallet,
        address[] memory teamWallets,
        string[] memory teamNames,
        address investorWallet,
        uint64 startTimestamp
    )
        ERC20("Paradaise Supply Chain", "PSC")
        Ownable(msg.sender)
    {
        require(publicWallet != address(0), "Invalid public wallet");
        require(investorWallet != address(0), "Invalid investor wallet");
        require(teamWallets.length == 4, "Team wallets must be 4");
        require(teamWallets.length == teamNames.length, "Names length mismatch");
        require(startTimestamp >= block.timestamp, "Start must be future");

        for (uint256 i = 0; i < teamWallets.length; i++) {
            require(teamWallets[i] != address(0), "Invalid team wallet");
            require(bytes(teamNames[i]).length > 0, "Invalid team name");
        }

        // Store team member names
        for (uint256 i = 0; i < teamWallets.length; i++) {
            teamMemberNames[teamWallets[i]] = teamNames[i];
            teamMemberAddresses.push(teamWallets[i]);
        }

        // Mint total supply to contract
        _mint(address(this), TOTAL_SUPPLY);

        // ===== Public =====
        uint256 publicAmount = (TOTAL_SUPPLY * PUBLIC_PERCENT) / 100;
        _transfer(address(this), publicWallet, publicAmount);
        emit PublicDistributed(publicWallet, publicAmount);

        // ===== Team Vesting =====
        uint256 teamTotalAmount = (TOTAL_SUPPLY * TEAM_PERCENT) / 100;
        uint256 perTeamMember = teamTotalAmount / teamWallets.length;

        for (uint256 i = 0; i < teamWallets.length; i++) {
            VestingWallet vesting = new VestingWallet(
                teamWallets[i],
                startTimestamp + TEAM_CLIFF,
                TEAM_VESTING_DURATION
            );

            _transfer(address(this), address(vesting), perTeamMember);
            teamVestings.push(vesting);

            emit TeamVestingCreated(teamWallets[i], teamNames[i], address(vesting), perTeamMember);
        }

        // ===== Investor Step Vesting =====
        uint256 investorAmount = TOTAL_SUPPLY - publicAmount - teamTotalAmount;

        investorVesting = new InvestorStepVesting(
            investorWallet,
            startTimestamp,
            INVESTOR_STEP,
            INVESTOR_STEPS
        );

        _transfer(address(this), address(investorVesting), investorAmount);

        emit InvestorVestingCreated(investorWallet, address(investorVesting), investorAmount);
    }

    // =========================
    // ===== PAUSABLE HOOKS ====
    // =========================

    function pause() external onlyOwner {
        _pause();
        emit ContractPaused(msg.sender);
    }

    function unpause() external onlyOwner {
        _unpause();
        emit ContractUnpaused(msg.sender);
    }

    function transfer(address to, uint256 amount) public virtual override whenNotPaused returns (bool) {
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override whenNotPaused returns (bool) {
        return super.transferFrom(from, to, amount);
    }

    // =========================
    // ===== RESCUE TOKENS =====
    // =========================

    function rescueTokens(address token, address to) external onlyOwner nonReentrant {
        require(to != address(0), "Invalid recipient");
        uint256 balance = IERC20(token).balanceOf(address(this));
        
        if (token == address(this)) {
            uint256 lockedTokens = _getLockedTokenBalance();
            require(balance > lockedTokens, "Cannot rescue locked tokens");
            uint256 rescurable = balance - lockedTokens;
            IERC20(token).safeTransfer(to, rescurable);
            emit TokensRescued(token, to, rescurable);
        } else {
            IERC20(token).safeTransfer(to, balance);
            emit TokensRescued(token, to, balance);
        }
    }

    function _getLockedTokenBalance() internal view returns (uint256) {
        uint256 locked = 0;
        for (uint256 i = 0; i < teamVestings.length; i++) {
            locked += IERC20(address(this)).balanceOf(address(teamVestings[i]));
        }
        locked += IERC20(address(this)).balanceOf(address(investorVesting));
        return locked;
    }

    // =========================
    // ========= VIEWS =========
    // =========================

    function teamVestingsCount() external view returns (uint256) {
        return teamVestings.length;
    }

    function getTeamVestings() external view returns (VestingWallet[] memory) {
        return teamVestings;
    }

    function getTeamMembers() external view returns (address[] memory, string[] memory) {
        string[] memory names = new string[](teamMemberAddresses.length);
        for (uint256 i = 0; i < teamMemberAddresses.length; i++) {
            names[i] = teamMemberNames[teamMemberAddresses[i]];
        }
        return (teamMemberAddresses, names);
    }

    function getTotalLockedTokens() external view returns (uint256) {
        return _getLockedTokenBalance();
    }

    function getCirculatingSupply() external view returns (uint256) {
        return totalSupply() - _getLockedTokenBalance();
    }
}

/// @title Investor Step Vesting (6-month unlocks)
/// @dev Improved with safety checks and additional view functions
contract InvestorStepVesting is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable beneficiary;
    uint64 public immutable start;
    uint64 public immutable stepDuration;
    uint8 public immutable totalSteps;

    uint256 public released;
    bool public isRevoked;

    event Released(uint256 amount);
    event Revoked(address indexed revokedBy);

    constructor(
        address _beneficiary,
        uint64 _start,
        uint64 _stepDuration,
        uint8 _totalSteps
    ) {
        require(_beneficiary != address(0), "Invalid beneficiary");
        require(_totalSteps > 0, "Invalid steps");
        require(_stepDuration > 0, "Invalid step duration");

        beneficiary = _beneficiary;
        start = _start;
        stepDuration = _stepDuration;
        totalSteps = _totalSteps;
    }

    receive() external payable {}

    function releasable(address token) public view returns (uint256) {
        uint256 vested = vestedAmount(token, uint64(block.timestamp));
        return vested - released;
    }

    function release(address token) external nonReentrant {
        require(!isRevoked, "Vesting revoked");
        uint256 amount = releasable(token);
        require(amount > 0, "Nothing to release");

        released += amount;
        IERC20(token).safeTransfer(beneficiary, amount);

        emit Released(amount);
    }

    function revoke(address token, address to) external {
        require(msg.sender == beneficiary, "Only beneficiary can revoke");
        require(!isRevoked, "Already revoked");

        isRevoked = true;
        uint256 remaining = IERC20(token).balanceOf(address(this)) - released;
        IERC20(token).safeTransfer(to, remaining);

        emit Revoked(msg.sender);
    }

    function vestedAmount(address token, uint64 timestamp) public view returns (uint256) {
        if (isRevoked) {
            return released;
        }

        uint256 totalAllocation = IERC20(token).balanceOf(address(this)) + released;

        if (timestamp < start) {
            return 0;
        }

        uint256 elapsedSteps = (timestamp - start) / stepDuration + 1;

        if (elapsedSteps >= totalSteps) {
            return totalAllocation;
        }

        return (totalAllocation * elapsedSteps) / totalSteps;
    }

    function getTotalAllocation(address token) public view returns (uint256) {
        return IERC20(token).balanceOf(address(this)) + released;
    }

    function getCurrentStep() public view returns (uint256) {
        if (block.timestamp < start) {
            return 0;
        }
        uint256 elapsedSteps = (uint64(block.timestamp) - start) / stepDuration + 1;
        return elapsedSteps > totalSteps ? totalSteps : elapsedSteps;
    }

    function getVestedPercentage() public view returns (uint256) {
        uint256 currentStep = getCurrentStep();
        return (currentStep * 100) / totalSteps;
    }
}
