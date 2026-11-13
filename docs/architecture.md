# Architecture

OpenVPN Proxy Bridge uses a single command-line application with generated Finder launchers. Runtime source files are maintained once and copied into the protected installation directory when needed.

## Source layout

| Area | Responsibility |
|---|---|
| `bin/openvpn-proxy-bridge` | Snapshot execution, module loading, and CLI entry point |
| `lib/config.sh` | Stable paths, service label, state files, and timeouts |
| `lib/common.sh` | Privilege boundary, console user, temporary execution, and metadata writing |
| `lib/proxy.sh` | SOCKS5 discovery, manual proxy validation, and proxy session cleanup |
| `lib/openvpn.sh` | Credential handling and profile transformation |
| `lib/homebrew.sh` | OpenVPN installation ownership and dependency cleanup |
| `lib/service.sh` | LaunchDaemon lifecycle, process cleanup, connection waiting, and retry policy |
| `lib/commands.sh` | User-visible command orchestration |
| `assets/` | Files installed for background runtime execution |
| `tools/` | Structured Python helpers |
| `packaging/` | Release-only Finder launcher definitions |

Modules define functions only. Loading a module must not change system state.

Python 3.8 or newer is a runtime dependency. Setup discovers a compatible system or Homebrew interpreter and stores its absolute path in root-owned `install.meta`; the LaunchDaemon uses that recorded path rather than inheriting a shell `PATH`.

## Runtime lifecycle

`setup` copies and filters the selected profile, stores root-only credentials, writes ownership metadata, installs runtime assets, writes the LaunchDaemon plist, and leaves the service disabled.

`start` creates a snapshot of the complete runtime source, enables and bootstraps the LaunchDaemon, then waits for `Initialization Sequence Completed`. A missing TLS response is cleaned and retried once. `AUTH_FAILED` is never retried automatically.

The LaunchDaemon runs `assets/run-openvpn.sh`. It discovers the current SOCKS5 endpoint, expands every VPN hostname into explicit IPv4 remotes, appends the single runtime-owned server poll timeout, starts OpenVPN, and records the generated endpoint count. The foreground CLI derives its transport wait budget from that count. When the proxy endpoint changes, the monitor terminates OpenVPN, cleans the old proxy UDP connection, and rebuilds the connection.

`stop` disables and unloads the LaunchDaemon, terminates monitor and OpenVPN processes, removes transient state and routes through OpenVPN process shutdown, cleans compatible proxy UDP sessions, and waits for the baseline 8-second release window before reporting completion.

`uninstall` always runs the same complete stop path before deleting the installation directory and plist. Homebrew removal follows the ownership metadata written by `setup`.

## Stable compatibility contract

- Installation directory: `/Library/Application Support/Proxy-OpenVPN`
- LaunchDaemon label: `com.local.proxy-openvpn`
- Finder launcher names and user-visible command behavior
- Root-only credential and configuration permissions
- Installation does not connect automatically
- A stopped service remains stopped across macOS restarts

## Generated artifacts

Finder `.command` files are release artifacts. `scripts/generate-launchers.sh` renders them from `packaging/actions.tsv` and `packaging/launcher.command.template`.

`scripts/build-release.sh` creates the complete user package under `dist/`. Generated files and archives must never be edited manually or committed as runtime source.
