// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/finance/VestingWallet.sol";

/// @title Paradaise Supply Chain Token (PSC)
/// @notice ERC20 token with team linear vesting and investor step vesting
contract MyToken is ERC20, Ownable {
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

    // =========================
    // ========= EVENTS ========
    // =========================

    event TeamVestingCreated(address indexed beneficiary, address vestingWallet, uint256 amount);
    event InvestorVestingCreated(address indexed investor, address vestingWallet, uint256 amount);
    event PublicDistributed(address indexed publicWallet, uint256 amount);

    // =========================
    // ======== CONSTRUCTOR ====
    // =========================

    constructor(address publicWallet, address[] memory teamWallets, address investorWallet, uint64 startTimestamp)
        ERC20("Paradaise Supply Chain", "PSC")
        Ownable(msg.sender)
    {
        require(publicWallet != address(0), "Invalid public wallet");
        require(investorWallet != address(0), "Invalid investor wallet");
        require(teamWallets.length == 15, "Team wallets must be 15");
        require(startTimestamp >= block.timestamp, "Start must be future");

        for (uint256 i = 0; i < teamWallets.length; i++) {
            require(teamWallets[i] != address(0), "Invalid team wallet");
        }

        _mint(address(this), TOTAL_SUPPLY);

        // ===== Public =====
        uint256 publicAmount = (TOTAL_SUPPLY * PUBLIC_PERCENT) / 100;
        _transfer(address(this), publicWallet, publicAmount);
        emit PublicDistributed(publicWallet, publicAmount);

        // ===== Team Vesting =====
        uint256 teamTotalAmount = (TOTAL_SUPPLY * TEAM_PERCENT) / 100;
        uint256 perTeamMember = teamTotalAmount / teamWallets.length;

        for (uint256 i = 0; i < teamWallets.length; i++) {
            VestingWallet vesting =
                new VestingWallet(teamWallets[i], startTimestamp + TEAM_CLIFF, TEAM_VESTING_DURATION);

            _transfer(address(this), address(vesting), perTeamMember);
            teamVestings.push(vesting);

            emit TeamVestingCreated(teamWallets[i], address(vesting), perTeamMember);
        }

        // ===== Investor Step Vesting =====
        uint256 investorAmount = TOTAL_SUPPLY - publicAmount - teamTotalAmount;

        investorVesting = new InvestorStepVesting(investorWallet, startTimestamp, INVESTOR_STEP, INVESTOR_STEPS);

        _transfer(address(this), address(investorVesting), investorAmount);

        emit InvestorVestingCreated(investorWallet, address(investorVesting), investorAmount);
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
}

/// @title Investor Step Vesting (6-month unlocks)
contract InvestorStepVesting is Ownable {
    address public immutable beneficiary;
    uint64 public immutable start;
    uint64 public immutable stepDuration;
    uint8 public immutable totalSteps;

    uint256 public released;

    constructor(address _beneficiary, uint64 _start, uint64 _stepDuration, uint8 _totalSteps) Ownable(msg.sender) {
        require(_beneficiary != address(0), "Invalid beneficiary");
        require(_totalSteps > 0, "Invalid steps");

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

    function release(address token) external {
        uint256 amount = releasable(token);
        require(amount > 0, "Nothing to release");

        released += amount;
        IERC20(token).transfer(beneficiary, amount);
    }

    function vestedAmount(address token, uint64 timestamp) public view returns (uint256) {
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
}
