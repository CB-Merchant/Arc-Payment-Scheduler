// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PaymentScheduler} from "../PaymentScheduler.sol";
import {BlockableERC20} from "../test-helpers/MockERC20.sol";

abstract contract PaymentSchedulerTestBase is Test {
    PaymentScheduler internal sched;
    BlockableERC20 internal token;

    address internal alice = makeAddr("alice"); // sender
    address internal bob = makeAddr("bob"); // recipient
    address internal carol = makeAddr("carol");
    address internal keeper = makeAddr("keeper");

    uint256 internal constant T0 = 1_700_000_000;
    uint128 internal constant AMT = 10e6;
    uint32 internal constant N = 5;
    uint32 internal constant DAY = 1 days;
    uint48 internal START; // T0 + 1 day

    function setUp() public virtual {
        vm.warp(T0);
        START = uint48(T0 + 1 days);
        token = new BlockableERC20();
        sched = new PaymentScheduler(address(token));
        token.mint(alice, 1_000_000e6);
        vm.prank(alice);
        token.approve(address(sched), type(uint256).max);
    }

    /// @dev Creates a standard recurring schedule (AMT x N, daily, starting START) from alice to bob.
    function _createStd() internal returns (uint256 id) {
        vm.prank(alice);
        id = sched.createSchedule(bob, AMT, N, START, DAY, "std");
    }

    function _createOneTime() internal returns (uint256 id) {
        vm.prank(alice);
        id = sched.createSchedule(bob, AMT, 1, START, 0, "once");
    }

    function _create(address who, address rcpt, uint128 amt, uint32 n, uint48 start, uint32 interval)
        internal
        returns (uint256 id)
    {
        vm.prank(who);
        id = sched.createSchedule(rcpt, amt, n, start, interval, "");
    }

    function _warpTo(uint256 ts) internal {
        vm.warp(ts);
    }
}
