// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title PaymentScheduler
/// @notice Immutable, upfront-funded USDC schedules with permissionless catch-up payments.
/// @dev Intended for the ERC-20 view of USDC on Arc Testnet (6 decimals). The deployer
/// must supply the correct token address. A transaction must trigger release; time alone
/// does not execute payments. There is no owner, upgrade, pause, fee, or rescue mechanism.
/// Direct token donations cannot be recovered. USDC issuer restrictions still apply.
contract PaymentScheduler is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Maximum installments in a schedule.
    uint32 public constant MAX_INSTALLMENTS = 1000;
    /// @notice Minimum recurring interval, in seconds.
    uint32 public constant MIN_INTERVAL = 1 hours;
    /// @notice Maximum recurring interval, in seconds.
    uint32 public constant MAX_INTERVAL = 365 days;
    /// @notice Maximum memo length in bytes, not characters.
    uint256 public constant MAX_MEMO_BYTES = 64;

    /// @notice An escrowed payment plan.
    /// @dev On cancellation, paid is set to installments to close installment accounting.
    /// Unpaid earned funds remain in owed. Consult Cancelled and claim events for payouts.
    struct Schedule {
        address sender;
        address recipient;
        uint128 amount;
        uint32 installments;
        uint32 paid;
        uint48 startTime;
        uint32 interval;
        bool cancelled;
        uint144 owed;
        string memo;
    }

    /// @notice The fixed ERC-20 token used for every schedule.
    IERC20 public immutable token;
    /// @notice ID assigned to the next schedule; IDs start at one.
    uint256 public nextId = 1;

    mapping(uint256 => Schedule) private _schedules;
    mapping(address => uint256[]) private _bySender;
    mapping(address => uint256[]) private _byRecipient;

    /// @notice The constructor token address is zero.
    error InvalidToken();
    /// @notice The recipient is disallowed for the requested operation.
    error InvalidRecipient(address recipient);
    /// @notice An installment amount must be positive.
    error InvalidAmount();
    /// @notice The installment count is outside the supported range.
    error InvalidInstallments(uint32 installments);
    /// @notice The first installment cannot start in the past.
    error StartTimeInPast(uint48 supplied, uint256 current);
    /// @notice The interval does not match the schedule type or allowed range.
    error InvalidInterval(uint32 interval, uint32 installments);
    /// @notice The memo exceeds the byte limit.
    error MemoTooLong(uint256 actual, uint256 maximum);
    /// @notice The deposit did not increase the balance by exactly the escrow total.
    /// @dev actual is zero if the balance decreased rather than increased.
    error IncorrectDeposit(uint256 expected, uint256 actual);
    /// @notice No schedule exists at this ID.
    error UnknownSchedule(uint256 id);
    /// @notice A cancelled schedule cannot be released or changed without an owed claim.
    error ScheduleCancelled(uint256 id);
    /// @notice No unpaid installment is due yet.
    error NothingDue(uint256 id);
    /// @notice No installment or claim remains payable for this operation.
    error NothingRemaining(uint256 id);
    /// @notice Only the original sender may cancel.
    error NotSender(uint256 id, address caller);
    /// @notice Only the current recipient may reassign.
    error NotRecipient(uint256 id, address caller);

    /// @notice A new schedule was fully funded.
    event ScheduleCreated(
        uint256 indexed id,
        address indexed sender,
        address indexed recipient,
        uint128 amount,
        uint32 installments,
        uint48 startTime,
        uint32 interval,
        string memo
    );

    /// @notice All currently due installments were paid to the current recipient.
    event Released(
        uint256 indexed id,
        address indexed recipient,
        uint32 installmentsPaid,
        uint256 amountPaid,
        address caller
    );

    /// @notice The schedule closed; future installments were refunded and due funds paid or owed.
    /// @dev paidToRecipient reflects only the payout now; failed payouts remain in owed.
    event Cancelled(
        uint256 indexed id,
        address indexed sender,
        uint256 paidToRecipient,
        uint256 refundedToSender
    );

    /// @notice A failed cancellation payout remains escrowed for the current recipient.
    event ClaimRecorded(uint256 indexed id, address indexed recipient, uint256 amount);

    /// @notice Previously owed funds were paid to the current recipient.
    event Claimed(uint256 indexed id, address indexed recipient, uint256 amount, address caller);

    /// @notice The recipient changed for all unreleased installments and any owed claim.
    event RecipientChanged(
        uint256 indexed id,
        address indexed oldRecipient,
        address indexed newRecipient
    );

    /// @param tokenAddress ERC-20 USDC address for Arc Testnet, supplied by the app.
    constructor(address tokenAddress) {
        if (tokenAddress == address(0)) revert InvalidToken();
        token = IERC20(tokenAddress);
    }

    /// @notice Escrow the complete cost of a one-time or recurring payment plan.
    /// @dev Requires prior approval for amount * installments. Exact balance-delta
    /// checking rejects fee-on-transfer deposits. All state rolls back on failure.
    /// @param recipient Initial recipient; not zero, this contract, or the sender.
    /// @param amount Per-installment amount in USDC base units (6 decimals).
    /// @param installments Total count, between one and MAX_INSTALLMENTS inclusive.
    /// @param startTime First due timestamp, at or after the current timestamp.
    /// @param interval Zero for one installment; otherwise MIN_INTERVAL..MAX_INTERVAL.
    /// @param memo Public onchain memo, at most MAX_MEMO_BYTES bytes.
    /// @return id Newly allocated schedule ID.
    function createSchedule(
        address recipient,
        uint128 amount,
        uint32 installments,
        uint48 startTime,
        uint32 interval,
        string calldata memo
    ) external nonReentrant returns (uint256 id) {
        if (recipient == address(0) || recipient == address(this) || recipient == msg.sender) {
            revert InvalidRecipient(recipient);
        }
        if (amount == 0) revert InvalidAmount();
        if (installments == 0 || installments > MAX_INSTALLMENTS) revert InvalidInstallments(installments);
        if (uint256(startTime) < block.timestamp) revert StartTimeInPast(startTime, block.timestamp);
        if (installments == 1) {
            if (interval != 0) revert InvalidInterval(interval, installments);
        } else if (interval < MIN_INTERVAL || interval > MAX_INTERVAL) {
            revert InvalidInterval(interval, installments);
        }
        if (bytes(memo).length > MAX_MEMO_BYTES) revert MemoTooLong(bytes(memo).length, MAX_MEMO_BYTES);

        uint256 total = uint256(amount) * uint256(installments);
        uint256 balanceBefore = token.balanceOf(address(this));

        id = nextId;
        nextId = id + 1;
        Schedule storage schedule = _schedules[id];
        schedule.sender = msg.sender;
        schedule.recipient = recipient;
        schedule.amount = amount;
        schedule.installments = installments;
        schedule.startTime = startTime;
        schedule.interval = interval;
        schedule.memo = memo;
        _bySender[msg.sender].push(id);
        _byRecipient[recipient].push(id);

        _emitScheduleCreated(id, schedule);
        token.safeTransferFrom(msg.sender, address(this), total);
        uint256 balanceAfter = token.balanceOf(address(this));
        if (balanceAfter < balanceBefore || balanceAfter - balanceBefore != total) {
            revert IncorrectDeposit(total, balanceAfter < balanceBefore ? 0 : balanceAfter - balanceBefore);
        }
    }

    /// @notice Pay all currently due, unreleased installments in one token transfer.
    /// @dev Anyone may trigger payment, but funds only go to the current recipient.
    /// A failed transfer reverts the paid update as well. Due computation is O(1).
    /// @param id Schedule ID.
    /// @return amountPaid Total USDC base units transferred.
    function release(uint256 id) external nonReentrant returns (uint256 amountPaid) {
        Schedule storage schedule = _requireSchedule(id);
        if (schedule.cancelled) revert ScheduleCancelled(id);
        uint32 due = _dueInstallments(schedule);
        if (due == 0) revert NothingDue(id);

        amountPaid = uint256(due) * uint256(schedule.amount);
        schedule.paid += due;
        emit Released(id, schedule.recipient, due, amountPaid, msg.sender);
        token.safeTransfer(schedule.recipient, amountPaid);
    }

    /// @notice Close a schedule, settle installments already due, and refund the rest.
    /// @dev Only the sender may cancel. A failed recipient payout remains owed;
    /// only future installments are refunded. A failed sender refund reverts the entire
    /// transaction, including any successful recipient payout and all state changes.
    /// Zero-value transfers are skipped. Fully paid schedules cannot be cancelled.
    /// @param id Schedule ID.
    function cancel(uint256 id) external nonReentrant {
        Schedule storage schedule = _requireSchedule(id);
        if (msg.sender != schedule.sender) revert NotSender(id, msg.sender);
        if (schedule.cancelled) revert ScheduleCancelled(id);
        uint32 remaining = schedule.installments - schedule.paid;
        if (remaining == 0) revert NothingRemaining(id);
        uint32 due = _dueInstallments(schedule);
        uint256 paidToRecipient = uint256(due) * uint256(schedule.amount);
        uint256 refundedToSender = uint256(remaining - due) * uint256(schedule.amount);

        schedule.cancelled = true;
        schedule.paid = schedule.installments;

        if (paidToRecipient != 0) {
            bool success = token.trySafeTransfer(schedule.recipient, paidToRecipient);
            if (!success) {
                // amount is uint128 and due <= 1000, so the product fits uint144.
                schedule.owed = uint144(paidToRecipient);
                emit ClaimRecorded(id, schedule.recipient, paidToRecipient);
                paidToRecipient = 0;
            }
        }
        emit Cancelled(id, schedule.sender, paidToRecipient, refundedToSender);
        if (refundedToSender != 0) {
            token.safeTransfer(schedule.sender, refundedToSender);
        }
    }

    /// @notice Pay a recorded cancellation claim to the current recipient.
    /// @dev Anyone may call. A failed transfer reverts the owed update.
    /// @param id Schedule ID.
    /// @return amountPaid Total USDC base units transferred.
    function claim(uint256 id) external nonReentrant returns (uint256 amountPaid) {
        Schedule storage schedule = _requireSchedule(id);
        amountPaid = uint256(schedule.owed);
        if (amountPaid == 0) revert NothingRemaining(id);
        schedule.owed = 0;
        emit Claimed(id, schedule.recipient, amountPaid, msg.sender);
        token.safeTransfer(schedule.recipient, amountPaid);
    }

    /// @notice Redirect every unreleased installment or owed claim to another recipient.
    /// @dev Only the current recipient may call, including after cancellation if owed > 0.
    /// Reassignment to the original sender is allowed. Recipient index entries are
    /// append-only and may become stale or repeat if an address becomes recipient again.
    /// @param id Schedule ID.
    /// @param newRecipient New address; not zero, this contract, or the current recipient.
    function reassignRecipient(uint256 id, address newRecipient) external nonReentrant {
        Schedule storage schedule = _requireSchedule(id);
        if (msg.sender != schedule.recipient) revert NotRecipient(id, msg.sender);
        if (schedule.cancelled && schedule.owed == 0) revert ScheduleCancelled(id);
        if (schedule.paid == schedule.installments && schedule.owed == 0) revert NothingRemaining(id);
        if (
            newRecipient == address(0) || newRecipient == address(this)
                || newRecipient == schedule.recipient
        ) revert InvalidRecipient(newRecipient);

        address oldRecipient = schedule.recipient;
        schedule.recipient = newRecipient;
        _byRecipient[newRecipient].push(id);
        emit RecipientChanged(id, oldRecipient, newRecipient);
    }

    /// @notice Return the complete stored schedule, including owed funds and its memo.
    /// @param id Schedule ID; an unknown ID reverts.
    /// @return schedule Stored schedule data.
    function getSchedule(uint256 id) external view returns (Schedule memory schedule) {
        return _requireSchedule(id);
    }

    /// @notice Return the amount currently payable through release.
    /// @param id Schedule ID; an unknown ID reverts.
    /// @return amount USDC base units due; zero for cancelled or completed schedules.
    function releasableAmount(uint256 id) external view returns (uint256 amount) {
        Schedule storage schedule = _requireSchedule(id);
        return uint256(_dueInstallments(schedule)) * uint256(schedule.amount);
    }

    /// @notice Paginate the append-only IDs created by a sender, including closed schedules.
    /// @param sender Sender address to query.
    /// @param offset Zero-based index into the list.
    /// @param limit Maximum number of IDs to return.
    /// @return ids IDs in creation order; empty for zero limit or an exhausted offset.
    function getSchedulesBySender(address sender, uint256 offset, uint256 limit)
        external
        view
        returns (uint256[] memory ids)
    {
        return _page(_bySender[sender], offset, limit);
    }

    /// @notice Paginate IDs historically assigned to a recipient, including closed schedules.
    /// @dev Entries may be stale or duplicated. Re-check each schedule's current recipient
    /// and derived status; this view deliberately does not filter or deduplicate history.
    /// @param recipient Recipient address to query.
    /// @param offset Zero-based index into the historical list.
    /// @param limit Maximum number of IDs to return.
    /// @return ids Historical IDs; empty for zero limit or an exhausted offset.
    function getSchedulesByRecipient(address recipient, uint256 offset, uint256 limit)
        external
        view
        returns (uint256[] memory ids)
    {
        return _page(_byRecipient[recipient], offset, limit);
    }

    /// @notice Total schedules ever created, including cancelled and completed schedules.
    /// @return count Number of created schedules.
    function scheduleCount() external view returns (uint256 count) {
        return nextId - 1;
    }

    /// @dev Existence is identified by the sender, which can never be zero on creation.
    function _requireSchedule(uint256 id) private view returns (Schedule storage schedule) {
        schedule = _schedules[id];
        if (schedule.sender == address(0)) revert UnknownSchedule(id);
    }

    /// @dev Count due but unsettled installments without iterating or narrowing timestamps.
    function _dueInstallments(Schedule storage schedule) private view returns (uint32) {
        if (
            schedule.cancelled || schedule.paid == schedule.installments
                || block.timestamp < uint256(schedule.startTime)
        ) return 0;
        if (schedule.installments == 1) return schedule.installments - schedule.paid;

        uint256 dueTotal = 1 + (block.timestamp - uint256(schedule.startTime)) / uint256(schedule.interval);
        if (dueTotal > uint256(schedule.installments)) dueTotal = uint256(schedule.installments);
        return uint32(dueTotal) - schedule.paid;
    }

    /// @dev Bound allocation and iteration by available entries before adding offset.
    function _page(uint256[] storage entries, uint256 offset, uint256 limit)
        private
        view
        returns (uint256[] memory ids)
    {
        if (offset >= entries.length || limit == 0) return new uint256[](0);
        uint256 count = entries.length - offset;
        if (limit < count) count = limit;
        ids = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            ids[i] = entries[offset + i];
        }
    }

    /// @dev Emit from stored data to keep creation's parameter stack small.
    function _emitScheduleCreated(uint256 id, Schedule storage schedule) private {
        emit ScheduleCreated(
            id,
            schedule.sender,
            schedule.recipient,
            schedule.amount,
            schedule.installments,
            schedule.startTime,
            schedule.interval,
            schedule.memo
        );
    }
}
