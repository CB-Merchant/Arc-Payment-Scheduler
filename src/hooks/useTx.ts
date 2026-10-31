import { useCallback, useState } from 'react'
import { useAccount, usePublicClient, useSwitchChain, useWriteContract } from 'wagmi'
import type { Abi, Address } from 'viem'
import { toast } from 'sonner'
import { CHAIN_ID, parseOnchainError } from '@/lib/schedule'

export type TxPhase = 'idle' | 'wallet' | 'confirming'

type TxRequest = {
  address: Address
  abi: Abi
  functionName: string
  args: readonly unknown[]
}

/** Sends one contract write on Arc Testnet, switching chain first and waiting for the real receipt. */
export function useTx() {
  const { chainId } = useAccount()
  const { switchChainAsync } = useSwitchChain()
  const { writeContractAsync } = useWriteContract()
  const publicClient = usePublicClient({ chainId: CHAIN_ID })
  const [phase, setPhase] = useState<TxPhase>('idle')
  const [lastHash, setLastHash] = useState<`0x${string}` | undefined>()

  const run = useCallback(
    async (request: TxRequest): Promise<boolean> => {
      try {
        setPhase('wallet')
        if (chainId !== CHAIN_ID) await switchChainAsync({ chainId: CHAIN_ID })
        const hash = await writeContractAsync({ ...request, chainId: CHAIN_ID })
        setLastHash(hash)
        setPhase('confirming')
        const receipt = await publicClient?.waitForTransactionReceipt({ hash })
        if (receipt && receipt.status !== 'success') throw new Error('reverted')
        return true
      } catch (error) {
        const message = parseOnchainError(error)
        if (message) toast.error(message)
        return false
      } finally {
        setPhase('idle')
      }
    },
    [chainId, publicClient, switchChainAsync, writeContractAsync],
  )

  return { run, phase, busy: phase !== 'idle', lastHash }
}
