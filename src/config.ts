/**
 * wagmi configuration
 * Built with Arc Studio — https://studio.arc.io
 */

import { http, fallback, createConfig } from 'wagmi'
import { mainnet } from 'wagmi/chains'
import { arcTestnet } from 'viem/chains'
import { injected } from 'wagmi/connectors'
import { registerChain } from './tracing'

// Pre-register chain RPC URLs so trace events show correct chain names immediately
const ARC_RPC_URLS = arcTestnet.rpcUrls.default.http
for (const url of ARC_RPC_URLS) registerChain(arcTestnet.id, url)

export const config = createConfig({
  chains: [arcTestnet, mainnet], // mainnet needed for ENS resolution
  connectors: [injected()],
  transports: {
    // Try each public Arc Testnet RPC in turn so one slow endpoint never stalls balances or receipts
    [arcTestnet.id]: fallback(ARC_RPC_URLS.map((url) => http(url, { timeout: 8_000, retryCount: 1 })), { retryCount: 2 }),
    [mainnet.id]: http(), // ENS resolution uses mainnet
  },
})
