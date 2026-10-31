// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PaymentSchedulerTestBase} from "./PaymentScheduler.Base.t.sol";
import {PaymentScheduler} from "../PaymentScheduler.sol";

contract PaymentSchedulerCancelTest is PaymentSchedulerTestBase {
    uint256 internal id;
    uint256 internal total;

    function setUp() public override {
        super.setUp();
        id = _createStd();
        total = uint256(AMT) * N;
    }

    // ---------- cancel: happy paths ----------
    function test_Cancel_BeforeStart_RefundsEverything() public {
        uint256 aliceBefore = token.balanceOf(alice);
        vm.expectEmit(true, true, false, true, address(sched));
        emit PaymentScheduler.Cancelled(id, alice, 0, total);
        vm.prank(alice);
        sched.cancel(id);

        assertEq(token.balanceOf(alice), aliceBefore + total);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(sched)), 0);
        PaymentScheduler.Schedule memory s = sched.getSchedule(id);
        assertTrue(s.cancelled);
        assertEq(s.paid, N);
        assertEq(s.owed, 0);
        assertEq(sched.releasableAmount(id), 0);
    }

    function test_Cancel_ExactlyAtStart_PaysOneRefundsRest() public {
        _warpTo(START);
        vm.expectEmit(true, true, false, true, address(sched));
        emit PaymentScheduler.Cancelled(id, alice, AMT, 4 * uint256(AMT));
        vm.prank(alice);
        sched.cancel(id);
        assertEq(token.balanceOf(bob), AMT);
        assertEq(token.balanceOf(address(sched)), 0);
    }

    function test_Cancel_MidSchedule_PaysDueRefundsFuture() public {
        _warpTo(START + DAY + 7); // 2 due
        uint256 aliceBefore = token.balanceOf(alice);
        vm.expectEmit(true, true, false, true, address(sched));
        emit PaymentScheduler.Cancelled(id, alice, 2 * uint256(AMT), 3 * uint256(AMT));
        vm.prank(alice);
        sched.cancel(id);
        assertEq(token.balanceOf(bob), 2 * uint256(AMT));
        assertEq(token.balanceOf(alice), aliceBefore + 3 * uint256(AMT));
        assertEq(token.balanceOf(address(sched)), 0);
    }

    function test_Cancel_AfterPartialRelease_OnlyUnreleasedSettled() public {
        _warpTo(START);
        sched.release(id); // 1 paid
        _warpTo(START + DAY); // #2 now due
        uint256 aliceBefore = token.balanceOf(alice);
        vm.prank(alice);
        sched.cancel(id);
        assertEq(token.balanceOf(bob), 2 * uint256(AMT));
        assertEq(token.balanceOf(alice), aliceBefore + 3 * uint256(AMT));
        assertEq(token.balanceOf(address(sched)), 0);
    }

    function test_Cancel_AfterLastDueUnreleased_PaysAllNoRefund() public {
        _warpTo(START + 100 * uint256(DAY));
        uint256 aliceBefore = token.balanceOf(alice);
        vm.expectEmit(true, true, false, true, address(sched));
        emit PaymentScheduler.Cancelled(id, alice, total, 0);
        vm.prank(alice);
        sched.cancel(id);
        assertEq(token.balanceOf(bob), total);
        assertEq(token.balanceOf(alice), aliceBefore);
    }

    function test_Cancel_OneTime_BeforeAndAfterStart() public {
        uint256 oid = _createOneTime();
        uint256 aliceBefore = token.balanceOf(alice);
        vm.prank(alice);
        sched.cancel(oid);
        assertEq(token.balanceOf(alice), aliceBefore + AMT);

        uint256 oid2 = _createOneTime();
        _warpTo(START);
        vm.prank(alice);
        sched.cancel(oid2);
        assertEq(token.balanceOf(bob), AMT);
    }

    // ---------- cancel: reverts ----------
    function test_Cancel_RevertsNotSender() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.NotSender.selector, id, bob));
        sched.cancel(id);
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.NotSender.selector, id, carol));
        sched.cancel(id);
    }

    function test_Cancel_RevertsUnknownId() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.UnknownSchedule.selector, uint256(42)));
        sched.cancel(42);
    }

    function test_Cancel_RevertsAlreadyCancelled() public {
        vm.startPrank(alice);
        sched.cancel(id);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.ScheduleCancelled.selector, id));
        sched.cancel(id);
        vm.stopPrank();
    }

    function test_Cancel_RevertsWhenFullyReleased() public {
        _warpTo(START + 10 * uint256(DAY));
        sched.release(id);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.NothingRemaining.selector, id));
        sched.cancel(id);
    }

    // ---------- blocklisted recipient on cancel ----------
    function test_Cancel_BlockedRecipient_RecordsOwedAndRefundsFuture() public {
        _warpTo(START + DAY); // 2 due
        token.setBlocked(bob, true);
        uint256 aliceBefore = token.balanceOf(alice);

        vm.expectEmit(true, true, false, true, address(sched));
        emit PaymentScheduler.ClaimRecorded(id, bob, 2 * uint256(AMT));
        vm.expectEmit(true, true, false, true, address(sched));
        emit PaymentScheduler.Cancelled(id, alice, 0, 3 * uint256(AMT));
        vm.prank(alice);
        sched.cancel(id);

        PaymentScheduler.Schedule memory s = sched.getSchedule(id);
        assertEq(s.owed, 2 * uint256(AMT));
        assertTrue(s.cancelled);
        assertEq(token.balanceOf(alice), aliceBefore + 3 * uint256(AMT)); // only future refunded
        assertEq(token.balanceOf(address(sched)), 2 * uint256(AMT)); // owed stays escrowed
        assertEq(sched.releasableAmount(id), 0);
    }

    function test_Cancel_BlockedRecipient_NothingDue_NoClaim() public {
        token.setBlocked(bob, true);
        vm.prank(alice);
        sched.cancel(id); // before start: nothing due, full refund
        assertEq(sched.getSchedule(id).owed, 0);
        assertEq(token.balanceOf(address(sched)), 0);
    }

    function test_Cancel_BlockedRecipient_AllDue_NoRefundTransfer() public {
        _warpTo(START + 100 * uint256(DAY));
        token.setBlocked(bob, true);
        uint256 aliceBefore = token.balanceOf(alice);
        vm.prank(alice);
        sched.cancel(id);
        assertEq(sched.getSchedule(id).owed, total);
        assertEq(token.balanceOf(alice), aliceBefore);
        assertEq(token.balanceOf(address(sched)), total);
    }

    function test_Cancel_BlockedSender_RevertsEntireCancellation() public {
        _warpTo(START + DAY); // 2 due, 3 refundable
        token.setBlocked(alice, true);
        vm.prank(alice);
        vm.expectRevert(bytes("blocked"));
        sched.cancel(id);
        // fully rolled back: recipient not paid, schedule still live
        PaymentScheduler.Schedule memory s = sched.getSchedule(id);
        assertFalse(s.cancelled);
        assertEq(s.paid, 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(sched)), total);
        // recipient releases are unaffected
        sched.release(id);
        assertEq(token.balanceOf(bob), 2 * uint256(AMT));
    }

    function test_Cancel_BlockedSender_ZeroRefundSkipsTransfer() public {
        _warpTo(START + 100 * uint256(DAY)); // all due -> refund 0
        token.setBlocked(alice, true);
        vm.prank(alice);
        sched.cancel(id); // must not revert
        assertEq(token.balanceOf(bob), total);
    }

    // ---------- claim flow ----------
    function _cancelWithBlockedRecipient() internal {
        _warpTo(START + DAY);
        token.setBlocked(bob, true);
        vm.prank(alice);
        sched.cancel(id);
    }

    function test_Claim_WhileStillBlocked_RevertsAndRestoresOwed() public {
        _cancelWithBlockedRecipient();
        vm.expectRevert(bytes("blocked"));
        sched.claim(id);
        assertEq(sched.getSchedule(id).owed, 2 * uint256(AMT));
        assertEq(token.balanceOf(address(sched)), 2 * uint256(AMT));
    }

    function test_Claim_ReassignThenClaim_PaysNewRecipient() public {
        _cancelWithBlockedRecipient();
        vm.prank(bob);
        sched.reassignRecipient(id, carol);

        vm.expectEmit(true, true, false, true, address(sched));
        emit PaymentScheduler.Claimed(id, carol, 2 * uint256(AMT), keeper);
        vm.prank(keeper);
        uint256 paid = sched.claim(id);

        assertEq(paid, 2 * uint256(AMT));
        assertEq(token.balanceOf(carol), 2 * uint256(AMT));
        assertEq(token.balanceOf(keeper), 0);
        assertEq(token.balanceOf(address(sched)), 0);
        assertEq(sched.getSchedule(id).owed, 0);

        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.NothingRemaining.selector, id));
        sched.claim(id);
    }

    function test_Claim_ReassignToSenderPaysSender() public {
        // recipient can redirect an owed claim to the original sender (allowed by spec)
        _cancelWithBlockedRecipient();
        vm.prank(bob);
        sched.reassignRecipient(id, alice);
        uint256 aliceBefore = token.balanceOf(alice);
        sched.claim(id);
        assertEq(token.balanceOf(alice), aliceBefore + 2 * uint256(AMT));
    }

    function test_Claim_RevertsNothingOwed() public {
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.NothingRemaining.selector, id));
        sched.claim(id);
    }

    function test_Claim_RevertsUnknownId() public {
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.UnknownSchedule.selector, uint256(77)));
        sched.claim(77);
    }

    function test_Claim_UnblockedRecipientCanBeClaimedDirectly() public {
        _cancelWithBlockedRecipient();
        token.setBlocked(bob, false);
        sched.claim(id);
        assertEq(token.balanceOf(bob), 2 * uint256(AMT));
    }
}
