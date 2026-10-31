import { isAddress, zeroAddress, type Address } from 'viem'

/**
 * Which Arc network the app talks to. Chosen at build time:
 *   VITE_NETWORK=mainnet            -> Arc mainnet (real funds)
 *   VITE_SCHEDULER_ADDRESS=0x...    -> the PaymentScheduler address on that network
 * With no variables set, the app uses Arc Testnet and the testnet deployment.
 */
const TESTNET_CONTRACT: Address = '0x50bb53d67b0d789e899485751131daf155c3fda9'

export const IS_MAINNET = import.meta.env.VITE_NETWORK === 'mainnet'

export const CHAIN_ID: 5042 | 5042002 = IS_MAINNET ? 5042 : 5042002
export const CHAIN_NAME = IS_MAINNET ? 'Arc' : 'Arc Testnet'

const override = import.meta.env.VITE_SCHEDULER_ADDRESS
const configured: Address | undefined = override && isAddress(override) ? override : IS_MAINNET ? undefined : TESTNET_CONTRACT

/** True once a PaymentScheduler address is known for the selected network. */
export const IS_DEPLOYED = configured !== undefined
export const SCHEDULER_ADDRESS: Address = configured ?? zeroAddress
