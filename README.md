# FHEarn · Confidential Score-Based APY

FHEarn is a decentralized savings experience that assigns a personalized APY to every wallet based on its on-chain behaviour. Fully Homomorphic Encryption (FHEVM) keeps stake amounts, rewards and APY private while we analyse public wallet data to calculate a reputation score.

> Built on Sepolia with Vue 3, ethers v6, Covalent API and Zama’s FHEVM relayer SDK.

---

## Table of Contents

1. [Why FHEarn?](#why-fhearn)
2. [High-Level Architecture](#high-level-architecture)
3. [User Journey](#user-journey)
4. [Scoring & APY Algorithm](#scoring--apy-algorithm)
5. [FHEVM Integration](#fhevm-integration)
6. [Local Development](#local-development)
7. [Project Structure](#project-structure)
8. [Current Limitations & Next Steps](#current-limitations--next-steps)

---

## Why FHEarn?

- **Score-Based APY** – wallets earn between **5% and 25%** based on their on-chain reputation.
- **Confidential by Design** – stake amount, APY and rewards stay encrypted throughout contract storage and computation using FHEVM.
- **Multi-Chain Intelligence** – Covalent API aggregates balances, token holdings and activity across 7+ chains before scoring.
- **Smooth UX** – modern landing page with animated aurora background, fast wallet connect flow and detailed analytics dashboard.

---

## High-Level Architecture

```
┌────────────┐        ┌─────────────────────────┐        ┌────────────────────┐
│  Frontend  │        │     FHEarn Backend      │        │  External Services │
│ Vue + Vite │  REST  │ Hardhat + FHE Contracts │  RPC   │  • Covalent API     │
│            │ <────> │  • FHEarnStake.sol      │ <────> │  • Sepolia RPC      │
│            │        │  • FHEarnCore.sol       │        │  • FHEVM Relayer    │
└────────────┘        └─────────────────────────┘        └────────────────────┘
     │                         │                                     │
     └───────── ethers.js ─────┴───────────── on-chain ──────────────┘
```

- **Frontend (`FHEarn-Frontend/`)** – Vue 3 SPA that fetches wallet analytics, computes scores, displays APY tiers, and triggers encrypted staking transactions.
- **Backend (`FHEarn-Backend/`)** – Hardhat workspace containing the confidential staking contracts and deployment scripts.
- **Contracts** – `FHEarnStake.sol` stores encrypted stakes, handles reward calculations and controls withdrawals; `FHEarnCore.sol` provides shared helpers.

---

## User Journey

1. **Landing Page** – Animated aurora hero explains the offering and highlights privacy, scoring and partner tech.
2. **Connect Wallet** – User links MetaMask on Sepolia. We detect existing stakes via `getStakeInfoFull`.
3. **Analytics & Scoring**
   - Fetch multi-chain data (balance, total transactions, wallet age, tokens) using Covalent.
   - Run the scoring algorithm locally in the browser.
   - Display tier, APY, and detailed wallet metrics.
4. **Stake Flow**
   - Frontend encrypts stake amount and APY via FHEVM relayer SDK (`createEncryptedInput → add64 → encrypt`).
   - Calls `FHEarnStake.stake`, storing encrypted values and public mirrors for UI baselines.
5. **Earning Rewards** – Rewards accrue privately inside the contract (encrypted reward computation).
6. **Withdraw** – User executes `withdrawAll` (encrypted) or `withdrawAllClear` (clear mirror fallback) to receive principal + rewards. Claim-only rewards is currently disabled pending relayer integration.

---

## Scoring & APY Algorithm

### Score Components (max 120 base points)

| Component                 | Formula / Notes                       | Cap |
|---------------------------|---------------------------------------|-----|
| Transaction Activity      | `log₁₀(totalTx + 1) * 10`             | 30  |
| Wallet Age                | `years * 2`                            | 20  |
| Multi-chain Usage         | `activeChains * 5`                     | 25  |
| Token Diversity           | `log₁₀(totalTokens + 1) * 5`          | 15  |
| Active Tokens             | `activeTokens * 2`                     | 10  |
| ETH Balance               | `log₁₀(balanceETH * 1000 + 1) * 3`    | 20  |

**Bonus Multipliers**

- +0.1 for ≥3 active chains (stackable with ≥5 chains)
- +0.1 for ≥100 transactions (stackable with ≥500)
- +0.1 for ≥2 years age (stackable with ≥4 years)

Final score is rounded and capped at **150**.

### APY Tiers

| Score Range | Tier         | APY |
|-------------|--------------|-----|
| 120 – 150   | Elite        | 25% |
| 90  – 119   | Advanced     | 20% |
| 70  – 89    | Experienced  | 15% |
| 50  – 69    | Intermediate | 12% |
| 30  – 49    | Beginner     | 8%  |
| 0   – 29    | Newcomer     | 5%  |

The frontend stores the tier and APY immediately after calculation and re-synchronises with contract state after each transaction.

---

## FHEVM Integration

### Frontend Usage (Relayer SDK)

- `createEncryptedInput(contractAddress, userAddress)` – builds an encrypted payload.
- `input.add64(value)` – pushes 64-bit values (stake amount in wei, APY percent).
- `await input.encrypt()` – obtains encrypted handles & proof to pass into the contract.
- Decryption helpers: `publicDecrypt([handle])` with fallback to `userDecrypt({ ciphertext, publicKey, owner })` if public decrypt is restricted.

### Smart Contract Usage (`FHEarnStake.sol`)

- `FHE.fromExternal` – imports encrypted values supplied by the relayer.
- `FHE.makePubliclyDecryptable` – allows the frontend to read baselines (stake amount, timestamp, APY) via public decrypt.
- `FHE.asEuint64`, `FHE.sub`, `FHE.div`, `FHE.mul`, `FHE.add` – arithmetic over encrypted integers for reward calculations.
- `FHE.allowThis` / `FHE.allow` – controls which addresses may decrypt or operate on encrypted values.
- `calculateEncryptedReward` – computes `(amount * timeElapsed / YEAR) * apy` entirely under encryption.

At the moment `claimReward` still awaits a production relayer. Users withdraw both principal and rewards via `withdrawAll` or `withdrawAllClear` which resets encrypted baselines (`lastClaimTime`, `amount`).

---

## Local Development

### Prerequisites

- Node.js **20+**
- PNPM / NPM (project uses npm lockfiles)
- MetaMask configured for **Sepolia**
- Sepolia ETH faucet tokens

### Frontend

```bash
cd FHEarn-Frontend
npm install
npm run dev     # local development
npm run build   # production bundle
npm run preview # serve /dist
```

Environment hints:

- Covalent API key is currently hard-coded for demo purposes (`src/components/FHEarn.vue`).
- Contract addresses are in `src/FHEarn.json`.
- Network details live in `src/Network.json`.

### Backend / Contracts

```bash
cd FHEarn-Backend
npm install
npx hardhat compile
npx hardhat test
# Deploy to Sepolia (requires INFURA_API_KEY / PRIVATE_KEY via hardhat vars)
npx hardhat deploy --network sepolia
```

Important Hardhat vars:

- `MNEMONIC` – fallback account for local networks.
- `PRIVATE_KEY` – deployer on Sepolia (optional if using mnemonic).
- `INFURA_API_KEY` – only required if you switch RPC URL to Infura.

---

## Project Structure

```
├── FHEarn-Frontend/        # Vue 3 SPA
│   ├── src/components/     # Landing & dApp views
│   ├── src/contracts/      # ABI artefacts (Confidential token, oracle)
│   └── src/FHEarn.json     # Contract addresses / metadata
├── FHEarn-Backend/         # Hardhat workspace
│   ├── contracts/          # FHEarnStake.sol and helpers
│   ├── deploy/             # Hardhat deploy scripts
│   └── types/              # Typechain bindings (ethers v6)
└── README.md               # You are here
```

---

## Current Limitations & Next Steps

- **Claim-Only Rewards** – UI button removed until relayer-backed decryption flow is finished. To enable, wire `_requestDecryption` to Zama’s relayer and resume `claimReward()`.
- **Secret Management** – Covalent key and other demo configuration values are hard-coded; migrate to `.env` + Vite/Hardhat env loaders before production.
- **Relayer Reliability** – Add monitoring / retry logic for decryption requests once claim-only rewards are reintroduced.
- **Testing** – Unit tests cover contract compilation; additional integration specs (e.g., scoring edge cases) can be added.

Have ideas or questions? Open an issue or reach us via the repo discussions.

---

© 2025 FHEarn. Licensed under the BSD 3-Clause Clear License.


