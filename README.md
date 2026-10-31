# Payment Scheduler

Schedule USDC payments to another wallet on Arc Testnet. You lock the money upfront, and it is paid to the recipient on the date you choose, either once or on a recurring schedule. You can cancel any time, and the recipient can point future payments to a new address.

Built with [Arc Studio](https://studio.arc.io)

## What you can do

- Schedule a one-time or recurring USDC payment, with an optional memo.
- See what you are sending and what is coming to you.
- Release a payment once it is due (anyone can do this, the money only ever goes to the recipient).
- Cancel a schedule: payments already due go to the recipient, the rest returns to you.
- As a recipient, change the address that future payments go to.

## Tech stack

- Solidity (Foundry, OpenZeppelin) for the payment contract
- React, TypeScript, Vite, Tailwind CSS
- wagmi, viem, ConnectKit for wallet connection

## Development

Prerequisites: [Bun](https://bun.sh) and [Foundry](https://getfoundry.sh).

Install and run:

```bash
bun install
bun run dev
```

Build and test the contract:

```bash
bun run contracts:build
bun run contracts:test
```

Check the app code:

```bash
bun run check
```

### Environment variables

Both are optional build-time settings. With neither set, the app targets Arc Testnet.

- `VITE_NETWORK`: set to `mainnet` to target Arc mainnet.
- `VITE_SCHEDULER_ADDRESS`: the deployed PaymentScheduler contract address on the selected network. Required for mainnet.

### Mainnet

Mainnet uses real funds and the contract cannot be changed once deployed. See [docs/mainnet-deploy.md](docs/mainnet-deploy.md) for the checklist and deploy steps.
