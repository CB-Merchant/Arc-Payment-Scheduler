// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PaymentSchedulerTestBase} from "./PaymentScheduler.Base.t.sol";
import {PaymentScheduler} from "../PaymentScheduler.sol";
import {FeeOnTransferERC20} from "../test-helpers/MockERC20.sol";

contract PaymentSchedulerCreateTest is PaymentSchedulerTestBase {
    // ---------- constructor ----------
    function test_Constructor_SetsTokenAndNextId() public view {
        assertEq(address(sched.token()), address(token));
        assertEq(sched.nextId(), 1);
        assertEq(sched.scheduleCount(), 0);
        assertEq(sched.MAX_INSTALLMENTS(), 1000);
        assertEq(sched.MIN_INTERVAL(), 1 hours);
        assertEq(sched.MAX_INTERVAL(), 365 days);
        assertEq(sched.MAX_MEMO_BYTES(), 64);
    }

    function test_Constructor_RevertsOnZeroToken() public {
        vm.expectRevert(PaymentScheduler.InvalidToken.selector);
        new PaymentScheduler(address(0));
    }

    // ---------- create happy path ----------
    function test_Create_EscrowsTotalAndStoresSchedule() public {
        uint256 balBefore = token.balanceOf(alice);
        uint256 id = _createStd();
        assertEq(id, 1);
        assertEq(sched.nextId(), 2);
        assertEq(sched.scheduleCount(), 1);
        assertEq(token.balanceOf(address(sched)), uint256(AMT) * N);
        assertEq(token.balanceOf(alice), balBefore - uint256(AMT) * N);

        PaymentScheduler.Schedule memory s = sched.getSchedule(id);
        assertEq(s.sender, alice);
        assertEq(s.recipient, bob);
        assertEq(s.amount, AMT);
        assertEq(s.installments, N);
        assertEq(s.paid, 0);
        assertEq(s.startTime, START);
        assertEq(s.interval, DAY);
        assertFalse(s.cancelled);
        assertEq(s.owed, 0);
        assertEq(s.memo, "std");
    }

    function test_Create_OneTimeSchedule() public {
        uint256 id = _createOneTime();
        PaymentScheduler.Schedule memory s = sched.getSchedule(id);
        assertEq(s.installments, 1);
        assertEq(s.interval, 0);
        assertEq(token.balanceOf(address(sched)), AMT);
    }

    function test_Create_StartExactlyNowAllowed() public {
        uint256 id = _create(alice, bob, AMT, 1, uint48(T0), 0);
        assertEq(sched.releasableAmount(id), AMT);
    }

    function test_Create_MaxInstallmentsAndIntervalBounds() public {
        _create(alice, bob, 1, 1000, START, 1 hours);
        _create(alice, bob, 1, 2, START, 365 days);
        assertEq(sched.scheduleCount(), 2);
    }

    function test_Create_MemoExactly64BytesAllowed() public {
        bytes memory m = new bytes(64);
        for (uint256 i; i < 64; i++) {
            m[i] = "a";
        }
        vm.prank(alice);
        uint256 id = sched.createSchedule(bob, AMT, 1, START, 0, string(m));
        assertEq(bytes(sched.getSchedule(id).memo).length, 64);
    }

    function test_Create_IdsIncrementAndIndexed() public {
        uint256 a = _createStd();
        uint256 b = _createOneTime();
        assertEq(a, 1);
        assertEq(b, 2);
        uint256[] memory ids = sched.getSchedulesBySender(alice, 0, 10);
        assertEq(ids.length, 2);
        assertEq(ids[0], 1);
        assertEq(ids[1], 2);
        ids = sched.getSchedulesByRecipient(bob, 0, 10);
        assertEq(ids.length, 2);
    }

    function test_Create_EmitsScheduleCreated() public {
        vm.expectEmit(true, true, true, true, address(sched));
        emit PaymentScheduler.ScheduleCreated(1, alice, bob, AMT, N, START, DAY, "std");
        _createStd();
    }

    // ---------- create reverts ----------
    function test_Create_RevertsZeroRecipient() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.InvalidRecipient.selector, address(0)));
        sched.createSchedule(address(0), AMT, N, START, DAY, "");
    }

    function test_Create_RevertsSelfRecipient() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.InvalidRecipient.selector, address(sched)));
        sched.createSchedule(address(sched), AMT, N, START, DAY, "");
    }

    function test_Create_RevertsRecipientIsSender() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.InvalidRecipient.selector, alice));
        sched.createSchedule(alice, AMT, N, START, DAY, "");
    }

    function test_Create_RevertsZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(PaymentScheduler.InvalidAmount.selector);
        sched.createSchedule(bob, 0, N, START, DAY, "");
    }

    function test_Create_RevertsZeroInstallments() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.InvalidInstallments.selector, uint32(0)));
        sched.createSchedule(bob, AMT, 0, START, DAY, "");
    }

    function test_Create_RevertsTooManyInstallments() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.InvalidInstallments.selector, uint32(1001)));
        sched.createSchedule(bob, AMT, 1001, START, DAY, "");
    }

    function test_Create_RevertsStartInPast() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentScheduler.StartTimeInPast.selector, uint48(T0 - 1), uint256(T0))
        );
        sched.createSchedule(bob, AMT, N, uint48(T0 - 1), DAY, "");
    }

    function test_Create_RevertsOneTimeWithInterval() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.InvalidInterval.selector, DAY, uint32(1)));
        sched.createSchedule(bob, AMT, 1, START, DAY, "");
    }

    function test_Create_RevertsRecurringIntervalTooSmall() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.InvalidInterval.selector, uint32(3599), N));
        sched.createSchedule(bob, AMT, N, START, 3599, "");
    }

    function test_Create_RevertsRecurringZeroInterval() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.InvalidInterval.selector, uint32(0), N));
        sched.createSchedule(bob, AMT, N, START, 0, "");
    }

    function test_Create_RevertsRecurringIntervalTooLarge() public {
        uint32 tooBig = uint32(365 days) + 1;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.InvalidInterval.selector, tooBig, N));
        sched.createSchedule(bob, AMT, N, START, tooBig, "");
    }

    function test_Create_RevertsMemoTooLong() public {
        bytes memory m = new bytes(65);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.MemoTooLong.selector, uint256(65), uint256(64)));
        sched.createSchedule(bob, AMT, N, START, DAY, string(m));
    }

    function test_Create_RevertsInsufficientAllowance() public {
        address dave = makeAddr("dave");
        token.mint(dave, 1000e6);
        vm.prank(dave);
        vm.expectRevert();
        sched.createSchedule(bob, AMT, N, START, DAY, "");
        assertEq(sched.scheduleCount(), 0);
    }

    function test_Create_RevertsInsufficientBalance() public {
        address dave = makeAddr("dave");
        token.mint(dave, 10e6);
        vm.startPrank(dave);
        token.approve(address(sched), type(uint256).max);
        vm.expectRevert();
        sched.createSchedule(bob, AMT, N, START, DAY, "");
        vm.stopPrank();
        assertEq(sched.nextId(), 1);
    }

    function test_Create_RejectsFeeOnTransferToken() public {
        FeeOnTransferERC20 fee = new FeeOnTransferERC20();
        PaymentScheduler s2 = new PaymentScheduler(address(fee));
        fee.mint(alice, 1_000e6);
        vm.startPrank(alice);
        fee.approve(address(s2), type(uint256).max);
        uint256 total = uint256(AMT) * N;
        uint256 received = total - total / 100;
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.IncorrectDeposit.selector, total, received));
        s2.createSchedule(bob, AMT, N, START, DAY, "");
        vm.stopPrank();
        // state rolled back
        assertEq(s2.scheduleCount(), 0);
        assertEq(fee.balanceOf(alice), 1_000e6);
        assertEq(fee.balanceOf(address(s2)), 0);
    }
}
