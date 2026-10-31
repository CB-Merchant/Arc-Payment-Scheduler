import { useState } from 'react'
import { isAddress } from 'viem'
import { toast } from 'sonner'
import { ArrowDownLeft, ArrowUpRight, ExternalLink, Loader2, Repeat } from 'lucide-react'
import { PAYMENT_SCHEDULER_ABI, PAYMENT_SCHEDULER_ADDRESS } from '@/contracts/paymentScheduler'
import { useTx } from '@/hooks/useTx'
import { buildTxExplorerUrl } from '@/onchain-facts'
import {
  CHAIN_ID,
  STATUS_LABEL,
  dueCount,
  fmtDate,
  fmtUsdc,
  intervalLabel,
  nextDueTime,
  relativeTime,
  shortAddress,
  statusOf,
  type Schedule,
  type ScheduleStatus,
} from '@/lib/schedule'

type Props = {
  schedule: Schedule
  role: 'sending' | 'receiving'
  now: number
  onChanged: () => void
}

const STATUS_COLOR: Record<ScheduleStatus, { fg: string; bg: string }> = {
  upcoming: { fg: 'var(--accent-hover)', bg: 'rgba(16,97,166,0.1)' },
  ready: { fg: 'var(--success)', bg: 'rgba(26,128,71,0.12)' },
  active: { fg: 'var(--accent-hover)', bg: 'rgba(16,97,166,0.1)' },
  completed: { fg: 'var(--muted)', bg: 'rgba(107,101,128,0.12)' },
  cancelled: { fg: 'var(--danger)', bg: 'rgba(186,43,76,0.1)' },
  claim: { fg: 'var(--warn)', bg: 'rgba(154,103,0,0.12)' },
}

export function ScheduleCard({ schedule: s, role, now, onChanged }: Props) {
  const tx = useTx()
  const [mode, setMode] = useState<'none' | 'cancel' | 'reassign'>('none')
  const [newRecipient, setNewRecipient] = useState('')

  const status = statusOf(s, now)
  const due = dueCount(s, now)
  const releasable = BigInt(due) * s.amount
  const remaining = s.installments - s.paid
  const total = BigInt(s.installments) * s.amount
  const paidAmount = BigInt(s.paid) * s.amount
  const next = nextDueTime(s)
  const progress = s.cancelled ? 100 : Math.round((s.paid / s.installments) * 100)
  const counterparty = role === 'sending' ? s.recipient : s.sender
  const canCancel = role === 'sending' && !s.cancelled && remaining > 0
  const canReassign = role === 'receiving' && (s.cancelled ? s.owed > 0n : remaining > 0)
  const canClaim = s.owed > 0n
  const futureRefund = BigInt(Math.max(0, remaining - due)) * s.amount
  const color = STATUS_COLOR[status]

  const send = async (functionName: 'release' | 'cancel' | 'claim', success: string) => {
    const ok = await tx.run({
      address: PAYMENT_SCHEDULER_ADDRESS,
      abi: PAYMENT_SCHEDULER_ABI,
      functionName,
      args: [s.id],
    })
    if (ok) {
      toast.success(success)
      setMode('none')
      onChanged()
    }
  }

  const reassign = async () => {
    if (!isAddress(newRecipient)) return
    const ok = await tx.run({
      address: PAYMENT_SCHEDULER_ADDRESS,
      abi: PAYMENT_SCHEDULER_ABI,
      functionName: 'reassignRecipient',
      args: [s.id, newRecipient],
    })
    if (ok) {
      toast.success('Recipient updated')
      setMode('none')
      setNewRecipient('')
      onChanged()
    }
  }

  const busyLabel = tx.phase === 'wallet' ? 'Confirm in wallet…' : 'Confirming…'

  return (
    <article className="glass-card rounded-3xl p-5">
      <div className="flex items-start justify-between gap-3">
        <div className="flex min-w-0 items-center gap-3">
          <div
            className="flex size-10 shrink-0 items-center justify-center rounded-xl"
            style={{ background: 'var(--surface-muted)' }}
          >
            {role === 'sending' ? (
              <ArrowUpRight className="size-5" style={{ color: 'var(--ink)' }} />
            ) : (
              <ArrowDownLeft className="size-5" style={{ color: 'var(--success)' }} />
            )}
          </div>
          <div className="min-w-0">
            <div className="truncate text-sm font-semibold" style={{ color: 'var(--ink)' }}>
              {s.memo || (role === 'sending' ? 'Scheduled payment' : 'Incoming payment')}
            </div>
            <div className="mono truncate text-xs" style={{ color: 'var(--subtle)' }}>
              {role === 'sending' ? 'To' : 'From'} {shortAddress(counterparty)} · #{s.id.toString()}
            </div>
          </div>
        </div>
        <span
          className="shrink-0 rounded-full px-2.5 py-1 text-[11px] font-semibold"
          style={{ color: color.fg, background: color.bg }}
        >
          {STATUS_LABEL[status]}
        </span>
      </div>

      <div className="mt-4 flex items-baseline gap-1.5">
        <span className="display text-3xl font-bold tabular-nums" style={{ color: 'var(--ink)' }}>
          {fmtUsdc(s.amount)}
        </span>
        <span className="text-sm font-medium" style={{ color: 'var(--subtle)' }}>
          USDC
        </span>
        {s.installments > 1 && (
          <span className="ml-1 inline-flex items-center gap-1 text-xs" style={{ color: 'var(--muted)' }}>
            <Repeat className="size-3" /> {intervalLabel(s.interval)} × {s.installments}
          </span>
        )}
      </div>

      <div className="mt-4 h-1.5 overflow-hidden rounded-full" style={{ background: 'var(--surface-muted)' }}>
        <div
          className="h-full rounded-full"
          style={{
            width: `${progress}%`,
            background: s.cancelled ? 'var(--danger)' : 'var(--accent)',
            transition: 'width 0.4s ease',
          }}
        />
      </div>
      <div className="mt-2 flex flex-wrap justify-between gap-x-4 gap-y-1 text-xs tabular-nums" style={{ color: 'var(--muted)' }}>
        <span>
          {fmtUsdc(paidAmount)} of {fmtUsdc(total)} paid
        </span>
        {next !== undefined ? (
          <span>
            {status === 'ready' ? 'Due ' : 'Next '}
            {fmtDate(next)} ({relativeTime(next, now)})
          </span>
        ) : (
          <span>{s.cancelled ? 'Closed' : 'All installments paid'}</span>
        )}
      </div>

      {canClaim && (
        <div className="mt-3 rounded-2xl p-3 text-xs" style={{ background: 'rgba(154,103,0,0.1)', color: 'var(--warn)' }}>
          {fmtUsdc(s.owed)} USDC is held for the recipient because the payout could not be delivered. The recipient can
          change the address, then anyone can claim it.
        </div>
      )}

      {mode === 'cancel' && (
        <div className="glass-inner mt-4 rounded-2xl p-4 text-sm" style={{ color: 'var(--ink-2)' }}>
          <p className="font-semibold" style={{ color: 'var(--ink)' }}>
            Cancel this schedule?
          </p>
          <ul className="mt-2 space-y-1 text-xs tabular-nums">
            <li>{fmtUsdc(releasable)} USDC already due goes to the recipient.</li>
            <li>{fmtUsdc(futureRefund)} USDC comes back to you.</li>
          </ul>
        </div>
      )}

      {mode === 'reassign' && (
        <div className="glass-inner mt-4 rounded-2xl p-4">
          <label className="text-xs font-semibold" style={{ color: 'var(--muted)' }} htmlFor={`re-${s.id}`}>
            New recipient address
          </label>
          <input
            id={`re-${s.id}`}
            className="field mono mt-2"
            placeholder="0x…"
            value={newRecipient}
            onChange={(e) => setNewRecipient(e.target.value.trim())}
            autoComplete="off"
            spellCheck={false}
          />
          {newRecipient.length > 0 && !isAddress(newRecipient) && (
            <p className="mt-2 text-xs" style={{ color: 'var(--danger)' }}>
              Enter a valid address.
            </p>
          )}
          <p className="mt-2 text-xs" style={{ color: 'var(--muted)' }}>
            All unpaid installments will go to this address.
          </p>
        </div>
      )}

      <div className="mt-4 flex flex-wrap gap-2">
        {mode === 'none' && (
          <>
            {due > 0 && !s.cancelled && (
              <button
                className="btn-primary px-4"
                disabled={tx.busy}
                onClick={() => void send('release', `Released ${fmtUsdc(releasable)} USDC`)}
              >
                {tx.busy ? busyLabel : `Release ${fmtUsdc(releasable)} USDC`}
              </button>
            )}
            {canClaim && (
              <button className="btn-primary px-4" disabled={tx.busy} onClick={() => void send('claim', 'Claim paid')}>
                {tx.busy ? busyLabel : `Claim ${fmtUsdc(s.owed)} USDC`}
              </button>
            )}
            {canReassign && (
              <button className="btn-ghost" disabled={tx.busy} onClick={() => setMode('reassign')}>
                Change recipient
              </button>
            )}
            {canCancel && (
              <button className="btn-ghost" disabled={tx.busy} onClick={() => setMode('cancel')}>
                Cancel
              </button>
            )}
          </>
        )}
        {mode === 'cancel' && (
          <>
            <button
              className="btn-primary px-4"
              style={{ background: 'var(--danger)' }}
              disabled={tx.busy}
              onClick={() => void send('cancel', 'Schedule cancelled')}
            >
              {tx.busy ? busyLabel : 'Confirm cancel'}
            </button>
            <button className="btn-ghost" disabled={tx.busy} onClick={() => setMode('none')}>
              Keep schedule
            </button>
          </>
        )}
        {mode === 'reassign' && (
          <>
            <button className="btn-primary px-4" disabled={tx.busy || !isAddress(newRecipient)} onClick={() => void reassign()}>
              {tx.busy ? busyLabel : 'Save recipient'}
            </button>
            <button className="btn-ghost" disabled={tx.busy} onClick={() => setMode('none')}>
              Back
            </button>
          </>
        )}
        {tx.busy && <Loader2 className="size-4 animate-spin self-center" style={{ color: 'var(--muted)' }} />}
        {tx.lastHash && tx.phase === 'idle' && (
          <a
            href={buildTxExplorerUrl(CHAIN_ID, tx.lastHash)}
            target="_blank"
            rel="noreferrer"
            className="ml-auto inline-flex items-center gap-1 self-center text-xs font-medium"
            style={{ color: 'var(--accent-hover)' }}
          >
            Last transaction <ExternalLink className="size-3" />
          </a>
        )}
      </div>
    </article>
  )
}
