// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PaymentSchedulerTestBase} from "./PaymentScheduler.Base.t.sol";
import {PaymentScheduler} from "../PaymentScheduler.sol";

contract PaymentSchedulerFuzzTest is PaymentSchedulerTestBase {
    function setUp() public override {
        super.setUp();
        token.mint(alice, 1e30);
    }

    struct P {
        uint128 amt;
        uint32 n;
        uint48 start;
        uint32 interval;
    }

    function _params(uint128 amt, uint32 n, uint256 startOff, uint32 interval) internal view returns (P memory p) {
        p.amt = uint128(bound(amt, 1, 1e15));
        p.n = uint32(bound(n, 1, 1000));
        p.start = uint48(T0 + bound(startOff, 0, 365 days));
        p.interval = p.n == 1 ? 0 : uint32(bound(interval, 1 hours, 365 days));
    }

    /// @dev Spec F3: installment k due at start + (k-1)*interval.
    function _expectedDue(P memory p, uint256 ts, uint256 alreadyPaid) internal pure returns (uint256) {
        if (ts < p.start) return 0;
        uint256 total = p.n == 1 ? 1 : 1 + (ts - p.start) / p.interval;
        if (total > p.n) total = p.n;
        return total - alreadyPaid;
    }

    function testFuzz_DueCountMatchesSpecAndNeverExceedsInstallments(
        uint128 amt,
        uint32 n,
        uint256 startOff,
        uint32 interval,
        uint256 dt
    ) public {
        P memory p = _params(amt, n, startOff, interval);
        uint256 id = _create(alice, bob, p.amt, p.n, p.start, p.interval);
        uint256 ts = T0 + bound(dt, 0, 1100 * uint256(365 days));
        _warpTo(ts);
        uint256 expected = _expectedDue(p, ts, 0);
        assertLe(expected, p.n);
        assertEq(sched.releasableAmount(id), expected * p.amt);
    }

    function testFuzz_NoReleaseBeforeStart(uint128 amt, uint32 n, uint256 startOff, uint32 interval, uint256 dt)
        public
    {
        P memory p = _params(amt, n, startOff, interval);
        p.start = uint48(T0 + 1 + bound(startOff, 0, 365 days)); // strictly future
        uint256 id = _create(alice, bob, p.amt, p.n, p.start, p.interval);
        _warpTo(T0 + bound(dt, 0, p.start - T0 - 1)); // anywhere before start
        assertEq(sched.releasableAmount(id), 0);
        vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.NothingDue.selector, id));
        sched.release(id);
        assertEq(token.balanceOf(bob), 0);
    }

    function testFuzz_ReleaseTwiceTotalsNeverExceedEscrow(
        uint128 amt,
        uint32 n,
        uint256 startOff,
        uint32 interval,
        uint256 dt1,
        uint256 dt2
    ) public {
        P memory p = _params(amt, n, startOff, interval);
        uint256 id = _create(alice, bob, p.amt, p.n, p.start, p.interval);
        uint256 t1 = p.start + bound(dt1, 0, 400 * uint256(365 days));
        uint256 t2 = t1 + bound(dt2, 0, 400 * uint256(365 days));
        _warpTo(t1);
        uint256 exp1 = _expectedDue(p, t1, 0);
        assertEq(sched.release(id), exp1 * p.amt);
        _warpTo(t2);
        uint256 exp2 = _expectedDue(p, t2, exp1);
        if (exp2 > 0) {
            assertEq(sched.release(id), exp2 * p.amt);
        } else {
            vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.NothingDue.selector, id));
            sched.release(id);
        }
        assertEq(token.balanceOf(bob), (exp1 + exp2) * p.amt);
        assertLe(token.balanceOf(bob), uint256(p.amt) * p.n);
        assertEq(token.balanceOf(address(sched)), (uint256(p.n) - exp1 - exp2) * p.amt);
    }

    /// @dev paid-to-recipient + refunded-to-sender + owed == escrowed, with or without a blocked recipient.
    function testFuzz_CancelConservation(
        uint128 amt,
        uint32 n,
        uint256 startOff,
        uint32 interval,
        uint256 releaseDt,
        uint256 cancelDt,
        bool doRelease,
        bool blockRecipient
    ) public {
        P memory p = _params(amt, n, startOff, interval);
        uint256 id = _create(alice, bob, p.amt, p.n, p.start, p.interval);
        uint256 total = uint256(p.amt) * p.n;
        uint256 aliceAfterCreate = token.balanceOf(alice);

        uint256 t1 = T0 + bound(releaseDt, 0, 400 * uint256(365 days));
        uint256 t2 = t1 + bound(cancelDt, 0, 400 * uint256(365 days));
        uint256 released;
        _warpTo(t1);
        if (doRelease && _expectedDue(p, t1, 0) > 0) {
            released = sched.release(id);
        }
        _warpTo(t2);
        if (blockRecipient) token.setBlocked(bob, true);

        uint256 remaining = total - released;
        if (remaining == 0) {
            vm.prank(alice);
            vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.NothingRemaining.selector, id));
            sched.cancel(id);
            return;
        }
        vm.prank(alice);
        sched.cancel(id);

        uint256 paidNow = token.balanceOf(bob) - (blockRecipient ? 0 : 0);
        uint256 refunded = token.balanceOf(alice) - aliceAfterCreate;
        uint256 owed = sched.getSchedule(id).owed;

        // total conservation
        assertEq(paidNow + refunded + owed, total, "paid + refunded + owed == escrowed");
        // refund is never more than the not-yet-due part
        uint256 dueNow = _expectedDue(p, t2, released / p.amt);
        assertEq(refunded, remaining - dueNow * p.amt);
        // earned funds are either paid or owed, never refunded
        assertEq(paidNow - released + owed, dueNow * p.amt);
        if (blockRecipient && dueNow > 0) assertEq(owed, dueNow * p.amt);
        // contract holds exactly the owed claim
        assertEq(token.balanceOf(address(sched)), owed);
        // never anything left to release
        assertEq(sched.releasableAmount(id), 0);
    }

    function testFuzz_ClaimAfterReassignPaysFullOwed(uint128 amt, uint32 n, uint256 dt) public {
        P memory p = _params(amt, n, 0, 1 hours);
        p.start = uint48(T0 + 1);
        uint256 id = _create(alice, bob, p.amt, p.n, p.start, p.interval);
        _warpTo(T0 + 1 + bound(dt, 0, 2000 hours));
        token.setBlocked(bob, true);
        vm.prank(alice);
        sched.cancel(id);
        uint256 owed = sched.getSchedule(id).owed;
        vm.prank(bob);
        if (owed == 0) {
            vm.expectRevert(abi.encodeWithSelector(PaymentScheduler.ScheduleCancelled.selector, id));
            sched.reassignRecipient(id, carol);
            return;
        }
        sched.reassignRecipient(id, carol);
        sched.claim(id);
        assertEq(token.balanceOf(carol), owed);
        assertEq(token.balanceOf(address(sched)), 0);
    }
}
