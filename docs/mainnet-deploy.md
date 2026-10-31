# Deploying to Arc mainnet

A beginner-friendly walkthrough is in [mainnet-step-by-step.md](mainnet-step-by-step.md).

Mainnet uses real USDC and every transaction is irreversible. The contract is immutable (no owner, no upgrade, no pause), so the code you deploy is final. You deploy and operate it yourself, from your own wallet.

## Before you start

- [ ] Get an independent professional audit of `contracts/PaymentScheduler.sol`. The built-in security review is not a substitute.
- [ ] Run the test suite: `bun run contracts:test`.
- [ ] Read the design doc (`contracts/PaymentScheduler-design.md`), especially the sections on the USDC blocklist and on tokens sent directly to the contract (they cannot be recovered).
- [ ] Use a dedicated deployer wallet. On Arc, gas is paid in USDC, so it needs a little USDC.
- [ ] Double-check these values yourself against Circle's and Arc's official docs, not just this file:
  - Chain ID: 5042
  - RPC: https://rpc.mainnet.arc.io
  - Explorer: https://explorer.arc.io
  - USDC token address (the constructor argument): 0x3600000000000000000000000000000000000000

## 1. Get the code and build

```bash
git clone https://github.com/CB-Merchant/Arc-Payment-Scheduler.git
cd Arc-Payment-Scheduler
bun install
forge build
```

## 2. Deploy the contract

Keep your private key in an environment variable. Never paste it into a file, a chat, or a commit.

```bash
export PRIVATE_KEY=<your deployer key>

forge create contracts/PaymentScheduler.sol:PaymentScheduler \
  --rpc-url https://rpc.mainnet.arc.io \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --constructor-args 0x3600000000000000000000000000000000000000
```

Copy the "Deployed to" address from the output.

## 3. Verify the source on the explorer (recommended)

```bash
forge verify-contract <DEPLOYED_ADDRESS> contracts/PaymentScheduler.sol:PaymentScheduler \
  --chain-id 5042 \
  --verifier blockscout \
  --verifier-url https://explorer.arc.io/api/ \
  --constructor-args $(cast abi-encode "constructor(address)" 0x3600000000000000000000000000000000000000) \
  --watch
```

If the explorer rejects that verifier URL, check the current API address in the explorer's documentation.

## 4. Check it on-chain before using it

- Open the address on https://explorer.arc.io and confirm the code is verified.
- Read `token()` and confirm it returns the USDC address above.
- Do a small test first: create a schedule with a tiny amount, release it, and cancel another.

## 5. Build the app for mainnet

```bash
VITE_NETWORK=mainnet VITE_SCHEDULER_ADDRESS=<DEPLOYED_ADDRESS> bun run build
```

Upload the `dist` folder to your host. Without these two variables the app targets Arc Testnet.
