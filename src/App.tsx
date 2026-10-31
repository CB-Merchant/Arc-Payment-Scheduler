import { useEffect, useMemo, useState } from 'react'
import { ConnectKitButton } from 'connectkit'
import { useAccount } from 'wagmi'
import { Plus, Wallet } from 'lucide-react'
import { TokenUSDC } from '@web3icons/react'
import { NewScheduleSheet } from '@/components/NewScheduleSheet'
import { ScheduleCard } from '@/components/ScheduleCard'
import { useSchedules } from '@/hooks/useSchedules'
import { PAYMENT_SCHEDULER_ADDRESS } from '@/contracts/paymentScheduler'
import { buildAddressExplorerUrl } from '@/onchain-facts'
import { CHAIN_ID, fmtUsdc, shortAddress, type Schedule } from '@/lib/schedule'

type Tab = 'sending' | 'receiving'

function remainingValue(list: Schedule[]): bigint {
  return list.reduce((sum, s) => {
    const open = s.cancelled ? 0n : BigInt(s.installments - s.paid) * s.amount
    return sum + open + s.owed
  }, 0n)
}

export default function App() {
  const { address, isConnected } = useAccount()
  const { sending, receiving, isLoading, refetch } = useSchedules(address)
  const [tab, setTab] = useState<Tab>('sending')
  const [sheetOpen, setSheetOpen] = useState(false)
  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000))

  useEffect(() => {
    const timer = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 15_000)
    return () => clearInterval(timer)
  }, [])

  const outgoing = useMemo(() => remainingValue(sending), [sending])
  const incoming = useMemo(() => remainingValue(receiving), [receiving])
  const list = tab === 'sending' ? sending : receiving

  return (
    <div className="min-h-dvh">
      <header className="mx-auto flex max-w-2xl items-center justify-between px-5 pb-2 pt-5">
        <div className="flex items-center gap-2.5">
          <img src="/logo.svg" alt="" width={36} height={36} className="size-9 rounded-xl" />
          <span className="display text-lg font-bold" style={{ color: 'var(--ink)' }}>
            Payment Scheduler
          </span>
        </div>
        <ConnectKitButton />
      </header>

      <main className="mx-auto max-w-2xl space-y-5 px-5 pb-28 pt-3">
        <section className="glass-card rounded-3xl p-6">
          <div className="flex items-center gap-1.5">
            <TokenUSDC variant="branded" size={18} />
            <span className="text-xs font-semibold" style={{ color: 'var(--muted)' }}>
              Locked in your outgoing schedules
            </span>
          </div>
          <div className="mt-3 flex items-baseline gap-1.5">
            <span className="display text-5xl font-bold tabular-nums" style={{ color: 'var(--ink)' }}>
              {isConnected ? fmtUsdc(outgoing) : '0.00'}
            </span>
            <span className="text-lg font-medium" style={{ color: 'var(--subtle)' }}>
              USDC
            </span>
          </div>
          <p className="mt-1.5 text-xs tabular-nums" style={{ color: 'var(--muted)' }}>
            {isConnected
              ? `${fmtUsdc(incoming)} USDC still to arrive in your wallet`
              : 'Connect a wallet to see your schedules on Arc Testnet'}
          </p>
          <button
            className="btn-primary mt-5 flex w-full items-center justify-center gap-2"
            onClick={() => setSheetOpen(true)}
            disabled={!isConnected}
          >
            <Plus className="size-4" /> New scheduled payment
          </button>
          {!isConnected && (
            <p className="mt-3 text-center text-xs" style={{ color: 'var(--subtle)' }}>
              Use the connect button above. Get test USDC from the Arc Studio sidebar.
            </p>
          )}
        </section>

        {isConnected && (
          <>
            <div className="grid grid-cols-2 gap-1 rounded-2xl p-1" style={{ background: 'var(--surface-muted)' }} role="tablist">
              {(['sending', 'receiving'] as const).map((t) => (
                <button
                  key={t}
                  role="tab"
                  aria-selected={tab === t}
                  onClick={() => setTab(t)}
                  className="min-h-11 rounded-xl text-sm font-semibold"
                  style={{
                    background: tab === t ? '#fff' : 'transparent',
                    color: tab === t ? 'var(--ink)' : 'var(--muted)',
                    boxShadow: tab === t ? '0 1px 4px rgba(18,45,69,0.12)' : 'none',
                  }}
                >
                  {t === 'sending' ? `Sending (${sending.length})` : `Receiving (${receiving.length})`}
                </button>
              ))}
            </div>

            {isLoading && list.length === 0 ? (
              <div className="space-y-3" aria-busy="true">
                {[0, 1].map((i) => (
                  <div key={i} className="glass-card h-40 animate-pulse rounded-3xl" />
                ))}
              </div>
            ) : list.length === 0 ? (
              <div className="glass-card rounded-3xl p-8 text-center">
                <Wallet className="mx-auto size-8" style={{ color: 'var(--subtle)' }} />
                <p className="mt-3 text-sm font-semibold" style={{ color: 'var(--ink)' }}>
                  {tab === 'sending' ? 'No scheduled payments yet' : 'Nothing scheduled for you yet'}
                </p>
                <p className="mx-auto mt-1 max-w-xs text-xs text-pretty" style={{ color: 'var(--muted)' }}>
                  {tab === 'sending'
                    ? 'Lock USDC now and it is paid out to the recipient on the date you choose.'
                    : 'When someone schedules a payment to your address, it shows up here.'}
                </p>
              </div>
            ) : (
              <div className="space-y-3">
                {list.map((s) => (
                  <ScheduleCard key={s.id.toString()} schedule={s} role={tab} now={now} onChanged={() => void refetch()} />
                ))}
              </div>
            )}
          </>
        )}

        <p className="pt-2 text-center text-xs" style={{ color: 'var(--subtle)' }}>
          Contract{' '}
          <a
            className="mono underline"
            href={buildAddressExplorerUrl(CHAIN_ID, PAYMENT_SCHEDULER_ADDRESS)}
            target="_blank"
            rel="noreferrer"
          >
            {shortAddress(PAYMENT_SCHEDULER_ADDRESS)}
          </a>{' '}
          on Arc Testnet. Anyone can release a payment once it is due.
        </p>
      </main>

      <NewScheduleSheet
        open={sheetOpen}
        now={now}
        onClose={() => setSheetOpen(false)}
        onCreated={() => {
          setTab('sending')
          void refetch()
        }}
      />
    </div>
  )
}
