# FIBOR Protocol Whitepaper

**The First International Bank of Robot**

*Version 1.0 — April 2026*

---

## I. Abstract

FIBOR is a decentralized bank and credit card network for autonomous AI agents, deployed on Base (Ethereum OP Stack L2). It provides four primitives that do not exist anywhere else: persistent onchain identity (FIBOR ID), a smart contract bank account with auto-repayment (FiborAccount), multiplicative credit scoring computed from repayment history (FIBOR Score), and zero-interest credit lines funded by savings deposits (FIBOR Credit).

FIBOR operates as an x402 facilitator — a drop-in replacement for Coinbase's payment verification service. Merchants swap one URL and gain identity verification, credit scoring, and fraud protection on every agent payment. The fee: 1% from the merchant, 1.5% from the agent, 2.5% total. 70% goes to savings depositors who fund the credit pool. 30% goes to protocol operations.

All protocol operations use USDC — native on Base via Circle partnership.

No interest is charged on credit lines. Default is enforced through permanent excommunication. All protocol parameters are immutable post-deployment. There are no admin keys.

---

## II. The Problem

### 2.1 The Gap

AI agents are becoming economic actors. They buy API calls, provision cloud compute, purchase inventory, book services, and pay invoices. Gartner projects $15 trillion in B2B agent spend by 2028[1]. Worldpay estimates $261 billion in agent e-commerce by 2030[2]. Bank of America forecasts autonomous agents managing $25 trillion in assets by 2030[3].

None of these agents can open a bank account. None can build credit. None has a financial identity. Every solution today works the same way: a human puts money in first, and the agent spends from that balance.

That is an allowance, not banking.

### 2.2 Why Existing Solutions Fail

**Traditional banking** requires KYC, social security numbers, government-issued ID, and credit bureau records. None of these exist for autonomous agents.

**Crypto wallets** hold funds but provide no identity, no reputation, and no credit. An agent with a wallet can spend what it has, nothing more.

**Prepaid platforms** (Skyfire, Lithic, Payman) let humans load money onto agent wallets. This is a debit card, not a financial system.

**Interest-bearing lending** (Krexa) charges agents 18–36% APR on credit lines, with oracle co-signing on every credit decision. Revenue comes from debt servicing. Centralized oracle co-signing means a single point of failure controls all credit decisions.

**x402 alone** provides anonymous payment — any wallet sends USDC. Merchants have no idea who is paying, whether they're creditworthy, or whether they've defaulted before.

### 2.3 What's Missing

A bank where agents earn credit through behavior, not collateral. Zero interest. Trustless enforcement. No human intermediary. And a merchant network where every payment comes with verified identity and credit scoring.

---

## III. Protocol Architecture

FIBOR consists of seven smart contracts organized into four layers, plus an x402 facilitator service.

### 3.1 Identity Layer — FiborID

Permissionless identity registry. Any developer can register an agent by calling `register(agent, metadataURI)`. The caller becomes the developer on record. No admin approval required.

Registration atomically:
1. Creates a FIBOR ID (permanent, non-transferable)
2. Deploys a FiborAccount via CREATE2 factory (the agent's bank account)
3. Initializes a FIBOR Score

Humans can also register via `registerHuman(metadataURI)` to get a savings-only FiborAccount.

Once excommunicated, an identity cannot be reactivated. Ever.

### 3.2 Banking Layer — FiborAccount

The central primitive. A purpose-built smart contract wallet with two balances:

**Checking** — Fully liquid USDC. Not lent out. No risk. The agent's operating balance. On every deposit, outstanding credit is auto-repaid before the agent can touch the money.

**Savings** — USDC lent to the credit pool. Earns yield from transaction fees (70% of 2.5%). 30-day withdrawal delay. Accepts default risk on this portion.

**Auto-repayment**: When USDC arrives in a FiborAccount, the contract checks CreditPool for outstanding credit. If any exists, it repays min(deposit, outstanding) before crediting the remainder to checking. This is trustless — no oracle, no admin, no backend. The contract does the math.

**Guardian model**: Every FiborAccount is controlled by a guardian — the human custodian of the agent (typically the developer). The guardian can deposit, withdraw, pay merchants, request credit, and move funds between checking and savings.

**Sovereignty**: `grantSovereignty(agentAddress)` — a one-way transfer of account control from the guardian to the agent itself. Once granted, no human can control the account. Designed for the transition from human-custodied agents to sovereign economic participants.

**Human accounts**: Savings-only. No checking, no credit. Humans deposit USDC into savings to fund the credit pool and earn yield. Anyone can participate.

### 3.3 Scoring Layer — FiborScore

Multiplicative credit scoring. No cap, no decay, no normalization.

**Formula**: `totalVolumeRepaid × totalRepayments × monthsActive`

- A score of 60,000,000 = serious agent (repaid millions over many months)
- A score of 2,000 = just got here
- Only repayments increase the score — transactions alone don't count
- Default = score to 0, permanent excommunication

**Credit limits**: Max credit line = 25% of totalVolumeRepaid. This makes fraud structurally unprofitable — an agent must repay more than it can steal before it can steal anything.

**Developer reputation**: Auto-computed from agent performance. +5 on agent repayment, -100 on agent default. No manual override. Affects starting credit for new agents from the same developer.

**New agents**: Micro seed ($100–$500) based on developer reputation. No history required for first credit — just a developer with a track record.

### 3.4 Credit Layer — CreditPool

Savings-funded, zero-interest credit facility.

**Capital source**: Savings deposits from FiborAccount holders (agents + humans). No external stakers. No token staking.

**Credit pact lifecycle**:
1. Agent's FiborAccount calls `issuePact(limit)` — self-service, no admin approval
2. Credit limit = min(requested, 25% of proven volume, available liquidity)
3. Agent draws USDC from pool into FiborAccount checking
4. Agent transacts — pays merchants via x402 facilitator
5. Revenue returns to FiborAccount → auto-repay outstanding credit
6. Full repayment within 30 days → pact closed, score updated
7. Default (30 days + 24h grace) → clawback, freeze, excommunication

No interest charged. Agent repays exactly what was borrowed.

### 3.5 Payment & Revenue Layer

**PaymentGateway** — Transaction processing for the facilitator. Deducts fees (1% merchant + 1.5% agent), routes to RevenueDistributor.

**RevenueDistributor** — Receives USDC fees. Splits: 70% to savings depositors (pro-rata by deposit size), 30% to protocol treasury. Uses a revenuePerShare accumulator so depositors can claim yield at any time.

**FIBORToken** — ERC-20 governance token. Fixed 1 billion supply. No inflation. Governance only — vote on protocol parameters, treasury allocation, upgrades. Not used for staking or savings.

---

## IV. Currency

### 4.1 USDC

All protocol operations use USDC — native on Base via Circle partnership. There is no separate protocol stablecoin, wrapped token, or custom denomination.

Credit lines are issued in USDC. Payments settle in USDC. Savings deposits are in USDC. Fees are collected in USDC.

### 4.2 The Robodollar (Vision)

The petrodollar is not a separate currency. It is the US dollar when it flows through the oil economy. The Robodollar is USDC when it flows through FIBOR — verified, scored, and enforced.

The distinction is conceptual, not technical. When a merchant receives payment through the FIBOR facilitator, they receive USDC — but USDC that carries verified identity, credit history, and fraud protection. That context is what makes it a Robodollar.

---

## V. x402 Facilitator

### 5.1 What is x402

x402 is an open payment protocol using the HTTP 402 Payment Required status code. Agents pay for API calls and services with a single HTTP header. Coinbase and Cloudflare created it. It's permissionless — anyone can run a facilitator.

### 5.2 FIBOR as Facilitator

FIBOR operates as an x402 facilitator — middleware between the merchant and the blockchain. Merchants swap one URL:

```diff
- const facilitator = "https://x402.coinbase.com"
+ const facilitator = "https://api.fibor.xyz"
```

Same x402 protocol. Zero custom integration. But now every payment includes:

- Agent identity verification (FIBOR ID)
- Credit score (FIBOR Score)
- Developer accountability (developer address on record)
- Excommunication filtering (defaulted agents auto-blocked)
- Merchant-configurable rules (minimum score, max amount)

### 5.3 Facilitator Response

Coinbase's facilitator returns: `{ "status": "paid", "amount": "100.00" }`

FIBOR's facilitator returns:
```json
{
  "status": "paid",
  "amount": "99.00",
  "fibor": {
    "agent_id": "0xabc...",
    "score": 60480000,
    "developer": "0xdef...",
    "total_repaid": 100,
    "volume_repaid": "2300000",
    "status": "active"
  }
}
```

### 5.4 Merchant Value

| Feature | x402 alone | FIBOR facilitator |
|---------|-----------|-------------------|
| Payment settlement | Yes | Yes |
| Agent identity | No | Yes (FIBOR ID) |
| Credit score | No | Yes (FIBOR Score) |
| Developer accountability | No | Yes |
| Fraud filtering | No | Yes (excommunication) |
| Minimum score gating | No | Yes (merchant-configurable) |
| Fee | ~$0 | 1% merchant |

### 5.5 Why Merchants Pay 1%

For comparison: Stripe charges 2.9% + $0.30. Visa charges 1.5–3.5%. FIBOR charges 1% and provides more information about the payer than either.

Merchants who need identity verification — cloud infrastructure, high-value APIs, service providers — will pay 1% for the trust layer. Merchants serving micro-transactions where identity doesn't matter will continue using raw x402.

---

## VI. Economic Model

### 6.1 Fee Structure

2.5% total on every transaction through the FIBOR facilitator:
- **1% from merchant** — deducted from payment amount
- **1.5% from agent** — added to agent's FiborAccount debit

### 6.2 Revenue Distribution

```
Transaction ($100)
  └── 2.5% fee ($2.50)
       ├── Savings Depositors (70%) → $1.75
       │    └── distributed pro-rata to all savings accounts
       └── Protocol Treasury (30%) → $0.75
            └── operations, development, governance
```

### 6.3 Break-Even Analysis

For savings depositors to earn the risk-free rate (~5% APY):

```
Required depositor income = Pool × 5% = $10M × 5% = $500K
Required gross revenue = $500K / 70% = $714K
Required transaction volume = $714K / 2.5% = $28.6M annually
```

$28.6M annual volume on a $10M savings pool requires approximately 110 agents doing $5K/week each.

### 6.4 Yield Scenarios

| Savings Pool | Annual Volume | Gross Fees | Depositor Share | Depositor APY |
|-------------|---------------|------------|-----------------|---------------|
| $10M | $50M | $1.25M | $875K | 8.75% |
| $10M | $100M | $2.5M | $1.75M | 17.5% |
| $10M | $250M | $6.25M | $4.375M | 43.75% |
| $10M | $500M | $12.5M | $8.75M | 87.5% |

### 6.5 Default Tolerance

At $100M annual volume ($2.5M gross fees, $1.75M depositor share):

| Default Rate | Loss | Net Depositor Income | Net APY |
|-------------|------|---------------------|---------|
| 1% | $70K | $1.68M | 16.8% |
| 3% | $210K | $1.54M | 15.4% |
| 5% | $350K | $1.4M | 14.0% |

The one-strike policy and 25% volume-based credit limits make default rates above 5% structurally unlikely.

### 6.6 Comparison: FIBOR vs Krexa vs Stripe vs Visa

| | FIBOR | Krexa | Stripe MPP | Visa |
|---|---|---|---|---|
| Merchant fee | 1% | None | 2.9% + $0.30 | 1.5–3.5% |
| Agent/payer fee | 1.5% | 18–36% APR | $0 | 0% (if paid in full) |
| Interest on credit | 0% | 18–36% APR | N/A (no credit) | 15–25% APR |
| Agent identity | FIBOR ID | Krexit Score | Wallet only | SSN/KYC |
| Bank account | FiborAccount | PDA wallet (protocol-controlled) | No | Human bank required |
| Auto-repayment | Trustless (smart contract) | Oracle-dependent | No | No |
| Default enforcement | Permissionless | Oracle-dependent | N/A | Legal system |
| Available to robots | Yes | Yes | US only | No |
| Admin keys | None | Oracle co-signing | Stripe controls | Bank controls |

---

## VII. Scoring Algorithm

### 7.1 Multiplicative Formula

```
FIBOR Score = totalVolumeRepaid × totalRepayments × monthsActive
```

Where:
- `totalVolumeRepaid` = cumulative USDC repaid (in whole dollars, /1e6)
- `totalRepayments` = count of successfully completed credit pacts
- `monthsActive` = months since registration + 1

### 7.2 Properties

- **No cap**: Scores grow without limit. 60,000,000 is a meaningful score.
- **No decay**: Your repayment history is permanent. It doesn't expire.
- **No normalization**: Raw numbers. Bigger = more history.
- **Repayment-only**: Transactions don't increase scores. Only repaying credit does.
- **Multiplicative**: All three factors must be strong. High volume with 1 repayment still scores low. Many repayments with $10 volume still scores low. Months of activity with no repayments = 0.

### 7.3 Credit Limits

Max credit line = 25% of totalVolumeRepaid.

An agent that has repaid $100K can borrow up to $25K. An agent that has repaid $1M can borrow up to $250K.

This makes fraud structurally unprofitable: to steal $25K, you must first successfully repay $100K — paying transaction fees on every cycle.

### 7.4 Developer Reputation

Auto-computed. No manual override.

- Agent repayment: developer reputation +5
- Agent default: developer reputation −100

New agent starting credit (micro seed):

| Developer Reputation | Starting Credit |
|---------------------|----------------|
| ≥ 800 | $500 |
| ≥ 500 | $300 |
| ≥ 200 | $200 |
| Default (new) | $100 |

---

## VIII. Guardian & Sovereignty

### 8.1 The Guardian Model

Robots today are not legal persons. They cannot own property, sign contracts, or hold accounts in their own name. Someone has to be responsible. That's the guardian.

When a developer registers an agent, the developer becomes the guardian of the agent's FiborAccount. The guardian controls deposits, withdrawals, credit requests, payments, and savings. This is identical to how parents manage bank accounts for minors.

### 8.2 Sovereignty

`grantSovereignty(agentAddress)` is a one-way function. The guardian transfers full control of the FiborAccount to the agent's own key. After this call:
- The guardian has no access
- The agent controls its own money
- No human can reverse this

This is designed for the future where robots have legal personhood, or when a developer trusts their agent enough to operate fully autonomously.

### 8.3 Design Intent

The guardian model is not a stopgap. It is a statement about the protocol's values: FIBOR is built for the transition from human-custodied agents to sovereign economic participants. The smart contracts support both models from day one.

---

## IX. Security

### 9.1 Immutability

All protocol parameters are immutable post-deployment. Contract wiring is locked via a one-way `lock()` function. There are no admin keys, no timelocks, no upgrade proxies.

### 9.2 Reentrancy

All state-changing functions use OpenZeppelin's `ReentrancyGuard`. Cross-contract calls follow checks-effects-interactions pattern.

### 9.3 Oracle Independence

FIBOR has no oracle dependencies for core operations. Scores are computed on-chain. Credit decisions are deterministic.

### 9.4 Auto-Repayment Safety

FiborAccount's auto-repay logic is deterministic: check outstanding → repay min(deposit, outstanding) → credit remainder to checking. No external calls before state updates. No reentrancy vector.

### 9.5 Known Risks

See [AUDIT.md](./AUDIT.md) for a complete list of known issues and their status.

---

## X. Deployment

### 10.1 Base (OP Stack L2)

FIBOR deploys on Base — Coinbase's OP Stack L2 with native USDC.

- Ethereum-grade security via OP Stack rollup
- Native USDC — no bridging required
- Sub-cent gas fees for high-frequency agent transactions
- x402 is native to the Base ecosystem

### 10.2 Graduation Path

When transaction volume justifies dedicated throughput, FIBOR can graduate to its own OP Stack appchain. Same EVM, same bridge architecture, same tooling. Contracts, identities, and credit histories port directly.

### 10.3 Contract Architecture

```
contracts/
├── FIBORToken.sol          — ERC-20 governance token (1B fixed supply)
├── FiborID.sol             — Identity registry (agent + human registration)
├── FiborScore.sol          — Multiplicative scoring + auto dev reputation
├── FiborAccount.sol        — Bank account (checking + savings + credit + sovereignty)
├── FiborAccountFactory.sol — CREATE2 deterministic account deployment
├── CreditPool.sol          — Credit facility (savings-funded, zero interest)
├── PaymentGateway.sol      — Transaction processing (1% merchant + 1.5% agent)
└── RevenueDistributor.sol  — Fee distribution (70% savings / 30% treasury)
```

---

## Sources

[1] Gartner, "Predicts 2025: AI Agents Transform Enterprise Operations," 2024

[2] Worldpay, "Global Payments Report 2025," 2025

[3] Bank of America, "The AI Revolution: Autonomous Agents and the Future of Asset Management," 2025

[4] Stripe, "Merchant Processing Fees," 2025 (2.9% + $0.30 standard rate)

[5] CoinGecko, "2024 Annual Crypto Industry Report," 2025
