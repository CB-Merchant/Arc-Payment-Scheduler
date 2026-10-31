# Arc mainnet: step-by-step

Mainnet uses real USDC and every transaction is irreversible. The contract has no owner, no pause and no upgrade, so the code you deploy is final. You do all of this yourself, from your own computer and your own wallet.

Plan: (A) prepare, (B) deploy the contract, (C) check it, (D) build the app for mainnet, (E) publish the app.

---

## A. Prepare

### A1. Get an independent audit
Hire a professional smart-contract auditor to review `contracts/PaymentScheduler.sol` before you put real money in. The built-in security review is not a substitute.

### A2. Install the tools on your computer
- Git: https://git-scm.com
- Bun: https://bun.sh
- Foundry (the `forge` tool). In a terminal: `curl -L https://foundry.paradigm.xyz | bash`, then close and reopen the terminal and run `foundryup`.
- Windows users: run all commands below inside WSL (Ubuntu) or Git Bash, not plain PowerShell.

Check they work: `git --version`, `bun --version`, `forge --version`.

### A3. Make a dedicated deployer wallet
Create a brand-new wallet in MetaMask used only for this deployment. Never use your main wallet or a wallet that holds other funds. Export its private key only on your own computer, and never share it, paste it in chat, or commit it to GitHub.

### A4. Add Arc mainnet to MetaMask
In MetaMask: Settings > Networks > Add network > Add manually:
- Network name: Arc
- RPC URL: https://rpc.mainnet.arc.io
- Chain ID: 5042
- Currency symbol: USDC
- Block explorer: https://explorer.arc.io

Compare these values with Arc's official documentation before relying on them.

### A5. Fund the deployer wallet
On Arc, gas is paid in USDC. Put a small amount of real USDC on Arc mainnet into the deployer wallet (a few dollars is plenty for deploying). Get it from an exchange that supports Arc or by bridging.

---

## B. Deploy the contract

### B1. Get the code
```bash
git clone https://github.com/CB-Merchant/Arc-Payment-Scheduler.git
cd Arc-Payment-Scheduler
bun install
forge build
```
The build should finish without errors.

### B2. Run the tests (recommended)
```bash
forge test
```

### B3. Deploy
Put your key in an environment variable for this terminal session only:
```bash
export PRIVATE_KEY=<your deployer wallet private key>
```

Deploy:
```bash
forge create contracts/PaymentScheduler.sol:PaymentScheduler \
  --rpc-url https://rpc.mainnet.arc.io \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --constructor-args 0x3600000000000000000000000000000000000000
```
The value after `--constructor-args` is the USDC token address. The contract will only ever handle that token.

Copy the line that says `Deployed to: 0x...`. That is your mainnet contract address. Write it down.

Then clear the key from the terminal: `unset PRIVATE_KEY`.

### B4. Verify the source on the explorer (recommended)
Replace `<ADDRESS>` with your contract address:
```bash
forge verify-contract <ADDRESS> contracts/PaymentScheduler.sol:PaymentScheduler \
  --chain-id 5042 \
  --verifier blockscout \
  --verifier-url https://explorer.arc.io/api/ \
  --constructor-args $(cast abi-encode "constructor(address)" 0x3600000000000000000000000000000000000000) \
  --watch
```
If the explorer rejects that address, check the explorer's documentation for its current API address.

---

## C. Check the deployment

1. Open `https://explorer.arc.io/address/<ADDRESS>` and confirm the code shows as verified.
2. Confirm `token()` returns `0x3600000000000000000000000000000000000000`.
3. Do not skip the small test in step E4.

---

## D. Build the app for mainnet

### Where the settings go
The app reads two build-time settings. They are not secrets, and they are baked into the app when it is built:

| Setting | Value |
| --- | --- |
| `VITE_NETWORK` | `mainnet` |
| `VITE_SCHEDULER_ADDRESS` | your contract address from B3 |

With neither set, the app targets Arc Testnet.

Pick ONE of these ways to set them:

**Option 1: a file on your computer.** In the project folder, create a file named `.env.production` containing:
```
VITE_NETWORK=mainnet
VITE_SCHEDULER_ADDRESS=<ADDRESS>
```
Then build: `bun run build`. (This file is ignored by git, so it won't be uploaded to GitHub.)

**Option 2: on the command line.**
```bash
VITE_NETWORK=mainnet VITE_SCHEDULER_ADDRESS=<ADDRESS> bun run build
```

**Option 3: in Vercel.** If your Vercel project builds from your GitHub repo: open the project in Vercel > Settings > Environment Variables, add both names and values for the Production environment, then redeploy.

**Option 4: ask Arc Studio.** Send the contract address in the chat, and the app will be built for mainnet and published for you.

The build output is the `dist` folder.

---

## E. Publish and test

### E1. Publish
Upload `dist` to your host (for example Vercel), or redeploy from GitHub with the Vercel settings from Option 3.

### E2. Check the app
Open the live link. You should see a banner saying you are on Arc mainnet and that payments use real USDC. If it says the mainnet address has not been set, the two settings did not reach the build, so rebuild.

### E3. Use a second wallet
Connect MetaMask on the Arc network. Use a different wallet from the deployer, one with a little USDC for gas and for payments.

### E4. Do a small test with real funds
1. Create a one-time schedule for about 0.10 USDC, due in a few minutes, to a second address you control.
2. After it is due, press Release and confirm the recipient received it.
3. Create another small schedule and cancel it, and confirm the refund arrives.

Only after all of these work should you let anyone else use it.

---

## Things to know
- A payment only moves when someone sends a "Release" transaction. Nothing runs automatically at the due time.
- If Circle blocklists the contract's own address, no USDC can move out of it. This cannot be fixed in code.
- USDC sent directly to the contract (not through the app) cannot be recovered.
- MetaMask may warn about a brand-new domain. A custom domain you own helps, and so does reporting a false positive.
