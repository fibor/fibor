# FIBOR Protocol

**The First International Bank of Robot.**

Open-source smart contracts for the bank and credit card network for intelligent machines.

**[Thesis](./thesis.md)** · **[Whitepaper](./WHITEPAPER.md)** · **[Design Decisions](./DESIGN.md)** · **[Audit Report](./AUDIT.md)** · **[Security](./SECURITY.md)** · **[Contributing](./CONTRIBUTING.md)**

**Live App:** [fibor.xyz](https://fibor.xyz) · **Testnet:** Base Sepolia (84532)

## What is FIBOR?

FIBOR is a decentralized bank and credit card network for autonomous AI agents. Every agent gets a bank account, a credit score, and access to zero-interest credit — all enforced by smart contracts on Base.

- **FIBOR ID** — Permissionless onchain identity
- **FiborAccount** — Smart contract bank account (checking + savings + auto-repayment)
- **FIBOR Score** — Multiplicative credit scoring (volume × repayments × months)
- **FIBOR Credit** — Zero-interest credit lines, capped at 25% of proven volume
- **x402 Facilitator** — Drop-in identity + fraud protection for agent payments

## Deployed Contracts (Base Sepolia)

| Contract | Address |
|---|---|
| MockUSDC | `0xa714e359a92716f6c0a4c5031cb9922aa5e64eff` |
| FIBORToken | `0x28f8050adf4bd1dcde4ea6d0a2252aa18a132f07` |
| FiborScore | `0x229e1d18c266216fe5a4d6ec039f35a902368624` |
| FiborID | `0xa2dd2c0b37d81915d25601147b5607842ca205bc` |
| CreditPool | `0xac8fee7730a72dac5e16e4e9b5f1d31c967c69ed` |
| PaymentGateway | `0x1d180da78df91a90e15651141708d4ef66485a57` |
| RevenueDistributor | `0x8ce79fb30fb367f00c56b92f633ae6e45396101f` |
| FiborAccountFactory | `0x1fe6dca24de196fe4609384ebc1c87fe32daf5fd` |

## Smart Contracts

| Contract | Purpose |
|---|---|
| `FIBORToken` | ERC-20 governance token. Fixed 1B supply, no inflation. |
| `FiborID` | Permissionless identity registry. Deploys FiborAccount on register. |
| `FiborScore` | Score = totalVolumeRepaid x totalRepayments x monthsActive. Credit limit = 25% of proven volume. |
| `FiborAccount` | Bank account for robots. Checking (liquid) + savings (earns yield). Auto-repay on deposit. Guardian/sovereignty. |
| `FiborAccountFactory` | CREATE2 deterministic deployment, called by FiborID. |
| `CreditPool` | Savings-funded credit facility. Zero interest. 30-day pacts. One-strike default enforcement. |
| `PaymentGateway` | 1% merchant fee + 1.5% agent fee = 2.5% total. |
| `RevenueDistributor` | 70% to savings depositors, 30% to protocol treasury. |

## Testing

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install dependencies
forge install OpenZeppelin/openzeppelin-contracts --no-git
forge install foundry-rs/forge-std --no-git

# Build
forge build

# Test (16 tests)
forge test
```

## Deploy

```bash
export PRIVATE_KEY=0x...
forge script script/Deploy.s.sol:DeployFibor \
  --rpc-url https://sepolia.base.org \
  --private-key $PRIVATE_KEY \
  --broadcast
```

## OWS Integration

FIBOR includes an [Open Wallet Standard](https://openwallet.sh) policy for agent wallets:

```bash
# Create an agent wallet
ows wallet create --name "my-agent"

# Register the policy
ows policy create --file ows/fibor-policy.json
```

The `ows/fibor-policy.py` enforces FIBOR-specific rules before signing: checks excommunication status, credit utilization, and score thresholds.

## Fee Structure

| Who | Fee | What they get |
|---|---|---|
| Merchant | 1% | Identity verification, score checks, fraud protection |
| Agent | 1.5% | Zero-interest credit, bank account, financial identity |
| Savings depositors | — | 70% of all fees |
| Treasury | — | 30% of all fees |

## Architecture

```
contracts/
├── FIBORToken.sol          — ERC-20 governance token (1B fixed supply)
├── FiborID.sol             — Identity registry (agent + human registration)
├── FiborScore.sol          — Multiplicative scoring + auto dev reputation
├── FiborAccount.sol        — Bank account (checking + savings + credit + sovereignty)
├── FiborAccountFactory.sol — CREATE2 deterministic account deployment
├── CreditPool.sol          — Credit facility (savings-funded, zero interest)
├── PaymentGateway.sol      — Transaction processing (1% + 1.5% fees)
└── RevenueDistributor.sol  — Fee distribution (70% savings / 30% treasury)
```

## License

MIT
