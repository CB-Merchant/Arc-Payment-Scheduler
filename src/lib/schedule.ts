import type { Address } from 'viem'
import { Amount, usdcDecimalsFor } from '@/onchain-money'

export const CHAIN_ID = 5042002

export type Schedule = {
  id: bigint
  sender: Address
  recipient: Address
  amount: bigint
  installments: number
  paid: number
  startTime: number
  interval: number
  cancelled: boolean
  owed: bigint
  memo: string
}

export type ScheduleStatus = 'upcoming' | 'ready' | 'active' | 'completed' | 'cancelled' | 'claim'

export const DAY = 86_400

export const INTERVAL_PRESETS = [
  { label: 'Daily', seconds: DAY },
  { label: 'Weekly', seconds: 7 * DAY },
  { label: 'Every 2 weeks', seconds: 14 * DAY },
  { label: 'Every 30 days', seconds: 30 * DAY },
] as const

export function shortAddress(addr: string): string {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`
}

export function fmtUsdc(raw: bigint, fractionDigits = 2): string {
  const text = Amount.fromRaw(raw, usdcDecimalsFor(CHAIN_ID)).toString()
  const [whole, frac = ''] = text.split('.')
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ',')
  const trimmed = frac.padEnd(fractionDigits, '0').slice(0, Math.max(fractionDigits, frac.replace(/0+$/, '').length)).slice(0, 6)
  return trimmed.length > 0 ? `${grouped}.${trimmed}` : grouped
}

export function fmtDate(ts: number): string {
  return new Date(ts * 1000).toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  })
}

export function intervalLabel(seconds: number): string {
  const preset = INTERVAL_PRESETS.find((p) => p.seconds === seconds)
  if (preset) return preset.label.toLowerCase()
  if (seconds % DAY === 0) return `every ${seconds / DAY} days`
  if (seconds % 3600 === 0) return `every ${seconds / 3600} hours`
  return `every ${seconds}s`
}

export function relativeTime(ts: number, now: number): string {
  const diff = ts - now
  const abs = Math.abs(diff)
  const unit =
    abs >= DAY ? `${Math.floor(abs / DAY)}d` : abs >= 3600 ? `${Math.floor(abs / 3600)}h` : `${Math.max(1, Math.floor(abs / 60))}m`
  return diff >= 0 ? `in ${unit}` : `${unit} ago`
}

/** Installments that are due now and not yet paid. Mirrors the contract's math. */
export function dueCount(s: Schedule, now: number): number {
  if (s.cancelled || s.paid >= s.installments || now < s.startTime) return 0
  if (s.installments === 1) return 1 - s.paid
  const elapsed = Math.floor((now - s.startTime) / s.interval)
  const dueTotal = Math.min(s.installments, 1 + elapsed)
  return Math.max(0, dueTotal - s.paid)
}

export function nextDueTime(s: Schedule): number | undefined {
  if (s.cancelled || s.paid >= s.installments) return undefined
  return s.startTime + s.paid * s.interval
}

export function statusOf(s: Schedule, now: number): ScheduleStatus {
  if (s.cancelled) return s.owed > 0n ? 'claim' : 'cancelled'
  if (s.paid >= s.installments) return 'completed'
  if (dueCount(s, now) > 0) return 'ready'
  if (s.paid === 0) return 'upcoming'
  return 'active'
}

export const STATUS_LABEL: Record<ScheduleStatus, string> = {
  upcoming: 'Scheduled',
  ready: 'Ready to release',
  active: 'In progress',
  completed: 'Completed',
  cancelled: 'Cancelled',
  claim: 'Claim pending',
}

export function parseOnchainError(error: unknown): string | null {
  const err = error as { code?: number; shortMessage?: string; message?: string; name?: string } | null
  const message = `${err?.shortMessage ?? ''} ${err?.message ?? ''}`.toLowerCase()
  if (err?.code === 4001 || message.includes('user rejected') || message.includes('user denied')) return null
  if (message.includes('insufficient funds') || message.includes('exceeds balance') || message.includes('transfer amount exceeds'))
    return 'Insufficient balance. Add test USDC and try again.'
  if (err?.name === 'WaitForTransactionReceiptTimeoutError' || message.includes('timed out while waiting'))
    return 'Still waiting for confirmation. Check the transaction on the explorer, then refresh this page.'
  if (message.includes('nothingdue')) return 'Nothing is due yet.'
  if (message.includes('startTimeinpast'.toLowerCase())) return 'Start time must be in the future.'
  if (message.includes('notsender')) return 'Only the sender can cancel this schedule.'
  if (message.includes('notrecipient')) return 'Only the recipient can do this.'
  if (message.includes('reverted')) return 'The transaction was rejected by the contract. Check the details and try again.'
  if (message.includes('network') || message.includes('timeout')) return 'Network issue. Check your connection and retry.'
  return 'Something went wrong. Please try again.'
}
