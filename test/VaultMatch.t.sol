// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {FactoryMatch} from "../src/FactoryMatch.sol";
import {VaultMatch} from "../src/VaultMatch.sol";
import {IVaultMatch} from "../src/interfaces/IVaultMatch.sol";
import {MockYieldProtocol} from "../src/mock/MockYieldProtocol.sol";
import {USDCMock} from "../src/mock/USDCMock.sol";

/// @title VaultMatchTest
/// @notice Full lifecycle test for the EcoRound no-loss prediction market
contract VaultMatchTest is Test {
    FactoryMatch public factory;
    VaultMatch public vault;
    MockYieldProtocol public yieldProtocol;
    USDCMock public usdc;

    address owner = makeAddr("owner");
    address oracle = makeAddr("oracle");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");

    uint256 constant DEPOSIT_AMOUNT = 100e6; // 100 USDC (6 decimals)
    uint256 constant YIELD_BPS = 500; // 5% yield

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mocks
        usdc = new USDCMock();
        yieldProtocol = new MockYieldProtocol(YIELD_BPS);

        // Deploy factory
        factory = new FactoryMatch(
            owner,
            oracle,
            address(usdc),
            address(yieldProtocol)
        );

        // Create a match
        (, address vaultAddr) = factory.createMatch();
        vault = VaultMatch(vaultAddr);

        vm.stopPrank();

        // Fund users with USDC
        usdc.mint(alice, 1000e6);
        usdc.mint(bob, 1000e6);
        usdc.mint(charlie, 1000e6);

        // Fund yield protocol with extra tokens to simulate yield payout
        usdc.mint(address(yieldProtocol), 10_000e6);
    }

    // ─── Deposit Tests ───────────────────────────────────────────────────

    function test_DepositTeamA() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
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
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
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
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vm.expectRevert(IVaultMatch.ZeroAmount.selector);
        vault.deposit(IVaultMatch.Team.TeamA, 0);
        vm.stopPrank();
    }

    function test_RevertDepositInvalidTeam() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vm.expectRevert(IVaultMatch.InvalidTeam.selector);
        vault.deposit(IVaultMatch.Team.None, DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    // ─── Full Lifecycle: Winners Get Yield, Losers Get Principal ─────────

    function test_FullLifecycle_WinnersGetYield() public {
        // 1. Deposits: Alice bets 100 USDC on Team A, Bob bets 100 USDC on Team B
        vm.startPrank(alice);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(IVaultMatch.Team.TeamA, DEPOSIT_AMOUNT);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(IVaultMatch.Team.TeamB, DEPOSIT_AMOUNT);
        vm.stopPrank();

        // 2. Lock match (oracle) — deposits go to yield protocol
        vm.prank(oracle);
        vault.lockMatch();
        assertEq(uint(vault.status()), uint(IVaultMatch.MatchStatus.Locked));

        // 3. Resolve match — Team A wins. Yield protocol returns principal + 5%
        //    Total deposited: 200 USDC. Expected withdrawal: 210 USDC (5% yield)
        vm.prank(oracle);
        vault.resolveMatch(IVaultMatch.Team.TeamA);
        assertEq(uint(vault.status()), uint(IVaultMatch.MatchStatus.Resolved));

        // Yield = 210 - 200 = 10 USDC
        assertEq(vault.totalYield(), 10e6);

        // 4. Alice (winner) claims: 100 principal + 10 yield = 110 USDC
        uint256 aliceBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        vault.claim();
        uint256 aliceAfter = usdc.balanceOf(alice);
        assertEq(aliceAfter - aliceBefore, 110e6);

        // 5. Bob (loser) claims: 100 principal only = 100 USDC (no loss!)
        uint256 bobBefore = usdc.balanceOf(bob);
        vm.prank(bob);
        vault.claim();
        uint256 bobAfter = usdc.balanceOf(bob);
        assertEq(bobAfter - bobBefore, 100e6);
    }

    // ─── Multi-Winner Proportional Yield ─────────────────────────────────

    function test_ProportionalYieldDistribution() public {
        // Alice deposits 300 USDC on Team A
        vm.startPrank(alice);
        usdc.approve(address(vault), 300e6);
        vault.deposit(IVaultMatch.Team.TeamA, 300e6);
        vm.stopPrank();

        // Charlie deposits 100 USDC on Team A
        vm.startPrank(charlie);
        usdc.approve(address(vault), 100e6);
        vault.deposit(IVaultMatch.Team.TeamA, 100e6);
        vm.stopPrank();

        // Bob deposits 200 USDC on Team B
        vm.startPrank(bob);
        usdc.approve(address(vault), 200e6);
        vault.deposit(IVaultMatch.Team.TeamB, 200e6);
        vm.stopPrank();

        // Total: 600 USDC. 5% yield = 30 USDC. Team A total: 400 USDC
        vm.prank(oracle);
        vault.lockMatch();

        vm.prank(oracle);
        vault.resolveMatch(IVaultMatch.Team.TeamA);

        assertEq(vault.totalYield(), 30e6);

        // Alice: 300/400 of 30 yield = 22.5 USDC → payout = 300 + 22 = 322 (truncated)
        uint256 aliceBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        vault.claim();
        assertEq(usdc.balanceOf(alice) - aliceBefore, 300e6 + 22_500_000);

        // Charlie: 100/400 of 30 yield = 7.5 USDC → payout = 100 + 7.5 = 107.5
        uint256 charlieBefore = usdc.balanceOf(charlie);
        vm.prank(charlie);
        vault.claim();
        assertEq(usdc.balanceOf(charlie) - charlieBefore, 100e6 + 7_500_000);

        // Bob (loser): 200 principal only
        uint256 bobBefore = usdc.balanceOf(bob);
        vm.prank(bob);
        vault.claim();
        assertEq(usdc.balanceOf(bob) - bobBefore, 200e6);
    }

    // ─── Safety Module Tests ─────────────────────────────────────────────

    function test_EmergencyPauseAndRefund() public {
        // Alice deposits
        vm.startPrank(alice);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(IVaultMatch.Team.TeamA, DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Owner pauses
        vm.prank(owner);
        vault.pause();

        // Deposits should revert when paused
        vm.startPrank(bob);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vm.expectRevert();
        vault.deposit(IVaultMatch.Team.TeamB, DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Owner emergency refunds Alice
        uint256 aliceBefore = usdc.balanceOf(alice);
        vm.prank(owner);
        vault.emergencyRefund(alice);
        assertEq(usdc.balanceOf(alice) - aliceBefore, DEPOSIT_AMOUNT);
    }

    function test_RevertClaimBeforeResolution() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(IVaultMatch.Team.TeamA, DEPOSIT_AMOUNT);
        vm.expectRevert(IVaultMatch.MatchNotResolved.selector);
        vault.claim();
        vm.stopPrank();
    }

    function test_RevertDoubleClaim() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(IVaultMatch.Team.TeamA, DEPOSIT_AMOUNT);
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
        (, address v1) = factory.createMatch();
        (, address v2) = factory.createMatch();
        vm.stopPrank();

        // matchId 1 was created in setUp, so these are 2 and 3
        assertEq(factory.totalMatches(), 3);
        assertTrue(v1 != v2);
        assertEq(factory.getVault(2), v1);
        assertEq(factory.getVault(3), v2);
    }

    // ─── View Helper Tests ───────────────────────────────────────────────

    function test_GetExpectedPayout() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(IVaultMatch.Team.TeamA, DEPOSIT_AMOUNT);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(IVaultMatch.Team.TeamB, DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Before resolution, expected payout is 0
        assertEq(vault.getExpectedPayout(alice), 0);

        vm.prank(oracle);
        vault.lockMatch();
        vm.prank(oracle);
        vault.resolveMatch(IVaultMatch.Team.TeamA);

        // After resolution: alice (winner) = 100 + 10 = 110, bob (loser) = 100
        assertEq(vault.getExpectedPayout(alice), 110e6);
        assertEq(vault.getExpectedPayout(bob), 100e6);
    }
}
