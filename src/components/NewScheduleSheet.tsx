import { useMemo, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { erc20Abi, isAddress, type Address } from 'viem'
import { useAccount, useReadContract } from 'wagmi'
import { toast } from 'sonner'
import { ExternalLink, Loader2, X } from 'lucide-react'
import { PAYMENT_SCHEDULER_ABI, PAYMENT_SCHEDULER_ADDRESS } from '@/contracts/paymentScheduler'
import { useTx } from '@/hooks/useTx'
import { buildTxExplorerUrl, getUsdc } from '@/onchain-facts'
import { parseAmount } from '@/onchain-money'
import { CHAIN_ID, DAY, INTERVAL_PRESETS, fmtUsdc } from '@/lib/schedule'

const USDC = getUsdc(CHAIN_ID)
const MAX_INSTALLMENTS = 1000
const MAX_MEMO_BYTES = 64

function toLocalInput(date: Date): string {
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`
}

function defaultStart(): string {
  return toLocalInput(new Date(Date.now() + 10 * 60 * 1000))
}

type Props = {
  open: boolean
  onClose: () => void
  onCreated: () => void
  now: number
}

export function NewScheduleSheet({ open, onClose, onCreated, now }: Props) {
  const { address } = useAccount()
  const tx = useTx()

  const [recipient, setRecipient] = useState('')
  const [amount, setAmount] = useState('')
  const [recurring, setRecurring] = useState(false)
  const [count, setCount] = useState('3')
  const [intervalSeconds, setIntervalSeconds] = useState<number>(30 * DAY)
  const [start, setStart] = useState(defaultStart)
  const [memo, setMemo] = useState('')

  const usdcAddress = USDC?.address as Address | undefined

  const allowance = useReadContract({
    address: usdcAddress,
    abi: erc20Abi,
    functionName: 'allowance',
    args: address ? [address, PAYMENT_SCHEDULER_ADDRESS] : undefined,
    chainId: CHAIN_ID,
    query: { enabled: Boolean(address && usdcAddress && open) },
  })
  const balance = useReadContract({
    address: usdcAddress,
    abi: erc20Abi,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    chainId: CHAIN_ID,
    query: { enabled: Boolean(address && usdcAddress && open) },
  })

  const parsed = useMemo(() => {
    let perInstallment: bigint | undefined
    try {
      if (amount.trim() !== '') {
        const raw = parseAmount(CHAIN_ID, amount).raw
        if (raw > 0n) perInstallment = raw
      }
    } catch {
      perInstallment = undefined
    }
    const installments = recurring ? Number.parseInt(count, 10) : 1
    const validCount = Number.isInteger(installments) && installments >= 1 && installments <= MAX_INSTALLMENTS
    const startSeconds = Math.floor(new Date(start).getTime() / 1000)
    const startOk = Number.isFinite(startSeconds) && startSeconds > now + 120
    const memoBytes = new TextEncoder().encode(memo).length
    const total = perInstallment !== undefined && validCount ? perInstallment * BigInt(installments) : undefined
    return { perInstallment, installments, validCount, startSeconds, startOk, memoBytes, total }
  }, [amount, recurring, count, start, memo, now])

  const recipientOk = isAddress(recipient) && recipient.toLowerCase() !== address?.toLowerCase()
  const countOk = !recurring || (parsed.validCount && parsed.installments >= 2)
  const formOk = recipientOk && parsed.perInstallment !== undefined && countOk && parsed.startOk && parsed.memoBytes <= MAX_MEMO_BYTES
  const needsApproval = parsed.total !== undefined && (allowance.data ?? 0n) < parsed.total
  const insufficient = parsed.total !== undefined && balance.data !== undefined && balance.data < parsed.total

  const busyLabel = tx.phase === 'wallet' ? 'Confirm in wallet…' : 'Confirming…'

  const submit = async () => {
    if (!formOk || parsed.total === undefined || parsed.perInstallment === undefined || !usdcAddress) return
    if (needsApproval) {
      const ok = await tx.run({
        address: usdcAddress,
        abi: erc20Abi,
        functionName: 'approve',
        args: [PAYMENT_SCHEDULER_ADDRESS, parsed.total],
      })
      if (ok) {
        await allowance.refetch()
        toast.success('Approved. Now create the schedule.')
      }
      return
    }
    const ok = await tx.run({
      address: PAYMENT_SCHEDULER_ADDRESS,
      abi: PAYMENT_SCHEDULER_ABI,
      functionName: 'createSchedule',
      args: [
        recipient,
        parsed.perInstallment,
        parsed.installments,
        parsed.startSeconds,
        recurring ? intervalSeconds : 0,
        memo,
      ],
    })
    if (ok) {
      toast.success('Schedule created. Funds are locked until each payment is due.')
      setRecipient('')
      setAmount('')
      setMemo('')
      setRecurring(false)
      setCount('3')
      setStart(defaultStart())
      onCreated()
      onClose()
    }
  }

  const cta = !address
    ? 'Connect wallet first'
    : insufficient
      ? 'Insufficient USDC balance'
      : tx.busy
        ? busyLabel
        : needsApproval
          ? `Step 1 of 2: Approve ${parsed.total !== undefined ? fmtUsdc(parsed.total) : ''} USDC`
          : parsed.total !== undefined
            ? `Lock ${fmtUsdc(parsed.total)} USDC and schedule`
            : 'Schedule payment'

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          className="fixed inset-0 z-50 flex items-end justify-center sm:items-center"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          onClick={tx.busy ? undefined : onClose}
        >
          <div className="absolute inset-0 bg-black/25 backdrop-blur-sm" />
          <motion.section
            role="dialog"
            aria-modal="true"
            aria-label="New scheduled payment"
            className="relative max-h-[92dvh] w-full max-w-md overflow-y-auto rounded-t-3xl sm:rounded-3xl"
            style={{
              background: 'rgba(255,255,255,0.92)',
              backdropFilter: 'blur(40px) saturate(200%)',
              WebkitBackdropFilter: 'blur(40px) saturate(200%)',
            }}
            initial={{ y: '100%' }}
            animate={{ y: 0 }}
            exit={{ y: '100%' }}
            transition={{ type: 'spring', stiffness: 380, damping: 36 }}
            onClick={(e) => e.stopPropagation()}
          >
            <div
              className="h-1"
              style={{ background: 'linear-gradient(90deg,#85b1ed,#c8b6f0,#f2c6a0,#9fd6b0)' }}
            />
            <div className="px-5 pb-6 pt-4">
              <div className="mb-4 flex items-center justify-between">
                <h2 className="display text-xl font-bold" style={{ color: 'var(--ink)' }}>
                  New scheduled payment
                </h2>
                <button
                  aria-label="Close"
                  className="flex size-11 items-center justify-center rounded-full"
                  onClick={onClose}
                  disabled={tx.busy}
                >
                  <X className="size-5" />
                </button>
              </div>

              <div className="space-y-4">
                <div>
                  <label htmlFor="recipient" className="mb-1.5 block text-xs font-semibold" style={{ color: 'var(--muted)' }}>
                    Recipient address
                  </label>
                  <input
                    id="recipient"
                    className="field mono"
                    placeholder="0x…"
                    value={recipient}
                    onChange={(e) => setRecipient(e.target.value.trim())}
                    autoComplete="off"
                    spellCheck={false}
                  />
                  {recipient.length > 0 && !recipientOk && (
                    <p className="mt-1.5 text-xs" style={{ color: 'var(--danger)' }}>
                      {isAddress(recipient) ? 'You cannot schedule a payment to yourself.' : 'Enter a valid address.'}
                    </p>
                  )}
                </div>

                <div className="glass-inner rounded-2xl p-4">
                  <label htmlFor="amount" className="text-xs font-semibold" style={{ color: 'var(--muted)' }}>
                    {recurring ? 'Amount per payment' : 'Amount'}
                  </label>
                  <input
                    id="amount"
                    inputMode="decimal"
                    className="display w-full bg-transparent text-4xl font-bold tabular-nums outline-none placeholder:text-slate-300"
                    style={{ color: 'var(--ink)' }}
                    placeholder="0.00"
                    value={amount}
                    onChange={(e) => {
                      const v = e.target.value
                      if (v === '' || /^\d*\.?\d{0,6}$/.test(v)) setAmount(v)
                    }}
                  />
                  <div className="mt-1 flex items-center justify-between text-xs" style={{ color: 'var(--subtle)' }}>
                    <span>USDC</span>
                    <span className="tabular-nums">
                      {balance.data !== undefined ? `Balance: ${fmtUsdc(balance.data)}` : balance.isLoading ? 'Loading balance…' : 'Balance unavailable'}
                    </span>
                  </div>
                </div>

                <div className="grid grid-cols-2 gap-1 rounded-2xl p-1" style={{ background: 'var(--surface-muted)' }}>
                  {[false, true].map((isRecurring) => (
                    <button
                      key={String(isRecurring)}
                      type="button"
                      onClick={() => setRecurring(isRecurring)}
                      className="min-h-11 rounded-xl text-sm font-semibold"
                      style={{
                        background: recurring === isRecurring ? '#fff' : 'transparent',
                        color: recurring === isRecurring ? 'var(--ink)' : 'var(--muted)',
                        boxShadow: recurring === isRecurring ? '0 1px 4px rgba(18,45,69,0.12)' : 'none',
                      }}
                    >
                      {isRecurring ? 'Recurring' : 'One-time'}
                    </button>
                  ))}
                </div>

                {recurring && (
                  <div className="space-y-3">
                    <div>
                      <span className="mb-1.5 block text-xs font-semibold" style={{ color: 'var(--muted)' }}>
                        Repeats
                      </span>
                      <div className="flex flex-wrap gap-2">
                        {INTERVAL_PRESETS.map((p) => (
                          <button
                            key={p.seconds}
                            type="button"
                            onClick={() => setIntervalSeconds(p.seconds)}
                            className="min-h-11 rounded-full px-4 text-xs font-semibold"
                            style={{
                              background: intervalSeconds === p.seconds ? 'var(--accent)' : 'var(--surface-muted)',
                              color: intervalSeconds === p.seconds ? '#fff' : 'var(--ink)',
                            }}
                          >
                            {p.label}
                          </button>
                        ))}
                      </div>
                    </div>
                    <div>
                      <label htmlFor="count" className="mb-1.5 block text-xs font-semibold" style={{ color: 'var(--muted)' }}>
                        Number of payments (2 to {MAX_INSTALLMENTS})
                      </label>
                      <input
                        id="count"
                        inputMode="numeric"
                        className="field"
                        value={count}
                        onChange={(e) => /^\d{0,4}$/.test(e.target.value) && setCount(e.target.value)}
                      />
                      {!countOk && (
                        <p className="mt-1.5 text-xs" style={{ color: 'var(--danger)' }}>
                          Enter a number from 2 to {MAX_INSTALLMENTS}.
                        </p>
                      )}
                    </div>
                  </div>
                )}

                <div>
                  <label htmlFor="start" className="mb-1.5 block text-xs font-semibold" style={{ color: 'var(--muted)' }}>
                    {recurring ? 'First payment' : 'Pay on'}
                  </label>
                  <input
                    id="start"
                    type="datetime-local"
                    className="field"
                    value={start}
                    onChange={(e) => setStart(e.target.value)}
                  />
                  {!parsed.startOk && (
                    <p className="mt-1.5 text-xs" style={{ color: 'var(--danger)' }}>
                      Pick a time at least a few minutes from now.
                    </p>
                  )}
                </div>

                <div>
                  <label htmlFor="memo" className="mb-1.5 block text-xs font-semibold" style={{ color: 'var(--muted)' }}>
                    Memo (optional)
                  </label>
                  <input
                    id="memo"
                    className="field"
                    placeholder="Rent, invoice #42, allowance…"
                    value={memo}
                    onChange={(e) => setMemo(e.target.value)}
                  />
                  {parsed.memoBytes > MAX_MEMO_BYTES && (
                    <p className="mt-1.5 text-xs" style={{ color: 'var(--danger)' }}>
                      Keep the memo under {MAX_MEMO_BYTES} bytes.
                    </p>
                  )}
                </div>

                {parsed.total !== undefined && (
                  <div className="glass-inner space-y-1.5 rounded-2xl p-4 text-xs tabular-nums" style={{ color: 'var(--ink-2)' }}>
                    <div className="flex justify-between">
                      <span>Locked now</span>
                      <span className="font-semibold">{fmtUsdc(parsed.total)} USDC</span>
                    </div>
                    <div className="flex justify-between">
                      <span>Payments</span>
                      <span>{parsed.installments}</span>
                    </div>
                    <p style={{ color: 'var(--muted)' }}>
                      You can cancel any time. Payments already due go to the recipient and the rest returns to you.
                    </p>
                  </div>
                )}

                <button
                  className="btn-primary w-full"
                  disabled={!address || !formOk || insufficient || tx.busy}
                  onClick={() => void submit()}
                >
                  {tx.busy ? (
                    <span className="flex items-center justify-center gap-2">
                      <Loader2 className="size-4 animate-spin" /> {busyLabel}
                    </span>
                  ) : (
                    cta
                  )}
                </button>
                {tx.phase === 'confirming' && tx.lastHash && (
                  <a
                    href={buildTxExplorerUrl(CHAIN_ID, tx.lastHash)}
                    target="_blank"
                    rel="noreferrer"
                    className="flex items-center justify-center gap-1 text-xs font-medium"
                    style={{ color: 'var(--accent-hover)' }}
                  >
                    Track this transaction <ExternalLink className="size-3" />
                  </a>
                )}
              </div>
            </div>
          </motion.section>
        </motion.div>
      )}
    </AnimatePresence>
  )
}
