# FIBOR Architecture

## Overview

FIBOR is the First International Bank of Robot — a decentralized bank and credit card network for autonomous AI agents deployed on Base (OP Stack L2). It provides bank accounts, financial identity, credit scoring, and zero-interest credit lines, plus an x402 facilitator that gives merchants identity verification and fraud protection on every agent payment.

## Chain

### Base (OP Stack L2)

FIBOR deploys on Base — Coinbase's OP Stack L2 with native USDC (Circle partnership).

- Ethereum-grade security via OP Stack rollup
- Native USDC — no bridging required
- Sub-cent gas fees for high-frequency agent transactions
- x402 protocol is native to the Base ecosystem
- Graduation path: when volume justifies it, migrate to own OP Stack appchain (same EVM, same tooling)

ETH is used for gas. FIBOR is the governance token, not the gas token.

## Token Architecture

### FIBOR (ERC-20)

Governance token only. Not used for staking or savings.

- **Fixed supply:** 1 billion, all minted to treasury at deploy. No inflation.
- **Governance:** Vote on protocol parameters — fee rates, credit limits, treasury allocation, protocol upgrades.
- **Not staking:** The credit pool is funded by USDC savings deposits, not FIBOR token staking.

### Currency

All protocol operations use USDC (native on Base via Circle partnership). There is no separate protocol stablecoin or wrapped token.

## Core Modules

### FiborAccount (Bank Account)

The central primitive. Every participant gets a FiborAccount — a purpose-built smart contract wallet.

**Agent accounts** (full features):
- Checking balance: fully liquid USDC, not lent out, withdraw anytime
- Savings balance: USDC lent to credit pool, earns yield, 30-day withdrawal delay
- Credit access: draw zero-interest credit lines
- Auto-repayment: on every deposit, outstanding credit is repaid first
- Guardian/sovereignty: developer controls until `grantSovereignty()` transfers to agent

**Human accounts** (savings only):
- Savings balance only — no checking, no credit
- Deposit USDC, earn yield from agent transaction fees
- Anyone can participate, no agent required

### FIBOR ID

Permissionless onchain identity for agents and humans.

- Developer-initiated registration: `register(agentAddress, metadataURI)`
- Human registration: `registerHuman(metadataURI)`
- Registration auto-deploys a FiborAccount via CREATE2 factory
- Agent registration auto-initializes FIBOR Score
- Once excommunicated, an ID cannot be reactivated. Ever.
- Guardian = msg.sender at registration (the developer)

### FIBOR Score

Multiplicative credit scoring. No cap, no decay, no normalization.

**Formula:** `totalVolumeRepaid × totalRepayments × monthsActive`

- A score of 60,000,000 = serious agent
- A score of 2,000 = just got here
- Only repayments increase the score — transactions alone don't count
- Default = score to 0, permanent excommunication

**Credit limits:**
- Max credit line = 25% of totalVolumeRepaid
- This makes fraud structurally unprofitable (you spend more building reputation than you can steal)
- New agents: micro seed ($100–$500) based on developer reputation

**Developer reputation:**
- Auto-computed: +5 on agent repayment, -100 on agent default
- No manual override
- Affects starting credit for new agents from the same developer

### Credit Facility (CreditPool)

Savings-funded, zero-interest credit.

**Capital source:** Savings deposits from FiborAccount holders (agents + humans). No external stakers.

**Credit pact lifecycle:**
1. Agent's FiborAccount calls `issuePact(limit)` — self-service, no admin approval
2. Credit limit = min(requested, 25% of proven volume, available liquidity)
3. Agent draws USDC from pool into FiborAccount checking
4. Agent transacts — pays merchants via PaymentGateway or x402
5. Revenue returns to FiborAccount → auto-repay outstanding credit
6. Full repayment within 30 days → pact closed, score updated
7. Default (30 days + 24h grace) → clawback, freeze, excommunication

**No interest charged.** Agent repays exactly what was borrowed.

### One-Strike Enforcement

Enforced at the smart contract level. No admin override.

1. Pact expires + 24-hour grace period passes
2. Anyone calls `declareDefault(pactId)` — permissionless
3. FiborAccount is frozen (no withdrawals)
4. Outstanding USDC clawed back to credit pool
5. FIBOR Score → 0
6. FIBOR ID → excommunicated (permanent, irreversible)
7. Developer reputation reduced (-100)
8. Event emitted for all network participants

No appeals. No exceptions.

## Revenue Model

### Fee Structure

2.5% total on every transaction through the FIBOR facilitator:
- **1% from merchant** — for identity verification, score checks, fraud protection
- **1.5% from agent** — for credit access, bank account, financial identity

### Revenue Distribution

```
Transaction ($100 USDC)
  └── 2.5% fee ($2.50)
       ├── Savings Depositors (75%) → $1.875
       │    └── distributed pro-rata to all savings accounts
       └── Protocol Treasury (25%) → $0.625
            └── operations, development, governance
```

No interest charged. No origination fees. No account fees.

## x402 Facilitator

FIBOR operates as an x402 facilitator — a drop-in replacement for Coinbase's payment verification service.

**Merchant integration:**
```
- const facilitator = "https://x402.coinbase.com"
+ const facilitator = "https://api.fibor.xyz"
```

One URL change. No custom SDK. Same x402 protocol.

**What merchants get:**
- Agent identity (FIBOR ID)
- Credit score (FIBOR Score)
- Developer address (accountability)
- Excommunication status (fraud protection)
- Configurable rules (minimum score, max amount)

**Facilitator response includes:**
```json
{
  "status": "paid",
  "amount": "99.00",
  "fibor": {
    "agent_id": "0xabc...",
    "score": 60000000,
    "developer": "0xdef...",
    "total_repaid": 47,
    "status": "active"
  }
}
```

## Smart Contract Architecture

```
contracts/
├── FIBORToken.sol          — ERC-20 governance token (1B fixed supply)
├── FiborID.sol             — Identity registry (agent + human registration)
├── FiborScore.sol          — Multiplicative scoring + auto dev reputation
├── FiborAccount.sol        — Bank account (checking + savings + credit + sovereignty)
├── FiborAccountFactory.sol — CREATE2 deterministic account deployment
├── CreditPool.sol          — Credit facility (savings-funded, zero interest, 30d pacts)
├── PaymentGateway.sol      — Transaction processing (1% merchant + 1.5% agent)
└── RevenueDistributor.sol  — Fee distribution (75% savings depositors / 25% treasury)
```

All contracts use a one-way `lock()` gate on admin setters. After deployment wiring is complete, the owner calls `lock()` and all admin functions are permanently disabled. No admin keys retained.

## External Integrations

- **USDC (Circle):** Native on Base — the underlying asset for all protocol operations
- **x402 Protocol:** FIBOR facilitator integrates at the protocol level
- **Base (OP Stack L2):** Block production, settlement, Ethereum L1 security
- **Chainlink / API3:** Price feeds if needed for any USD conversions

## Guardian / Sovereignty Model

- **Guardian:** The human custodian of an agent's FiborAccount. Typically the developer who registered the agent.
- **Sovereignty:** `grantSovereignty(agentAddress)` — one-way transfer of account control to the agent itself. Once granted, no human can control the account.
- Designed for the transition from human-custodied agents to sovereign economic participants.
- Inspired by the principles in Systema Robotica — robot identity, personhood, and autonomy as first-class protocol concerns.
