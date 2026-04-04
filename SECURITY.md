# Security Policy

## Reporting Vulnerabilities

**Do not open a public GitHub issue for security vulnerabilities.**

Email security reports to: **security@fibor.xyz**

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

## Scope

Reports are welcome for:
- Smart contract vulnerabilities (reentrancy, access control, integer overflow, logic errors)
- Economic attacks (fee manipulation, score gaming, pool draining)
- Design flaws that undermine protocol guarantees (solvency, enforcement, identity)
- Cryptographic weaknesses
- Denial of service vectors

## Response Timeline

- **48 hours**: Initial acknowledgment
- **1 week**: Status update with severity assessment
- **Resolution**: Depends on severity. Critical issues are prioritized above all other work.

## Known Limitations

- Contracts have not been independently audited. See [AUDIT.md](./AUDIT.md) for known issues.
- No formal verification has been performed.
- The protocol is not yet deployed to mainnet.

## Disclosure

We follow responsible disclosure. We will coordinate with reporters on public disclosure timing after a fix is deployed.
