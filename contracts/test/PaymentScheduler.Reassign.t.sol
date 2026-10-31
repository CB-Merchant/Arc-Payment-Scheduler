// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PaymentSchedulerTestBase} from "./PaymentScheduler.Base.t.sol";
import {PaymentScheduler} from "../PaymentScheduler.sol";

contract PaymentSchedulerReassignTest is PaymentSchedulerTestBase {
    uint256 internal id;

    function setUp() public override {
        super.setUp();
        id = _createStd();
    }

    // ---------- reassign happy ----------
    function test_Reassign_ChangesRecipientAndEmits() public {
        vm.expectEmit(true, true, true, true, address(sched));
        emit PaymentScheduler.RecipientChanged(id, bob, carol);
        vm.prank(bob);
        sched.reassignRecipient(id, carol);
        assertEq(sched.getSchedule(id).recipient, carol);
        uint256[] memory ids = sched.getSchedulesByRecipient(carol, 0, 10);
        assertEq(ids.length, 1);
        assertEq(ids[0], id);
        // history for old recipient is retained (stale)
        assertEq(sched.getSchedulesByRecipient(bob, 0, 10).length, 1);
    }

    function test_Reassign_OldRecipientLosesRights() public {
        vm.prank(bob);
        sched.reassignRecipient(id, carol);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.NotRecipient.selector, id, bob));
        sched.reassignRecipient(id, keeper);
        vm.prank(carol);
        sched.reassignRecipient(id, keeper);
        assertEq(sched.getSchedule(id).recipient, keeper);
    }

    function test_Reassign_ToOriginalSenderAllowed() public {
        vm.prank(bob);
        sched.reassignRecipient(id, alice);
        assertEq(sched.getSchedule(id).recipient, alice);
        _warpTo(START);
        sched.release(id);
        assertEq(token.balanceOf(alice), 1_000_000e6 - uint256(AMT) * N + AMT);
    }

    function test_Reassign_BackAndForthDuplicatesHistory() public {
        vm.prank(bob);
        sched.reassignRecipient(id, carol);
        vm.prank(carol);
        sched.reassignRecipient(id, bob);
        uint256[] memory ids = sched.getSchedulesByRecipient(bob, 0, 10);
        assertEq(ids.length, 2); // create + re-assign
        assertEq(ids[0], id);
        assertEq(ids[1], id);
    }

    function test_Reassign_AfterPartialRelease_Allowed() public {
        _warpTo(START);
        sched.release(id);
        vm.prank(bob);
        sched.reassignRecipient(id, carol);
        _warpTo(START + DAY);
        sched.release(id);
        assertEq(token.balanceOf(bob), AMT);
        assertEq(token.balanceOf(carol), AMT);
    }

    function test_Reassign_CancelledWithOwed_Allowed() public {
        _warpTo(START);
        token.setBlocked(bob, true);
        vm.prank(alice);
        sched.cancel(id);
        assertEq(sched.getSchedule(id).owed, AMT);
        vm.prank(bob);
        sched.reassignRecipient(id, carol);
        assertEq(sched.getSchedule(id).recipient, carol);
    }

    // ---------- reassign reverts ----------
    function test_Reassign_RevertsNotRecipient() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.NotRecipient.selector, id, alice));
        sched.reassignRecipient(id, carol);
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.NotRecipient.selector, id, carol));
        sched.reassignRecipient(id, carol);
    }

    function test_Reassign_RevertsUnknownId() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.UnknownSchedule.selector, uint256(9)));
        sched.reassignRecipient(9, carol);
    }

    function test_Reassign_RevertsZeroAddress() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.InvalidRecipient.selector, address(0)));
        sched.reassignRecipient(id, address(0));
    }

    function test_Reassign_RevertsToContractItself() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.InvalidRecipient.selector, address(sched)));
        sched.reassignRecipient(id, address(sched));
    }

    function test_Reassign_RevertsUnchangedRecipient() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.InvalidRecipient.selector, bob));
        sched.reassignRecipient(id, bob);
    }

    function test_Reassign_RevertsCancelledWithNothingOwed() public {
        vm.prank(alice);
        sched.cancel(id);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.ScheduleCancelled.selector, id));
        sched.reassignRecipient(id, carol);
    }

    function test_Reassign_RevertsFullyPaidNothingOwed() public {
        _warpTo(START + 10 * uint256(DAY));
        sched.release(id);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.NothingRemaining.selector, id));
        sched.reassignRecipient(id, carol);
    }

    function test_Reassign_RevertsAfterOwedClaimed() public {
        _warpTo(START);
        token.setBlocked(bob, true);
        vm.prank(alice);
        sched.cancel(id);
        vm.prank(bob);
        sched.reassignRecipient(id, carol);
        sched.claim(id);
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.ScheduleCancelled.selector, id));
        sched.reassignRecipient(id, keeper);
    }

    // ---------- pagination ----------
    function _createMany(uint256 n) internal {
        for (uint256 i; i < n; i++) {
            _create(alice, bob, 1e6, 1, START, 0);
        }
    }

    function test_Pagination_SenderPages() public {
        _createMany(4); // ids 2..5 (id 1 from setUp)
        uint256[] memory a = sched.getSchedulesBySender(alice, 0, 2);
        assertEq(a.length, 2);
        assertEq(a[0], 1);
        assertEq(a[1], 2);
        uint256[] memory b = sched.getSchedulesBySender(alice, 2, 2);
        assertEq(b.length, 2);
        assertEq(b[0], 3);
        assertEq(b[1], 4);
        uint256[] memory c = sched.getSchedulesBySender(alice, 4, 2);
        assertEq(c.length, 1);
        assertEq(c[0], 5);
    }

    function test_Pagination_LimitLargerThanRemaining() public {
        _createMany(2);
        uint256[] memory a = sched.getSchedulesBySender(alice, 1, type(uint256).max);
        assertEq(a.length, 2);
        assertEq(a[0], 2);
        assertEq(a[1], 3);
    }

    function test_Pagination_EmptyCases() public {
        _createMany(2); // 3 entries
        assertEq(sched.getSchedulesBySender(alice, 0, 0).length, 0, "zero limit");
        assertEq(sched.getSchedulesBySender(alice, 3, 5).length, 0, "offset == length");
        assertEq(sched.getSchedulesBySender(alice, 100, 5).length, 0, "offset beyond");
        assertEq(sched.getSchedulesBySender(alice, type(uint256).max, type(uint256).max).length, 0);
        assertEq(sched.getSchedulesBySender(carol, 0, 5).length, 0, "no schedules");
        assertEq(sched.getSchedulesByRecipient(alice, 0, 5).length, 0);
    }

    function test_Pagination_RecipientPages_IncludeClosedSchedules() public {
        _createMany(2);
        vm.prank(alice);
        sched.cancel(1); // closed schedules remain listed
        uint256[] memory r = sched.getSchedulesByRecipient(bob, 0, 10);
        assertEq(r.length, 3);
        assertEq(r[0], 1);
        uint256[] memory r2 = sched.getSchedulesByRecipient(bob, 1, 1);
        assertEq(r2.length, 1);
        assertEq(r2[0], 2);
        assertEq(sched.scheduleCount(), 3);
    }
}
