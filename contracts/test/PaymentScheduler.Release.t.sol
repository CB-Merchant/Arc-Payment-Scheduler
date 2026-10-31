// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PaymentSchedulerTestBase} from "./PaymentScheduler.Base.t.sol";
import {PaymentScheduler} from "../PaymentScheduler.sol";

contract PaymentSchedulerReleaseTest is PaymentSchedulerTestBase {
    uint256 internal id;

    function setUp() public override {
        super.setUp();
        id = _createStd();
    }

    // ---------- due-count boundaries ----------
    function test_Due_OneSecondBeforeStart_IsZero() public {
        _warpTo(START - 1);
        assertEq(sched.releasableAmount(id), 0);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.NothingDue.selector, id));
        sched.release(id);
    }

    function test_Due_ExactlyAtStart_IsOne() public {
        _warpTo(START);
        assertEq(sched.releasableAmount(id), AMT);
        vm.prank(keeper);
        uint256 paid = sched.release(id);
        assertEq(paid, AMT);
        assertEq(token.balanceOf(bob), AMT);
        assertEq(sched.getSchedule(id).paid, 1);
    }

    function test_Due_BetweenInstallments_NoExtra() public {
        _warpTo(START + DAY - 1);
        assertEq(sched.releasableAmount(id), AMT); // still only #1
        sched.release(id);
        // right after release, nothing due until next boundary
        assertEq(sched.releasableAmount(id), 0);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.NothingDue.selector, id));
        sched.release(id);
    }

    function test_Due_ExactlyAtSecondInstallment() public {
        _warpTo(START + DAY - 1);
        sched.release(id);
        _warpTo(START + DAY);
        assertEq(sched.releasableAmount(id), AMT);
        sched.release(id);
        assertEq(token.balanceOf(bob), 2 * uint256(AMT));
    }

    function test_Due_AfterLast_CapsAtInstallments() public {
        _warpTo(START + uint256(DAY) * 100);
        assertEq(sched.releasableAmount(id), uint256(AMT) * N);
        uint256 paid = sched.release(id);
        assertEq(paid, uint256(AMT) * N);
        assertEq(token.balanceOf(bob), uint256(AMT) * N);
        assertEq(token.balanceOf(address(sched)), 0);
        assertEq(sched.releasableAmount(id), 0);
    }

    function test_Due_ExactlyAtLastInstallment() public {
        _warpTo(START + uint256(DAY) * (N - 1) - 1);
        assertEq(sched.releasableAmount(id), uint256(AMT) * (N - 1));
        _warpTo(START + uint256(DAY) * (N - 1));
        assertEq(sched.releasableAmount(id), uint256(AMT) * N);
    }

    function test_CatchUp_SingleTransferForManyInstallments() public {
        _warpTo(START + 2 * uint256(DAY) + 5); // installments 1..3 due
        vm.prank(keeper);
        uint256 paid = sched.release(id);
        assertEq(paid, 3 * uint256(AMT));
        assertEq(token.balanceOf(bob), 3 * uint256(AMT));
        assertEq(token.balanceOf(keeper), 0, "keeper gets nothing");
        // later, remaining
        _warpTo(START + 10 * uint256(DAY));
        assertEq(sched.release(id), 2 * uint256(AMT));
        assertEq(sched.getSchedule(id).paid, N);
    }

    function test_Release_OneTimeAtStart() public {
        uint256 oid = _createOneTime();
        _warpTo(START - 1);
        assertEq(sched.releasableAmount(oid), 0);
        _warpTo(START);
        assertEq(sched.releasableAmount(oid), AMT);
        sched.release(oid);
        assertEq(token.balanceOf(bob), AMT);
        assertEq(sched.releasableAmount(oid), 0);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.NothingDue.selector, oid));
        sched.release(oid);
    }

    function test_Release_EmitsReleased() public {
        _warpTo(START + DAY);
        vm.expectEmit(true, true, false, true, address(sched));
        emit PaymentScheduler.Released(id, bob, 2, 2 * uint256(AMT), keeper);
        vm.prank(keeper);
        sched.release(id);
    }

    function test_Release_PaysCurrentRecipientAfterReassign() public {
        vm.prank(bob);
        sched.reassignRecipient(id, carol);
        _warpTo(START);
        sched.release(id);
        assertEq(token.balanceOf(carol), AMT);
        assertEq(token.balanceOf(bob), 0);
    }

    // ---------- release reverts ----------
    function test_Release_RevertsUnknownId() public {
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.UnknownSchedule.selector, uint256(99)));
        sched.release(99);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.UnknownSchedule.selector, uint256(0)));
        sched.release(0);
    }

    function test_Release_RevertsWhenCancelled() public {
        _warpTo(START);
        vm.prank(alice);
        sched.cancel(id);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.ScheduleCancelled.selector, id));
        sched.release(id);
    }

    function test_Release_BlockedRecipientRevertsAndKeepsPaid() public {
        token.setBlocked(bob, true);
        _warpTo(START);
        vm.expectRevert(bytes("blocked"));
        sched.release(id);
        assertEq(sched.getSchedule(id).paid, 0);
        assertEq(sched.releasableAmount(id), AMT);
    }

    // ---------- views revert on unknown id ----------
    function test_Views_UnknownIdReverts() public {
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.UnknownSchedule.selector, uint256(5)));
        sched.getSchedule(5);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.UnknownSchedule.selector, uint256(5)));
        sched.releasableAmount(5);
    }
}
