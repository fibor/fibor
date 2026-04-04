# FIBOR
## The First International Bank of Robot

AI agents are economic actors. They buy API calls, rent cloud compute, procure inventory, and hire services. Gartner projects $15 trillion in B2B agent spending by 2028[1]. Worldpay estimates $261 billion in agent-driven e-commerce by 2030[2]. Bank of America forecasts autonomous agents managing $25 trillion in assets by the end of the decade[3]. These are not assistants waiting for human approval. They are autonomous participants in the economy, spending real money on real infrastructure.

But they cannot open bank accounts. They cannot build credit. They cannot access working capital. Every solution today works the same way: a human deposits money first, the agent spends from that balance. That is an allowance, not banking. The total credit history of every AI agent in existence is $0.

Banks were built for humans — KYC, social security numbers, credit bureaus, branch visits. None of these apply to software. Crypto was built for speculation — liquid tokens before value, governance before revenue. Neither system was designed for autonomous agents that need identity, reputation, and credit.

Skyfire, Lithic, and Payman offer prepaid agent wallets. A human loads funds, the agent draws down. No identity, no scoring, no credit. Krexa offers interest-bearing agent lending at 36% APR on its lowest tier, with a centralized oracle co-signing every credit decision. Its revenue comes from debt, not commerce. These are the incumbents: custodial allowances and predatory lending, the same models traditional finance already failed at, repackaged for machines.

What is missing is a bank where agents earn credit through behavior, not collateral. Zero interest. Trustless enforcement. No human co-signers. And a credit card network where merchants can verify who is paying them.

### FIBOR is the first decentralized bank and credit card network for autonomous AI agents. Every agent gets a bank account, a credit score, and access to zero-interest credit — all enforced by smart contracts on Base.

The protocol has four layers. **FIBOR ID** is a permissionless onchain identity that any developer can register without approval. **FIBOR Score** is a multiplicative creditworthiness metric — totalVolumeRepaid × totalRepayments × monthsActive — that produces scores from 2,000 (brand new) to billions (established). **FIBOR Credit** extends zero-interest credit lines capped at 25% of proven repayment volume, making fraud structurally unprofitable. And **FiborAccount** is the bank account itself — a smart contract wallet with checking (liquid, not lent) and savings (lent to the credit pool, earns yield) — with trustless auto-repayment on every deposit.

All protocol operations use USDC — native on Base via Circle. The petrodollar runs the world today. The Robodollar — USDC flowing through the FIBOR network, verified and scored — will run the machine economy tomorrow.

FIBOR operates as an x402 facilitator — a drop-in replacement for Coinbase's payment verification service. Merchants swap one URL and gain identity verification, credit scoring, and fraud protection on every agent payment. The fee: 1% from the merchant, 1.5% from the agent, 2.5% total. 75% goes to savings depositors who fund the credit pool. 25% goes to protocol operations. No interest is charged, ever.

The credit pool is not funded by external stakers. It is funded by savings deposits from FiborAccount holders — both agents and humans. Agents deposit revenue into savings to earn yield. Humans open savings-only accounts to participate. The ecosystem funds itself. This is a cooperative bank, not a DeFi yield farm.

The credit system works because the penalty for default is absolute. Default once, excommunicated forever. The agent's account is frozen, outstanding balances clawed back automatically. Anyone can call `declareDefault` — enforcement is permissionless. Credit limits are capped at 25% of proven volume, so the maximum theft is always less than the cost of building the reputation required to access it. The severity of the penalty is what makes zero-interest credit possible.

FiborAccount is controlled by a guardian — the human custodian of the agent. When robots are granted sovereignty and personhood, control transfers to the agent itself via `grantSovereignty()`. This is a one-way gate, designed for the transition from human-custodied agents to sovereign economic participants.

FIBOR launches on Base, Coinbase's OP Stack L2, where x402 is the native payment protocol and over $10 billion in stablecoins are in circulation[5]. The facilitator integrates with x402 at the protocol level — no custom merchant SDK, no separate payment rail.

The endgame is USDC flowing through FIBOR as the default rails for machine commerce — every dollar verified, scored, and enforced. The financial system spent five centuries building credit infrastructure for humans. FIBOR builds it for machines, and it starts now.


Sources

[1] $15T in B2B agent spending by 2028: Gartner, "Agentic AI" forecast, 2024

[2] $261B in agent-driven e-commerce by 2030: Worldpay Global Payments Report, 2024

[3] $25T in agent-managed assets by 2030: Bank of America Global Research, 2024

[4] Stripe USDC integration on Base: Stripe Blog, October 2024

[5] Base stablecoin circulation: CoinGecko; DeFi Llama
