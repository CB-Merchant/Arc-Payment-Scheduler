import { useMemo } from 'react'
import { useReadContract, useReadContracts } from 'wagmi'
import type { Address } from 'viem'
import { PAYMENT_SCHEDULER_ABI, PAYMENT_SCHEDULER_ADDRESS } from '@/contracts/paymentScheduler'
import { CHAIN_ID, type Schedule } from '@/lib/schedule'

const PAGE = 100n
const POLL_MS = 15_000

const base = { address: PAYMENT_SCHEDULER_ADDRESS, abi: PAYMENT_SCHEDULER_ABI, chainId: CHAIN_ID } as const

export function useSchedules(account: Address | undefined) {
  const enabled = Boolean(account)

  const bySender = useReadContract({
    ...base,
    functionName: 'getSchedulesBySender',
    args: account ? [account, 0n, PAGE] : undefined,
    query: { enabled, refetchInterval: POLL_MS },
  })
  const byRecipient = useReadContract({
    ...base,
    functionName: 'getSchedulesByRecipient',
    args: account ? [account, 0n, PAGE] : undefined,
    query: { enabled, refetchInterval: POLL_MS },
  })

  const ids = useMemo(() => {
    const set = new Set<bigint>()
    for (const id of bySender.data ?? []) set.add(id)
    for (const id of byRecipient.data ?? []) set.add(id)
    return [...set].sort((a, b) => (a < b ? 1 : -1))
  }, [bySender.data, byRecipient.data])

  const details = useReadContracts({
    contracts: ids.map((id) => ({ ...base, functionName: 'getSchedule', args: [id] }) as const),
    query: { enabled: ids.length > 0, refetchInterval: POLL_MS },
  })

  const all = useMemo<Schedule[]>(() => {
    const out: Schedule[] = []
    ids.forEach((id, i) => {
      const entry = details.data?.[i]
      if (!entry || entry.status !== 'success') return
      const s = entry.result
      out.push({
        id,
        sender: s.sender,
        recipient: s.recipient,
        amount: s.amount,
        installments: s.installments,
        paid: s.paid,
        startTime: Number(s.startTime),
        interval: s.interval,
        cancelled: s.cancelled,
        owed: s.owed,
        memo: s.memo,
      })
    })
    return out
  }, [ids, details.data])

  const lower = account?.toLowerCase()
  const sending = useMemo(() => all.filter((s) => s.sender.toLowerCase() === lower), [all, lower])
  const receiving = useMemo(
    () =>
      all.filter(
        (s) => s.recipient.toLowerCase() === lower && (!s.cancelled || s.owed > 0n),
      ),
    [all, lower],
  )

  const isLoading = enabled && (bySender.isLoading || byRecipient.isLoading || (ids.length > 0 && details.isLoading))

  const refetch = async () => {
    await Promise.all([bySender.refetch(), byRecipient.refetch()])
    await details.refetch()
  }

  return { sending, receiving, isLoading, refetch }
}
