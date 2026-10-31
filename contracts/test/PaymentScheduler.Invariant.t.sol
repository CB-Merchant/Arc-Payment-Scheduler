// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PaymentScheduler} from "../PaymentScheduler.sol";
import {BlockableERC20} from "../test-helpers/MockERC20.sol";

/// @dev Drives bounded random action sequences against the scheduler.
contract SchedulerHandler is Test {
    PaymentScheduler public sched;
    BlockableERC20 public token;

    address[] public senders;
    address[] public recipients;

    bool public releasedEarly;
    uint256 public successfulCreates;
    uint256 public successfulReleases;
    uint256 public successfulCancels;
    uint256 public successfulClaims;
    uint256 public successfulReassigns;

    constructor(PaymentScheduler _sched, BlockableERC20 _token) {
        sched = _sched;
        token = _token;
        senders.push(makeAddr("hSender0"));
        senders.push(makeAddr("hSender1"));
        recipients.push(makeAddr("hRecipient0"));
        recipients.push(makeAddr("hRecipient1"));
        recipients.push(makeAddr("hRecipient2"));
        for (uint256 i; i < senders.length; i++) {
            token.mint(senders[i], 1e30);
            vm.prank(senders[i]);
            token.approve(address(sched), type(uint256).max);
        }
    }

    function _id(uint256 seed) internal view returns (uint256) {
        uint256 c = sched.scheduleCount();
        if (c == 0) return 0;
        return bound(seed, 1, c);
    }

    function create(uint256 seed, uint128 amt, uint32 n, uint256 startOff, uint32 interval) external {
        amt = uint128(bound(amt, 1, 1e12));
        n = uint32(bound(n, 1, 50));
        uint48 start = uint48(block.timestamp + bound(startOff, 0, 30 days));
        interval = n == 1 ? 0 : uint32(bound(interval, 1 hours, 10 days));
        address s = senders[seed % senders.length];
        address r = recipients[(seed >> 8) % recipients.length];
        vm.prank(s);
        try sched.createSchedule(r, amt, n, start, interval, "h") {
            successfulCreates++;
        } catch {}
    }

    function warp(uint256 dt) external {
        vm.warp(block.timestamp + bound(dt, 0, 20 days));
    }

    function release(uint256 seed) external {
        uint256 id = _id(seed);
        if (id == 0) return;
        PaymentScheduler.Schedule memory s = sched.getSchedule(id);
        try sched.release(id) {
            successfulReleases++;
            if (block.timestamp < s.startTime) releasedEarly = true;
        } catch {}
    }

    function cancel(uint256 seed) external {
        uint256 id = _id(seed);
        if (id == 0) return;
        PaymentScheduler.Schedule memory s = sched.getSchedule(id);
        vm.prank(s.sender);
        try sched.cancel(id) {
            successfulCancels++;
        } catch {}
    }

    function claim(uint256 seed) external {
        uint256 id = _id(seed);
        if (id == 0) return;
        try sched.claim(id) {
            successfulClaims++;
        } catch {}
    }

    function reassign(uint256 seed, uint256 target) external {
        uint256 id = _id(seed);
        if (id == 0) return;
        PaymentScheduler.Schedule memory s = sched.getSchedule(id);
        address to = target % 4 == 3 ? s.sender : recipients[target % recipients.length];
        vm.prank(s.recipient);
        try sched.reassignRecipient(id, to) {
            successfulReassigns++;
        } catch {}
    }

    function setBlocked(uint256 who, bool b) external {
        token.setBlocked(recipients[who % recipients.length], b);
    }
}

contract PaymentSchedulerInvariantTest is Test {
    PaymentScheduler internal sched;
    BlockableERC20 internal token;
    SchedulerHandler internal handler;

    function setUp() public {
        vm.warp(1_700_000_000);
        token = new BlockableERC20();
        sched = new PaymentScheduler(address(token));
        handler = new SchedulerHandler(sched, token);

        targetContract(address(handler));
        bytes4[] memory sels = new bytes4[](7);
        sels[0] = SchedulerHandler.create.selector;
        sels[1] = SchedulerHandler.warp.selector;
        sels[2] = SchedulerHandler.release.selector;
        sels[3] = SchedulerHandler.cancel.selector;
        sels[4] = SchedulerHandler.claim.selector;
        sels[5] = SchedulerHandler.reassign.selector;
        sels[6] = SchedulerHandler.setBlocked.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: sels}));
    }

    /// @dev Guards against a vacuous run: the handler must actually exercise the state machine.
    function afterInvariant() public view {
        assertGt(handler.successfulCreates(), 0, "no creates");
    }

    function _obligations() internal view returns (uint256 sum) {
        uint256 c = sched.scheduleCount();
        for (uint256 id = 1; id <= c; id++) {
            PaymentScheduler.Schedule memory s = sched.getSchedule(id);
            sum += uint256(s.installments - s.paid) * s.amount + s.owed;
        }
    }

    /// @dev S6: balance covers remaining installment obligations plus every owed claim.
    function invariant_BalanceCoversRemainingObligationsPlusOwed() public view {
        assertGe(token.balanceOf(address(sched)), _obligations());
    }

    /// @dev With no donations, escrow accounting is exact (nothing leaks, nothing is stuck).
    function invariant_BalanceEqualsObligationsExactly() public view {
        assertEq(token.balanceOf(address(sched)), _obligations());
    }

    /// @dev S4: no successful release ever happened before startTime.
    function invariant_NoReleaseBeforeStart() public view {
        assertFalse(handler.releasedEarly());
    }

    /// @dev Cancelled schedules are closed: paid == installments, nothing releasable.
    function invariant_CancelledSchedulesClosed() public view {
        uint256 c = sched.scheduleCount();
        for (uint256 id = 1; id <= c; id++) {
            PaymentScheduler.Schedule memory s = sched.getSchedule(id);
            assertLe(s.paid, s.installments);
            if (s.cancelled) {
                assertEq(s.paid, s.installments);
                assertEq(sched.releasableAmount(id), 0);
            } else {
                assertEq(s.owed, 0);
            }
        }
    }
}
