// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FactoryMatch} from "../src/FactoryMatch.sol";
import {VaultMatch} from "../src/VaultMatch.sol";
import {IVaultMatch} from "../src/interfaces/IVaultMatch.sol";

/// @title VaultMatchTest
/// @notice Fork test on Base mainnet (real USDC + Morpho Vault)
/// @dev Run with: forge test --fork-url <BASE_RPC> -vvv
contract VaultMatchTest is Test {
    // Base Mainnet USDC
    IERC20 constant USDC = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);

    FactoryMatch public factory;
    VaultMatch public vault;

    address owner = makeAddr("owner");
    address oracle = makeAddr("oracle");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");

    uint256 constant DEPOSIT_AMOUNT = 100e6; // 100 USDC

    function setUp() public {
        vm.createSelectFork(vm.envString("TENDERLY_VIRTUAL_TESTNET_RPC_URL"));
        vm.startPrank(owner);

        factory = new FactoryMatch(owner, oracle);
        (, address vaultAddr) = factory.createMatch("Sentinels", "LOUD");
        vault = VaultMatch(vaultAddr);

        vm.stopPrank();

        // Fund users with USDC using Foundry's deal cheatcode
        deal(address(USDC), alice, 1000e6);
        deal(address(USDC), bob, 1000e6);
        deal(address(USDC), charlie, 1000e6);
    }

    // ─── Deposit Tests ───────────────────────────────────────────────────

    function test_DepositTeamA() public {
        vm.startPrank(alice);
        USDC.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(IVaultMatch.Team.TeamA, DEPOSIT_AMOUNT);
        vm.stopPrank();

        assertEq(vault.totalTeamA(), DEPOSIT_AMOUNT);
        assertEq(
            vault.userDeposits(alice, IVaultMatch.Team.TeamA),
            DEPOSIT_AMOUNT
        );
    }

    function test_DepositTeamB() public {
        vm.startPrank(bob);
        USDC.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(IVaultMatch.Team.TeamB, DEPOSIT_AMOUNT);
        vm.stopPrank();

        assertEq(vault.totalTeamB(), DEPOSIT_AMOUNT);
        assertEq(
            vault.userDeposits(bob, IVaultMatch.Team.TeamB),
            DEPOSIT_AMOUNT
        );
    }

    function test_RevertDepositZeroAmount() public {
        vm.startPrank(alice);
        USDC.approve(address(vault), DEPOSIT_AMOUNT);
        vm.expectRevert(IVaultMatch.ZeroAmount.selector);
        vault.deposit(IVaultMatch.Team.TeamA, 0);
        vm.stopPrank();
    }

    function test_RevertDepositInvalidTeam() public {
        vm.startPrank(alice);
        USDC.approve(address(vault), DEPOSIT_AMOUNT);
        vm.expectRevert(IVaultMatch.InvalidTeam.selector);
        vault.deposit(IVaultMatch.Team.None, DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    // ─── Lifecycle: Lock + Resolve + Claim ───────────────────────────────

    function test_FullLifecycle() public {
        // Deposits
        vm.startPrank(alice);
        USDC.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(IVaultMatch.Team.TeamA, DEPOSIT_AMOUNT);
        vm.stopPrank();

        vm.startPrank(bob);
        USDC.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(IVaultMatch.Team.TeamB, DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Lock
        vm.prank(oracle);
        vault.lockMatch();
        assertEq(uint(vault.status()), uint(IVaultMatch.MatchStatus.Locked));

        // Resolve (Team A wins)
        vm.prank(oracle);
        vault.resolveMatch(IVaultMatch.Team.TeamA);
        assertEq(uint(vault.status()), uint(IVaultMatch.MatchStatus.Resolved));

        // Alice (winner) claims principal + any yield
        uint256 aliceBefore = USDC.balanceOf(alice);
        vm.prank(alice);
        vault.claim();
        uint256 alicePayout = USDC.balanceOf(alice) - aliceBefore;
        assertGe(alicePayout, DEPOSIT_AMOUNT); // At minimum gets principal back

        // Bob (loser) claims principal only (may lose 1 wei to ERC4626 rounding)
        uint256 bobBefore = USDC.balanceOf(bob);
        vm.prank(bob);
        vault.claim();
        uint256 bobPayout = USDC.balanceOf(bob) - bobBefore;
        assertApproxEqAbs(bobPayout, DEPOSIT_AMOUNT, 1); // 1 wei tolerance for ERC4626 rounding
    }

    // ─── Division by Zero Guard ──────────────────────────────────────────

    function test_RevertResolveNoWinnerDeposits() public {
        // Everyone bets Team A, then Team B wins -> should revert
        vm.startPrank(alice);
        USDC.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(IVaultMatch.Team.TeamA, DEPOSIT_AMOUNT);
        vm.stopPrank();

        vm.prank(oracle);
        vault.lockMatch();

        vm.prank(oracle);
        vm.expectRevert(IVaultMatch.NoWinnerDeposits.selector);
        vault.resolveMatch(IVaultMatch.Team.TeamB); // Nobody bet on B
    }

    // ─── Safety Module ───────────────────────────────────────────────────

    function test_EmergencyPauseAndRefund() public {
        vm.startPrank(alice);
        USDC.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(IVaultMatch.Team.TeamA, DEPOSIT_AMOUNT);
        vm.stopPrank();

        vm.prank(owner);
        vault.pause();

        // Deposits should revert when paused
        vm.startPrank(bob);
        USDC.approve(address(vault), DEPOSIT_AMOUNT);
        vm.expectRevert();
        vault.deposit(IVaultMatch.Team.TeamB, DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Emergency refund Alice
        uint256 aliceBefore = USDC.balanceOf(alice);
        vm.prank(owner);
        vault.emergencyRefund(alice);
        assertEq(USDC.balanceOf(alice) - aliceBefore, DEPOSIT_AMOUNT);
    }

    // function test_EmergencyWithdrawFromYield() public {
    //     // Deposit + Lock (funds go to Morpho)
    //     vm.startPrank(alice);
    //     USDC.approve(address(vault), DEPOSIT_AMOUNT);
    //     vault.deposit(IVaultMatch.Team.TeamA, DEPOSIT_AMOUNT);
    //     vm.stopPrank();

    //     vm.startPrank(bob);
    //     USDC.approve(address(vault), DEPOSIT_AMOUNT);
    //     vault.deposit(IVaultMatch.Team.TeamB, DEPOSIT_AMOUNT);
    //     vm.stopPrank();

    //     vm.prank(oracle);
    //     vault.lockMatch();
    //     // Funds are now in Morpho, vault balance should be ~0
    //     assertEq(USDC.balanceOf(address(vault)), 0);

    //     // Pause + emergency withdraw from yield
    //     vm.startPrank(owner);
    //     vault.pause();
    //     vault.emergencyWithdrawFromYield();
    //     vm.stopPrank();

    //     // Funds should be back in vault (may be 1 wei less due to ERC4626 rounding)
    //     assertApproxEqAbs(USDC.balanceOf(address(vault)), 200e6, 1);

    //     // Now refunds work
    //     uint256 aliceBefore = USDC.balanceOf(alice);
    //     vm.prank(owner);
    //     vault.emergencyRefund(alice);
    //     assertApproxEqAbs(
    //         USDC.balanceOf(alice) - aliceBefore,
    //         DEPOSIT_AMOUNT,
    //         1
    //     );
    // }

    function test_RevertClaimBeforeResolution() public {
        vm.startPrank(alice);
        USDC.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(IVaultMatch.Team.TeamA, DEPOSIT_AMOUNT);
        vm.expectRevert(IVaultMatch.MatchNotResolved.selector);
        vault.claim();
        vm.stopPrank();
    }

    function test_RevertDoubleClaim() public {
        vm.startPrank(alice);
        USDC.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(IVaultMatch.Team.TeamA, DEPOSIT_AMOUNT);
        vm.stopPrank();

        vm.startPrank(bob);
        USDC.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(IVaultMatch.Team.TeamB, DEPOSIT_AMOUNT);
        vm.stopPrank();

        vm.prank(oracle);
        vault.lockMatch();
        vm.prank(oracle);
        vault.resolveMatch(IVaultMatch.Team.TeamA);

        vm.prank(alice);
        vault.claim();

        vm.prank(alice);
        vm.expectRevert(IVaultMatch.AlreadyClaimed.selector);
        vault.claim();
    }

    // ─── Factory Tests ───────────────────────────────────────────────────

    function test_FactoryCreatesMultipleMatches() public {
        vm.startPrank(owner);
        (, address v1) = factory.createMatch("DRX", "Fnatic");
        (, address v2) = factory.createMatch("Paper Rex", "Gen.G");
        vm.stopPrank();

        assertEq(factory.totalMatches(), 3); // setUp + 2
        assertTrue(v1 != v2);
        assertEq(factory.getVault(2), v1);
        assertEq(factory.getVault(3), v2);

        // Verify team names
        VaultMatch v = VaultMatch(v1);
        assertEq(v.teamAName(), "DRX");
        assertEq(v.teamBName(), "Fnatic");
    }

    // ─── Team Name Tests ─────────────────────────────────────────────────

    function test_TeamNames() public view {
        assertEq(vault.teamAName(), "Sentinels");
        assertEq(vault.teamBName(), "LOUD");
    }
}
