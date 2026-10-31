/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_NETWORK?: 'mainnet' | 'testnet'
  readonly VITE_SCHEDULER_ADDRESS?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
