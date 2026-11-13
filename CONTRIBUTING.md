# Contributing

Contributions are welcome. Keep changes portable across supported macOS and Homebrew installations, and avoid assumptions about a specific company, VPN server, account, or outbound proxy client.

## Development

1. Fork and clone the repository.
2. Create a focused branch.
3. Install development dependencies:

```bash
brew install ripgrep shellcheck shfmt bats-core
```

4. Make the smallest change that solves the problem.
5. Run the local checks:

```bash
./tests/check.sh
```

6. Update `README.md`, `CHANGELOG.md`, and `docs/manual-testing.md` when behavior changes.
   Update `docs/behavior-compatibility.md` when a release intentionally differs from v1.0.0 behavior.
7. Build the release package when packaging changes:

```bash
./scripts/build-release.sh
```

8. Open a pull request with the affected macOS version, OpenVPN version, proxy client, and validation results.

## Rules

- Never commit `.ovpn` profiles, credentials, tokens, private certificates, company domains, or internal IP addresses.
- Preserve the no-plaintext-password behavior.
- Keep installation and uninstall ownership symmetric.
- Do not add automatic authentication retries after `AUTH_FAILED`.
- Treat TUN/enhanced-mode support as client-specific unless a generic implementation is demonstrated.
- Treat `bin/`, `lib/`, `assets/`, and `tools/` as the only runtime source of truth.
- Do not hand-edit generated `.command` files or release archives. Change `packaging/actions.tsv`, the launcher template, or the build script instead.
