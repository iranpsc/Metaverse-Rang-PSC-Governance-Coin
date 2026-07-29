// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/finance/VestingWallet.sol";

/**
 * @title InvestorStepVesting
 * @notice Step-based vesting contract for investors (e.g., 4 steps of 6 months each)
 */
contract InvestorStepVesting is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============================
    // Immutable Parameters
    // ============================
    address public immutable beneficiary;
    uint64 public immutable start;
    uint64 public immutable stepDuration;
    uint8 public immutable totalSteps;

    // ============================
    // Mutable State
    // ============================
    uint256 public released;
    bool public isRevoked;

    // ============================
    // Events
    // ============================
    event Released(uint256 amount);
    event Revoked(address indexed revokedBy);

    // ============================
    // Constructor
    // ============================
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

    // ============================
    // Core Functions
    // ============================

    /**
     * @notice Returns the amount of tokens that can be released right now
     */
    function releasable(address token) public view returns (uint256) {
        uint256 vested = vestedAmount(token, uint64(block.timestamp));
        return vested - released;
    }

    /**
     * @notice Releases vested tokens to the beneficiary
     */
    function release(address token) external nonReentrant {
        require(!isRevoked, "Vesting revoked");
        uint256 amount = releasable(token);
        require(amount > 0, "Nothing to release");

        released += amount;
        IERC20(token).safeTransfer(beneficiary, amount);

        emit Released(amount);
    }

    /**
     * @notice Revokes the vesting and transfers remaining tokens to a specified address
     * @dev Only callable by the beneficiary
     */
    function revoke(address token, address to) external {
        require(msg.sender == beneficiary, "Only beneficiary can revoke");
        require(!isRevoked, "Already revoked");

        isRevoked = true;
        uint256 remaining = IERC20(token).balanceOf(address(this)) - released;
        IERC20(token).safeTransfer(to, remaining);

        emit Revoked(msg.sender);
    }

    // ============================
    // View Functions
    // ============================

    /**
     * @notice Calculates the total vested amount up to a given timestamp
     */
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

    /**
     * @notice Returns the total amount of tokens allocated to this vesting contract
     */
    function getTotalAllocation(address token) public view returns (uint256) {
        return IERC20(token).balanceOf(address(this)) + released;
    }

    /**
     * @notice Returns the current vesting step (0 = not started, totalSteps = fully vested)
     */
    function getCurrentStep() public view returns (uint256) {
        if (block.timestamp < start) {
            return 0;
        }
        uint256 elapsedSteps = (uint64(block.timestamp) - start) / stepDuration + 1;
        return elapsedSteps > totalSteps ? totalSteps : elapsedSteps;
    }

    /**
     * @notice Returns the vesting percentage completed (0% to 100%)
     */
    function getVestedPercentage() public view returns (uint256) {
        uint256 currentStep = getCurrentStep();
        return (currentStep * 100) / totalSteps;
    }

    // ============================
    // Receive Ether (for compatibility)
    // ============================
    receive() external payable {}
}

/**
 * @title MyToken (Paradaise Supply Chain Token - PSC)
 * @notice ERC20 token with public distribution, team vesting, and investor step vesting
 */
contract MyToken is ERC20, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============================
    // Constants
    // ============================
    uint256 public constant TOTAL_SUPPLY = 20_000_000 * 10**18; // 20 million with 18 decimals
    uint256 public constant PUBLIC_PERCENT = 10; // 10%
    uint256 public constant TEAM_PERCENT = 3;    // 3%
    uint256 public constant INVESTOR_PERCENT = 87; // 87%

    uint64 public constant TEAM_CLIFF = 365 days;
    uint64 public constant TEAM_VESTING_DURATION = 730 days;

    uint64 public constant INVESTOR_STEP = 180 days; // 6 months
    uint8 public constant INVESTOR_STEPS = 4;        // 4 steps = 24 months

    // ============================
    // Storage Variables
    // ============================
    VestingWallet[] public teamVestings;
    InvestorStepVesting public investorVesting;

    mapping(address => string) public teamMemberNames;
    address[] public teamMemberAddresses;

    // ============================
    // Events
    // ============================
    event TeamVestingCreated(address indexed beneficiary, string name, address vestingWallet, uint256 amount);
    event InvestorVestingCreated(address indexed investor, address vestingWallet, uint256 amount);
    event PublicDistributed(address indexed publicWallet, uint256 amount);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);
    event ContractPaused(address indexed pausedBy);
    event ContractUnpaused(address indexed unpausedBy);

    // ============================
    // Constructor
    // ============================
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
        // Input validation
        require(publicWallet != address(0), "Invalid public wallet");
        require(investorWallet != address(0), "Invalid investor wallet");
        require(teamWallets.length == 4, "Team wallets must be exactly 4");
        require(teamWallets.length == teamNames.length, "Names length mismatch");
        require(startTimestamp >= block.timestamp, "Start must be in the future");

        for (uint256 i = 0; i < teamWallets.length; i++) {
            require(teamWallets[i] != address(0), "Invalid team wallet");
            require(bytes(teamNames[i]).length > 0, "Invalid team name");
        }

        // Store team member information
        for (uint256 i = 0; i < teamWallets.length; i++) {
            teamMemberNames[teamWallets[i]] = teamNames[i];
            teamMemberAddresses.push(teamWallets[i]);
        }

        // Mint total supply to the contract itself
        _mint(address(this), TOTAL_SUPPLY);

        // ===== Public Distribution (10%) =====
        uint256 publicAmount = (TOTAL_SUPPLY * PUBLIC_PERCENT) / 100;
        _transfer(address(this), publicWallet, publicAmount);
        emit PublicDistributed(publicWallet, publicAmount);

        // ===== Team Vesting (3%) =====
        uint256 teamTotalAmount = (TOTAL_SUPPLY * TEAM_PERCENT) / 100;
        uint256 perTeamMember = teamTotalAmount / teamWallets.length;

        for (uint256 i = 0; i < teamWallets.length; i++) {
            // Create a separate vesting wallet for each team member
            VestingWallet vesting = new VestingWallet(
                teamWallets[i],
                startTimestamp + TEAM_CLIFF,
                TEAM_VESTING_DURATION
            );

            _transfer(address(this), address(vesting), perTeamMember);
            teamVestings.push(vesting);

            emit TeamVestingCreated(teamWallets[i], teamNames[i], address(vesting), perTeamMember);
        }

        // ===== Investor Step Vesting (87%) =====
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

    // ============================
    // Pause / Unpause Functions
    // ============================
    function pause() external onlyOwner {
        _pause();
        emit ContractPaused(msg.sender);
    }

    function unpause() external onlyOwner {
        _unpause();
        emit ContractUnpaused(msg.sender);
    }

    // ============================
    // Overridden Transfer Functions (with pause protection)
    // ============================
    function transfer(address to, uint256 amount) public virtual override whenNotPaused returns (bool) {
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override whenNotPaused returns (bool) {
        return super.transferFrom(from, to, amount);
    }

    // ============================
    // Rescue Stray Tokens
    // ============================
    /**
     * @notice Allows the owner to rescue tokens accidentally sent to this contract
     * @dev Cannot rescue locked tokens (team / investor vesting)
     */
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

    // ============================
    // Internal Helper Functions
    // ============================
    /**
     * @dev Calculates the total amount of tokens locked in vesting contracts
     */
    function _getLockedTokenBalance() internal view returns (uint256) {
        uint256 locked = 0;

        // Sum tokens locked in team vesting contracts
        for (uint256 i = 0; i < teamVestings.length; i++) {
            locked += IERC20(address(this)).balanceOf(address(teamVestings[i]));
        }

        // Add tokens locked in investor vesting contract
        locked += IERC20(address(this)).balanceOf(address(investorVesting));

        return locked;
    }

    // ============================
    // Public View Functions
    // ============================
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
