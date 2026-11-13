# Contributing

Contributions are welcome. Keep changes portable across supported macOS and Homebrew installations, and avoid assumptions about a specific company, VPN server, account, or outbound proxy client.

## Development

1. Fork and clone the repository.
2. Create a focused branch.
3. Make the smallest change that solves the problem.
4. Run the local checks:

```bash
./tests/check.sh
```

5. Update `README.md`, `CHANGELOG.md`, and `docs/manual-testing.md` when behavior changes.
6. Open a pull request with the affected macOS version, OpenVPN version, proxy client, and validation results.

## Rules

- Never commit `.ovpn` profiles, credentials, tokens, private certificates, company domains, or internal IP addresses.
- Preserve the no-plaintext-password behavior.
- Keep installation and uninstall ownership symmetric.
- Do not add automatic authentication retries after `AUTH_FAILED`.
- Treat TUN/enhanced-mode support as client-specific unless a generic implementation is demonstrated.
