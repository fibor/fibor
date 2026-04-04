# Contributing to FIBOR

## Reporting Issues

Open an issue on GitHub for bugs, feature requests, or documentation improvements. For security vulnerabilities, see [SECURITY.md](./SECURITY.md).

## Pull Request Workflow

1. Fork the repository
2. Create a feature branch from `main`
3. Make your changes
4. Write or update tests
5. Ensure all tests pass
6. Submit a pull request with a clear description

## Development Setup

### Frontend (Docs + dApp)

```bash
bun install
bun run dev
```

Open [http://localhost:3000](http://localhost:3000).

### Smart Contracts

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Build contracts
forge build

# Run tests
forge test
```

## Code Style

### Solidity
- Solidity 0.8.24+
- OpenZeppelin 5.x
- Follow [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html)
- NatSpec documentation on all public functions
- Use `SafeERC20` for all token transfers
- Use `ReentrancyGuard` on all state-changing external functions

### TypeScript / React
- Next.js 15, React 19, Tailwind CSS 4
- Functional components only
- No `any` types

## Security

- Do not submit PRs that add admin keys, backdoors, or mutable parameters that should be immutable
- Do not submit PRs that weaken the Lockable pattern
- Read [DESIGN.md](./DESIGN.md) before proposing architectural changes

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
