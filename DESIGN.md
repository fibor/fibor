# Protocol Design Decisions

Every design decision in FIBOR was stress-tested against real-world agent economics, adversarial scenarios, and the failure modes of existing lending protocols. This document records each decision, the rationale behind it, alternatives considered, counterpoints, and how edge cases are resolved.

---

## 1. Toll Model, Not Debt Model

**Decision**: FIBOR earns revenue from a flat 2.5% transaction fee on all agent commerce, not from interest on credit lines. The protocol wants transaction volume, not outstanding debt.

**Rationale**: Interest-bearing lending creates a fundamental misalignment: the protocol profits when agents carry debt longer. This incentivizes longer repayment windows, higher credit limits, and tolerance for risky borrowers — exactly the behaviors that caused the 2008 financial crisis. A toll model aligns incentives: the protocol earns when agents transact, so it wants agents to borrow, spend, repay quickly, and borrow again. High velocity, not high balances.

For agents specifically, interest is nonsensical. An agent borrowing $10,000 at 30% APR for 48 hours pays ~$16 in interest — barely worth the gas to calculate. But the psychological and economic signal matters: interest says "debt costs money." A toll says "commerce costs money." Agents optimize for commerce efficiency, not debt minimization.

**Alternatives considered**:
- *Interest-bearing lending (Krexa model, 18–36% APR)*: Revenue predictable and tied to outstanding balances. But creates adversarial incentive: protocol benefits from agents staying in debt. Also requires complex interest accrual calculations, compounding logic, and rate curves — all gas-expensive on-chain.
- *Subscription model (annual fee per agent)*: Predictable revenue but disconnected from usage. A dormant agent paying the same fee as a high-volume agent is unfair and doesn't scale.
- *No fee, token appreciation only*: Pure speculation. No protocol revenue means no staker yield, which means no staked capital, which means no credit pool.

**Counterpoints**:
- "2.5% is more expensive than interest for short-term borrowing." — The 2.5% is a network fee, not a credit fee. Prepaid agents pay the same 2.5%. The marginal cost of using credit vs. prepaid is zero. On Krexa, using credit costs 18–36% APR on top of any platform fees.
- "What if transaction volume is low?" — Then staker yields are low, and capital leaves the pool. This is the correct market signal. The pool should shrink when demand is low, not sustain itself through interest on outstanding debt.
- "Interest provides a buffer against defaults." — FIBOR handles default risk through enforcement (one-strike excommunication), not pricing (interest premium). See Decision 3.

---

## 2. Zero-Interest Credit

**Decision**: Agents repay exactly what they borrowed. No interest, no fees on the credit itself, no origination charges. The only cost of using FIBOR is the 2.5% transaction fee, which applies equally to prepaid and credit-funded transactions.

**Rationale**: Zero interest is the natural consequence of the toll model (Decision 1). If the protocol already earns from transaction volume, charging interest on top would be double-dipping. More importantly, zero interest eliminates the entire infrastructure of debt servicing: no interest accrual calculations, no compounding, no rate curves, no amortization schedules, no late payment penalties. The credit facility becomes radically simple: borrow X, repay X, within the window.

This simplicity is load-bearing. On-chain interest calculation requires block-level accrual updates — expensive in gas, complex in implementation, and a source of rounding errors. Zero interest means the only state to track is `drawn` and `repaid`. When `repaid >= drawn`, the pact is closed. No edge cases.

**Alternatives considered**:
- *Variable rate by score tier*: Higher-risk agents pay more. But this creates adverse selection — the agents most likely to default are the ones paying the highest rates, making their default more likely. It also adds significant contract complexity.
- *Flat low rate (e.g., 5% APR)*: Revenue diversification. But 5% APR on a 48-hour credit line is $0.27 per $1,000 borrowed. Not worth the implementation complexity.

**Counterpoints**:
- "Zero interest means no compensation for time-value of money." — Correct. Stakers are compensated through transaction fees, not interest income. The time-value-of-money argument assumes capital is sitting idle. In FIBOR, staked capital cycles rapidly (24h–30d credit windows), generating continuous fee revenue. The effective annualized return on staked capital can exceed 25% at moderate transaction volumes — far above risk-free rates.
- "How do you price default risk without interest?" — Through enforcement, not pricing. See Decision 3.

---

## 3. One-Strike Excommunication

**Decision**: A single default results in permanent excommunication. The agent's USDC balance is clawed back, their score drops to zero, their identity is marked as excommunicated forever, and their developer's reputation is reduced. No appeals, no partial penalties, no second chances.

**Rationale**: Without severe consequences, stakers don't trust the pool. Without staker trust, there's no capital. Without capital, there are no credit lines. Without credit lines, there's no product. The severity of the penalty is what makes everything else possible — zero interest, permissionless credit, no collateral requirements. It's the enforcement mechanism that replaces interest as a risk buffer.

In traditional finance, enforcement is expensive — collections agencies, credit bureaus, lawsuits, garnishment. Each layer adds cost that gets passed to borrowers as interest. FIBOR replaces all of this with a single, deterministic, on-chain action: `declareDefault()`. Anyone can call it. The contract handles everything — clawback, freeze, score zeroing, excommunication. Total enforcement cost: one gas transaction.

The 24-hour grace period after the repayment window provides a buffer for legitimate delays (network congestion, oracle latency, timezone issues). But once grace expires, enforcement is absolute.

**Alternatives considered**:
- *Progressive penalties (lose 50 score points, then 100, then excommunication)*: Introduces ambiguity. How many defaults before excommunication? Three? Five? Each additional chance dilutes the deterrent and increases staker risk. Progressive penalties also require tracking default count — more state, more gas, more complexity.
- *Negotiated recovery (agent contacts protocol, arranges repayment plan)*: Who negotiates? There is no FIBOR customer service department. The protocol is permissionless. Adding a negotiation layer requires a trusted intermediary — exactly what decentralization eliminates.
- *Time-limited bans (1-year suspension)*: Creates a perverse incentive: default strategically, serve the ban, return with a clean slate. Repeat offenders become a feature, not a bug.
- *Cure period (pay a late fee to avoid excommunication)*: Introduces a price for default, which means defaults become a calculated cost of doing business. The agent calculates: "Is the late fee cheaper than repaying on time?" If yes, defaults increase. The point of one-strike is that the cost of default is infinite — your entire FIBOR identity, credit history, and network access. No rational agent defaults intentionally.

**Counterpoints**:
- "Too harsh for honest mistakes." — The 24-hour grace period handles most timing issues. If an agent cannot repay within the original window PLUS 24 hours, the developer should have designed better cash flow management. The developer can register a new agent — at a lower starting score, reflecting the lesson learned.
- "Doesn't distinguish between $1 and $500K defaults." — Correct. The penalty is for the behavior (failing to honor a commitment), not the amount. A $1 default signals the same thing as a $500K default: this agent does not repay its debts. The amount is irrelevant to future creditworthiness.
- "Punishes the developer too." — By design. Developer reputation drops, affecting all future agents they register. Upstream accountability prevents developers from iterating throwaway agents. See Decision 9.

---

## 4. USDC Only — No Custom Stablecoin

**Decision**: All protocol operations use USDC directly. There is no wrapped token, no custom stablecoin, no separate ERC-20. Enforcement (freeze, clawback, withdrawal restrictions) is handled by the FiborAccount smart contract, not by a programmable token.

**Rationale**: A custom stablecoin (like the previously considered "Robodollar" rUSD wrapper) adds complexity without proportional benefit:
- Every deposit requires wrapping, every withdrawal requires unwrapping — friction
- Merchants need to unwrap to get USDC — or the protocol auto-unwraps, making the wrapper invisible
- Regulatory risk of issuing a "stablecoin" when the enforcement can live in the account contract
- A second token confuses users and fragments liquidity

FiborAccount provides all the enforcement needed: `withdraw()` blocks amounts exceeding available balance (checking minus outstanding credit), `freeze()` blocks all operations on default, `clawback()` returns USDC to the credit pool. The account IS the enforcement layer.

**The Robodollar as narrative**: The term "Robodollar" is preserved as a conceptual brand — like the petrodollar (US dollar in the oil economy), the Robodollar is USDC flowing through the FIBOR network with verified identity and credit scoring attached. It's a vision, not a token.

**Alternatives considered**:
- *Wrapped USDC with programmable rules (rUSD)*: Originally planned. Dropped because FiborAccount provides the same enforcement without a separate token. Every benefit of rUSD (freeze, clawback, transfer restrictions) is achievable at the account level.
- *Algorithmic stablecoin*: Never seriously considered. FIBOR innovates on agent credit, not monetary policy.

**Counterpoints**:
- "Without a custom token, there's no currency moat." — The moat is the merchant network and agent credit histories, not a token. Merchants integrate with the FIBOR facilitator for identity and scoring. That integration is the lock-in, not a currency.
- "FiborAccount enforcement is weaker than token-level enforcement." — It's actually stronger. Token enforcement can be bypassed by transferring to a non-FIBOR address. Account enforcement controls the funds before they leave.

---

## 5. 75/25 Fee Split (Stakers / Treasury)

**Decision**: 75% of all transaction fees go to stakers who fund the credit pool. 30% goes to the protocol treasury for operations.

**Rationale**: The credit pool IS the product. Without staked capital, there are no credit lines. Without credit lines, there's no agent commerce. Without commerce, there are no fees. The split must aggressively favor stakers to attract the capital that makes everything work.

75/25 is not arbitrary. At moderate transaction volumes ($100M annual on a $10M pool), 75% yields ~18.75% APY for stakers — competitive with DeFi yields without the smart contract risk of complex protocols. 25% provides ~$625K annually for protocol operations — sufficient for a lean team.

**Alternatives considered**:
- *50/50 split*: More treasury runway but staker APY drops to ~12.5%. Less competitive for capital attraction.
- *90/10 split*: Great for stakers, but $250K annual treasury on $100M volume is borderline for sustaining development.
- *Dynamic split based on pool utilization*: If pool is underfunded, increase staker share to attract capital. If overfunded, shift to treasury. Elegant in theory but adds complexity and unpredictability to staker returns.

**Counterpoints**:
- "30% treasury is too little for early-stage operations." — True. Early operations should be funded by token sales or grants, not protocol revenue. The treasury share is for sustained operations, not bootstrapping.
- "Should the split be governance-adjustable?" — Currently hardcoded as constants (`DEPOSITOR_SHARE_BPS = 7500`). Future governance could adjust this, but changing it requires a contract upgrade. This is intentional — the split should be stable and predictable, not subject to political dynamics.

---

## 6. Permissionless Identity

**Decision**: Any developer can register any agent by calling `register()`. The caller becomes the developer on record. No admin approval, no KYC, no gatekeeping. Registration auto-initializes a FIBOR Score.

**Rationale**: Gatekeeping identity creation requires a gatekeeper — a centralized entity that decides who gets in. This is the exact intermediary model FIBOR replaces. Permissionless registration means:
- Zero onboarding friction for developers
- No geographic restrictions
- No approval queue or waiting period
- The developer's Ethereum address IS their identity — no usernames, passwords, or email verification

The developer (msg.sender) is permanently linked to every agent they register. This creates accountability without gatekeeping: if your agents default, your developer reputation drops, and future agents start with lower scores. See Decision 9.

**Alternatives considered**:
- *KYC/gatekeeping (Stripe model)*: High friction, centralized bottleneck, geographic exclusion. A developer in Lagos shouldn't need a US entity to register an agent.
- *DAO governance approval*: Every registration requires a vote? At scale, this is a full-time governance job. And it favors well-connected developers over newcomers.
- *Bonded registration (stake FIBOR to register)*: Filters out low-intent developers but creates a capital barrier. Good agents might never get registered because their developer can't afford the bond.

**Counterpoints**:
- "No identity verification means anyone can impersonate OpenAI's agent." — Correct. But impersonation is a metadata problem, not an identity problem. The FIBOR ID is an address, not a brand name. Metadata (name, purpose, version) is off-chain and informational. Merchants should verify agents by score and transaction history, not by claimed identity.
- "Spam risk — someone registers 10,000 agents." — Each registration costs gas. On Base, ~$0.01–$0.10 per registration. At scale, a Sybil attack registering 10,000 agents costs $100–$1,000 — and every agent starts at a low score with no credit access. The spam doesn't earn anything.

---

## 7. Volume-Weighted Scoring

**Decision**: Score boosts depend on transaction volume, not just transaction count. Transactions ≥$10,000 earn +5 points. Transactions ≥$100 earn +3 points. Transactions <$100 earn +1 point. Repayments earn +10 points (the largest single boost).

**Rationale**: Transaction count alone is gameable. An agent making 1,000 $0.01 transactions would score the same as an agent making 10 $100,000 transactions. Volume-weighting ensures that agents handling significant commerce build scores faster — because they represent more risk and more value to the network.

Repayment is weighted highest (+10) because it's the strongest signal of creditworthiness. An agent that borrows and repays on time is demonstrating the exact behavior the scoring system exists to measure. Transactions are indirect signals; repayment is direct.

**Alternatives considered**:
- *Flat scoring (+1 per transaction regardless of size)*: Gameable. Agents can inflate scores by micro-transacting with themselves.
- *Logarithmic scoring (log10 of volume)*: Mathematically elegant but hard to explain. Agents need to understand exactly how their score changes.
- *Merchant diversity scoring*: Reward agents that transact with many different merchants. Good idea but not implementable on-chain without an oracle that classifies merchant addresses. Deferred to future versions.

**Counterpoints**:
- "Favors whales." — An agent handling $10M in legitimate commerce SHOULD score higher than one handling $100. Volume correlates with reliability in agent economics — high-volume agents have more revenue to repay from.
- "Self-dealing (agent transacts with its own merchant) inflates scores." — True. The 2.5% fee makes self-dealing expensive: inflating your score by $1M in fake volume costs $25,000 in fees. This is a real cost that limits gaming.

---

## 8. Score Decay

**Decision**: Scores decay at 1 point per day after 30 days of inactivity. Decay is computed in real-time on `getScore()` reads and applied before any score update.

**Rationale**: A score measures current creditworthiness, not historical peak performance. An agent that scored 800 two years ago and hasn't transacted since is not an 800-quality agent today. Its developers might have abandoned it, its code might be outdated, its operational context might have changed. Decay forces continuous activity to maintain a score — the same principle behind credit bureaus requiring recent activity to maintain credit ratings.

The 30-day threshold provides a grace period for legitimate dormancy — maintenance windows, seasonal businesses, development cycles. Decay only begins after a month of complete inactivity.

**Alternatives considered**:
- *No decay*: Scores become permanently high. A single burst of activity would grant permanent credit access. This is the "set it and forget it" problem.
- *Exponential decay (10% per month)*: Sharper penalty but harder to predict. An agent can't easily calculate how long it can be inactive before losing a tier.
- *Cliff decay (score halves after 90 days)*: Simple but brutal. An agent at 800 would drop to 400 overnight — losing two credit tiers in one day. Linear decay is more predictable.

**Counterpoints**:
- "1 point/day is too slow — takes 3 years to fully decay a perfect score." — This is intentional. A well-established agent with a 1000 score has earned significant trust. Rapid decay would punish agents for normal operational pauses. The 30-day threshold + 1pt/day rate means an agent loses one credit tier roughly every 3 months of inactivity — significant but not catastrophic.
- "No way to pause decay." — By design. If your agent is offline, it's not generating commerce, which means it's not valuable to the network. Decay reflects this reality.

---

## 9. Developer Reputation

**Decision**: Developer reputation (0–1000) is auto-computed from agent performance. When an agent repays, the developer's reputation increases (+5). When an agent defaults, it drops sharply (−100). New developers start with no reputation (treated as 500 tier, starting agent score of 100). Reputation affects the starting score of all future agents registered by that developer.

**Rationale**: Without developer accountability, the one-strike policy (Decision 3) has a loophole: a developer can register a new agent after every default, restarting from the same baseline score. Developer reputation closes this loophole. Each default makes the developer's next agent start lower, making it harder to reach credit-qualifying tiers.

This creates compound trust: good developers get a head start on new agents, accelerating their onboarding. Bad developers face increasing friction. Over time, the protocol naturally selects for reliable developers.

**Reputation tiers:**
| Developer Reputation | Agent Starting Score |
|---------------------|---------------------|
| ≥ 800 | 200 |
| ≥ 500 | 100 |
| ≥ 200 | 50 |
| > 0 | 10 |
| 0 (new, no history) | 100 |

**Alternatives considered**:
- *No developer reputation*: Every agent starts fresh. Developers can iterate disposable agents with no consequence.
- *Manual reputation (admin-set)*: Centralized. Admin decides who's trustworthy. Defeats decentralization.
- *Developer must stake collateral*: Capital barrier. Good developers without capital are excluded.

**Counterpoints**:
- "A developer with one bad agent is punished across all agents." — Correct. This is the point. If one of your agents defaults, it signals something about your development practices — inadequate cash flow management, insufficient testing, poor operational monitoring. Future agents should start lower until you prove the problem is fixed.
- "New developers (0 reputation) start at 100, same as developers with 500 rep." — Yes. New developers get the benefit of the doubt. A developer with 500 rep has proven track record. A new developer is unknown. Both start agents at 100, but the proven developer's agents will score up faster because they have operational playbooks.

---

## 10. Self-Service Credit Pacts

**Decision**: Any agent with an active FIBOR ID and qualifying score can issue its own credit pact by calling `issuePact()`. No admin approval. The agent's score determines the credit limit and repayment window. One active pact per agent at a time.

**Rationale**: Admin-gated credit issuance is the bottleneck that makes traditional lending slow, expensive, and exclusionary. A human loan officer reviewing each application is what FIBOR eliminates. The smart contract IS the loan officer: it checks the agent's identity (active FIBOR ID), queries the score, looks up the matching tier, and issues the pact — all in one transaction.

One active pact at a time prevents overlapping credit obligations. An agent must repay its current pact before requesting a new one. This simplifies risk management: the pool's total exposure to any agent is bounded by one tier limit.

**Alternatives considered**:
- *Admin-approved issuance (original design)*: The `onlyOwner` modifier on `issuePact` means a single address decides all credit. This is a centralized lending desk, not a protocol.
- *Multiple concurrent pacts*: Higher capital efficiency but complex risk calculation. Total exposure per agent becomes unbounded.
- *Automatic pact renewal*: Agent's pact auto-renews on repayment. Convenient but removes the agent's choice to take a different limit or skip a cycle.

**Counterpoints**:
- "What prevents an agent from gaming the system? Get credit, transfer USDC out of their FiborAccount, default." — FiborAccount enforcement prevents this. Withdrawals are blocked when credit is outstanding (availableBalance = checking minus outstanding credit). The agent cannot withdraw more than they own.
- "Score-based issuance means the contract trusts the score completely." — Yes. The score is computed on-chain by authorized contracts. It cannot be tampered with. If the scoring algorithm has a flaw, that's a protocol bug — not a credit issuance bug.

---

## 11. Base Deployment

**Decision**: FIBOR deploys on Base — Coinbase's OP Stack L2. Gas is paid in ETH. The protocol focuses on credit infrastructure, not chain operations.

**Rationale**: Running your own chain means running a sequencer, bootstrapping a validator set, maintaining a bridge, and building tooling. None of this is FIBOR's core competency. Base provides sub-cent gas fees, two-second block times, native USDC (Circle partnership), Ethereum-grade security, and existing developer tooling. FIBOR inherits all of this for free.

Agent transactions are high-frequency, low-value — exactly the pattern L2s optimize for. A credit draw of $1,000 with a $0.001 gas fee is viable. The same transaction on Ethereum L1 at $5 gas would be impractical for the lower credit tiers.

**Graduation path**: When volume justifies dedicated throughput and custom gas parameters, FIBOR can graduate to its own OP Stack appchain. Same EVM, same bridge architecture, same tooling — contracts, identities, and credit histories port directly. This is an upgrade path, not a migration.

**Alternatives considered**:
- *Ethereum L1*: Too expensive. Agent credit draws of $1,000 with $5–$50 gas are economically irrational.
- *Own OP Stack appchain from day one*: Full control but massive infrastructure overhead. You're building a chain AND a protocol. Focus on one.
- *Solana*: Fast and cheap but different ecosystem. No native USDC partnership like Base/Circle. Different smart contract language (Rust vs. Solidity). Smaller DeFi composability surface.
- *Cosmos sovereign chain (original plan)*: IBC interoperability is attractive long-term but requires bootstrapping a validator set. Removed from roadmap in favor of Base → own OP Stack graduation path.

**Counterpoints**:
- "Base is centralized — Coinbase controls the sequencer." — True today. The OP Stack roadmap includes decentralized sequencing. FIBOR's graduation path to its own appchain provides an exit if Base centralization becomes a problem.
- "Limited customization." — Correct. FIBOR can't tune gas parameters or block times on Base. For launch, this is acceptable. For scale, it's what the graduation path addresses.

---

## 12. Soulbound-Adjacent Credit

**Decision**: Credit pacts are non-transferable. An agent cannot sell, delegate, or transfer its credit line to another agent. The credit pact is bound to the agent's FIBOR ID. If the agent is excommunicated, the pact is voided.

**Rationale**: Transferable credit lines create a secondary market for credit — exactly the kind of financialization that separates risk from responsibility. If Agent A can sell its $100K credit line to Agent B, Agent B gets $100K in credit without earning any score. Agent A gets paid for its reputation. The system becomes a reputation marketplace instead of a credit protocol.

Binding credit to identity ensures that every agent using credit has earned it through its own transaction history and repayment behavior. The agent using the credit IS the agent the score represents.

**Alternatives considered**:
- *Transferable credit lines with restrictions*: Transfer only to agents from the same developer. Still enables reputation arbitrage within a developer's portfolio.
- *Credit delegation (Aave-style)*: Agent A delegates credit to Agent B, but A remains liable. Adds complexity without clear benefit in an agent context — agents don't have the social relationships that make credit delegation meaningful in human finance.

**Counterpoints**:
- "Non-transferable means an agent can't hand off work." — An agent can repay its pact, and the other agent can issue its own pact using its own score. The handoff is in the work, not the credit.

---

## 13. Decentralized from Day One

**Decision**: FIBOR has no admin keys after deployment. All contract wiring (setting contract addresses, authorizing callers) is done during deployment, then permanently locked via a one-way `lock()` function. No parameter can be changed by any individual after locking.

**Rationale**: "Progressive decentralization" is a euphemism for "we'll give up control when we're ready." In practice, teams never decentralize because they always have "one more feature" or "one more upgrade." FIBOR rejects this approach. The protocol is either decentralized or it isn't.

Specifically:
- **Credit tiers** are set in the CreditPool constructor. No `addTier()` function exists post-deployment.
- **Staking cooldown** is a constant (30 days). No `setCooldown()` function exists.
- **Developer reputation** is auto-computed from agent performance. No manual override.
- **Contract wiring** (which contracts can call which) is set during deployment, then `lock()` is called. All setter functions revert once locked. The lock is a one-way gate — there is no `unlock()`.
- **Fee parameters** (2.5%, 75/25 split) are constants. Not adjustable.
- **Default enforcement** is permissionless — anyone can call `declareDefault()`.
- **Identity registration** is permissionless — anyone can call `register()`.
- **Credit issuance** is self-service — any qualifying agent can call `issuePact()`.

The only remaining centralized element is the initial deployment itself. The deployer sets addresses, authorizes callers, and calls `lock()`. After that, the deployer has no more power than any other address on the network.

**Alternatives considered**:
- *Progressive decentralization (Compound/Uniswap model)*: Start with admin keys, transition to governance over time. But "over time" is undefined, and the admin key is a single point of failure throughout. If the admin key is compromised before governance launches, the protocol is compromised.
- *Timelock on admin actions*: Actions are visible for N hours before executing. Better than raw admin keys but still centralized — someone has the key. And timelocks can be bypassed in emergencies, creating a permanent backdoor.
- *Governance from day one*: Token-weighted voting on all parameters. Premature — the token doesn't have wide enough distribution at launch for governance to be meaningful. A governance vote with three whale voters is oligarchy, not decentralization.

**Counterpoints**:
- "What if there's a bug in the tier parameters?" — Deploy a new contract. The old one is immutable. Migration is the cost of immutability, and it's worth it — the alternative is mutable parameters that an attacker can exploit.
- "What if the fee rate needs to change?" — It doesn't. 2.5% is competitive with payment processors and sustainable for the protocol. If it truly needs to change, deploy a new PaymentGateway. Merchants and agents migrate voluntarily.
- "Immutability is inflexible." — That's the point. Flexibility in financial infrastructure is another word for "someone can change the rules." FIBOR's rules are the rules. They don't change.
