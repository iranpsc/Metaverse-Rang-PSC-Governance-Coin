// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/contracts/ParadiseSupplyChain.sol";
import "../src/contracts/PSCTreasury.sol";
import "../src/contracts/MerkleAirdrop.sol";
import "../src/contracts/SupplyChainModule.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MCK") {
        _mint(msg.sender, 1_000_000 * 1e18);
    }
}

contract PSCTest is Test {
    PSCToken public pscToken;
    PSCTreasury public pscTreasury;
    MerkleAirdrop public merkleAirdrop;
    SupplyChainModule public supplyChainModule;
    MockERC20 public mockToken;

    address public deployer = makeAddr("deployer");
    address public timelock = makeAddr("timelock");
    address public operator = makeAddr("operator");

    address public developerWallet = makeAddr("developerWallet");
    address public founder1 = makeAddr("founder1");
    address public founder2 = makeAddr("founder2");
    address public consultantWallet = makeAddr("consultantWallet");
    address public publicOfferingWallet = makeAddr("publicOfferingWallet");
    address public publicDistributionWallet = makeAddr("publicDistributionWallet");

    uint256 public user1Pk = 0xA11CE;
    address public user1;
    uint256 public user2Pk = 0xB0B;
    address public user2;

    uint256 public user1AirdropAmt = 100_000 * 1e18;
    uint256 public user2AirdropAmt = 300_000 * 1e18;
    bytes32 public leaf1;
    bytes32 public leaf2;
    bytes32 public merkleRoot;

    address[] public teamWallets;
    uint256[] public teamAmounts;

    uint256 public constant LAUNCH_TIMESTAMP = 1825545600; // Nov 6, 2027

    function setUp() public {
        vm.warp(LAUNCH_TIMESTAMP - 10 days);

        user1 = vm.addr(user1Pk);
        user2 = vm.addr(user2Pk);

        leaf1 = keccak256(bytes.concat(keccak256(abi.encode(user1, user1AirdropAmt))));
        leaf2 = keccak256(bytes.concat(keccak256(abi.encode(user2, user2AirdropAmt))));
        merkleRoot = _hashPair(leaf1, leaf2);

        uint256 baseAmt = 34_000 * 1e18;
        uint256 sum = 0;
        for (uint256 i = 0; i < 57; ++i) {
            teamWallets.push(address(uint160(0x1000 + i)));
            teamAmounts.push(baseAmt);
            sum += baseAmt;
        }
        teamWallets.push(address(uint160(0x1000 + 57)));
        teamAmounts.push((2_000_000 * 1e18) - sum);

        vm.startPrank(deployer);

        pscToken = new PSCToken();

        pscTreasury = new PSCTreasury(
            address(pscToken),
            developerWallet,
            founder1,
            founder2,
            consultantWallet,
            publicOfferingWallet,
            publicDistributionWallet
        );

        merkleAirdrop = new MerkleAirdrop(
            address(pscToken),
            address(pscTreasury)
        );

        supplyChainModule = new SupplyChainModule(
            address(pscToken),
            address(pscTreasury),
            timelock,
            operator
        );

        pscToken.setTreasury(address(pscTreasury));

        pscTreasury.initialize(
            timelock,
            address(merkleAirdrop),
            teamWallets,
            teamAmounts
        );

        merkleAirdrop.initializeAirdrop(
            merkleRoot,
            pscTreasury.AIRDROP_AMOUNT(),
            timelock
        );

        mockToken = new MockERC20();
        vm.stopPrank();
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    // ============================================================
    // 1. PSCToken Tests
    // ============================================================

    function test_TokenMetadataAndSupply() public view {
        assertEq(pscToken.name(), "Paradise Supply Chain");
        assertEq(pscToken.symbol(), "PSC");
        assertEq(pscToken.totalSupply(), 200_000_000 * 1e18);
        assertTrue(pscToken.treasurySet());
        assertEq(pscToken.treasury(), address(pscTreasury));
    }

    function test_SetTreasuryRevertAlreadySet() public {
        vm.prank(deployer);
        vm.expectRevert(PSCToken.AlreadySet.selector);
        pscToken.setTreasury(address(pscTreasury));
    }

    function test_SetTreasuryRevertNonContract() public {
        vm.startPrank(deployer);
        PSCToken freshToken = new PSCToken();
        vm.expectRevert(PSCToken.InvalidTreasuryAddress.selector);
        freshToken.setTreasury(makeAddr("eoaAddress"));
        vm.stopPrank();
    }

    // ============================================================
    // 2. PSCTreasury Year-1 & Role Tests
    // ============================================================

    function test_Year1DistributionAndRoles() public view {
        assertEq(pscToken.balanceOf(founder1), 4_000_000 * 1e18);
        assertEq(pscToken.balanceOf(founder2), 4_000_000 * 1e18);
        assertEq(pscToken.balanceOf(consultantWallet), 2_000_000 * 1e18);
        assertEq(pscToken.balanceOf(address(merkleAirdrop)), 4_000_000 * 1e18);
        assertEq(pscToken.balanceOf(publicOfferingWallet), 4_000_000 * 1e18);
        assertEq(pscToken.balanceOf(address(pscTreasury)), 180_000_000 * 1e18);

        assertFalse(pscTreasury.hasRole(pscTreasury.DEFAULT_ADMIN_ROLE(), deployer));
        assertTrue(pscTreasury.hasRole(pscTreasury.DEFAULT_ADMIN_ROLE(), timelock));
        assertTrue(pscTreasury.hasRole(pscTreasury.TIMELOCK_ROLE(), timelock));
        assertTrue(pscTreasury.hasRole(pscTreasury.EXECUTOR_ROLE(), timelock));
    }

    // ============================================================
    // 3. PSCTreasury Annual Release Schedule (Nov 6, 2028)
    // ============================================================

    function test_ReleaseAnnualRevertsOnLaunchDate2027() public {
        vm.warp(LAUNCH_TIMESTAMP);

        vm.prank(timelock);
        vm.expectRevert(PSCTreasury.TooEarlyForRelease.selector);
        pscTreasury.releaseAnnual();
    }

    function test_ReleaseAnnualSucceedsOneYearAfterLaunch2028() public {
        uint256 firstAnnualReleaseTime = LAUNCH_TIMESTAMP + 365 days;
        vm.warp(firstAnnualReleaseTime);

        uint256 initialTreasuryBal = pscToken.balanceOf(address(pscTreasury));
        uint256 expectedRelease = (initialTreasuryBal * 1000) / 10000;

        vm.prank(timelock);
        pscTreasury.releaseAnnual();

        assertEq(pscToken.balanceOf(developerWallet), (expectedRelease * 1000) / 10000);
        assertEq(pscToken.balanceOf(founder1), 4_000_000 * 1e18 + (expectedRelease * 2000) / 10000);
        assertEq(pscToken.balanceOf(founder2), 4_000_000 * 1e18 + (expectedRelease * 2000) / 10000);
        assertEq(pscToken.balanceOf(consultantWallet), 2_000_000 * 1e18 + (expectedRelease * 1000) / 10000);
        assertEq(pscToken.balanceOf(publicDistributionWallet), (expectedRelease * 4000) / 10000);
        assertEq(pscToken.balanceOf(address(pscTreasury)), 162_000_000 * 1e18);
        assertEq(pscTreasury.lastReleaseTime(), firstAnnualReleaseTime + 365 days);
    }

    // ============================================================
    // 4. PSCTreasury Timelock Wallet Updates
    // ============================================================

    function test_UpdateWalletsByTimelock() public {
        address newDev = makeAddr("newDevContract");
        address newF1 = makeAddr("newF1");
        address newF2 = makeAddr("newF2");
        address newCons = makeAddr("newCons");
        address newPubDist = makeAddr("newPubDistContract");

        vm.prank(deployer);
        vm.expectRevert();
        pscTreasury.updateWallets(newDev, newF1, newF2, newCons, newPubDist);

        vm.prank(timelock);
        pscTreasury.updateWallets(newDev, newF1, newF2, newCons, newPubDist);

        assertEq(pscTreasury.developerWallet(), newDev);
        assertEq(pscTreasury.founder1(), newF1);
        assertEq(pscTreasury.founder2(), newF2);
        assertEq(pscTreasury.consultantWallet(), newCons);
        assertEq(pscTreasury.publicDistributionWallet(), newPubDist);
    }

    function test_UpdateWalletsRevertZeroAddress() public {
        vm.prank(timelock);
        vm.expectRevert(PSCTreasury.InvalidParameters.selector);
        pscTreasury.updateWallets(address(0), founder1, founder2, consultantWallet, publicDistributionWallet);
    }

    // ============================================================
    // 5. MerkleAirdrop Claim, Vesting & Clawback
    // ============================================================

    function test_MerkleAirdropClaimAndVestingFlow() public {
        bytes32[] memory proof1 = new bytes32[](1);
        proof1[0] = leaf2;

        vm.prank(user1);
        merkleAirdrop.claimAirdrop(user1AirdropAmt, proof1);

        assertTrue(merkleAirdrop.hasClaimed(user1));
        assertEq(merkleAirdrop.getClaimableAmount(user1), 0);

        vm.warp(merkleAirdrop.airdropStartTime() + 30 days);
        assertEq(merkleAirdrop.getClaimableAmount(user1), 0);

        vm.warp(merkleAirdrop.airdropStartTime() + 60 days + 182.5 days);
        uint256 halfClaimable = merkleAirdrop.getClaimableAmount(user1);
        assertApproxEqAbs(halfClaimable, user1AirdropAmt / 2, 1e10);

        vm.prank(user1);
        merkleAirdrop.releaseVested();
        assertEq(pscToken.balanceOf(user1), halfClaimable);

        vm.warp(merkleAirdrop.airdropStartTime() + 60 days + 365 days);
        vm.prank(user1);
        merkleAirdrop.releaseVested();
        assertEq(pscToken.balanceOf(user1), user1AirdropAmt);
    }

    function test_ExecuteClawbackPreservesUnclaimedVestedObligations() public {
        bytes32[] memory proof1 = new bytes32[](1);
        proof1[0] = leaf2;

        vm.prank(user1);
        merkleAirdrop.claimAirdrop(user1AirdropAmt, proof1);

        uint256 clawbackTime = merkleAirdrop.airdropStartTime() + 60 days + 365 days + 180 days;
        vm.warp(clawbackTime);

        uint256 treasuryBefore = pscToken.balanceOf(address(pscTreasury));
        uint256 expectedClawback = 4_000_000 * 1e18 - user1AirdropAmt;

        vm.prank(timelock);
        merkleAirdrop.executeClawback();

        assertEq(pscToken.balanceOf(address(pscTreasury)), treasuryBefore + expectedClawback);
        assertEq(pscToken.balanceOf(address(merkleAirdrop)), user1AirdropAmt);

        vm.prank(user1);
        merkleAirdrop.releaseVested();
        assertEq(pscToken.balanceOf(user1), user1AirdropAmt);
    }

    // ============================================================
    // 6. SupplyChainModule Fee & Permit Protection
    // ============================================================

    function test_SupplyChainProcessFeeWithPermitAndFrontrunProtection() public {
        uint256 feeAmount = 1_000 * 1e18;
        vm.prank(publicOfferingWallet);
        pscToken.transfer(user1, feeAmount);

        uint256 deadline = block.timestamp + 1 hours;
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                user1,
                address(supplyChainModule),
                feeAmount,
                pscToken.nonces(user1),
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", pscToken.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1Pk, digest);

        // Simulate attacker front-running the permit call directly on PSCToken
        vm.prank(makeAddr("frontrunner"));
        pscToken.permit(user1, address(supplyChainModule), feeAmount, deadline, v, r, s);

        uint256 treasuryBefore = pscToken.balanceOf(address(pscTreasury));
        uint256 supplyBefore = pscToken.totalSupply();

        // Operator call still succeeds thanks to try/catch allowance fallback
        vm.prank(operator);
        supplyChainModule.processFeeWithPermit(user1, feeAmount, deadline, v, r, s);

        assertEq(pscToken.totalSupply(), supplyBefore - 100 * 1e18);
        assertEq(pscToken.balanceOf(address(pscTreasury)), treasuryBefore + 900 * 1e18);
    }

    // ============================================================
    // 7. Token Rescue Tests
    // ============================================================

    function test_RescueTokensProtectsPSCAndRecoversMockToken() public {
        vm.prank(deployer);
        mockToken.transfer(address(pscTreasury), 500 * 1e18);

        vm.startPrank(timelock);
        vm.expectRevert(PSCTreasury.CannotRescuePSCTokens.selector);
        pscTreasury.rescueTokens(address(pscToken), timelock);

        pscTreasury.rescueTokens(address(mockToken), timelock);
        assertEq(mockToken.balanceOf(timelock), 500 * 1e18);
        vm.stopPrank();
    }
}