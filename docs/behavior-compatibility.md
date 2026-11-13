# v1.0.0 and v1.1.0 behavior compatibility

v1.1.0 changes the source and release architecture while preserving the v1.0.0 user interface and installed service contract.

## Compatibility matrix

| Area | v1.0.0 | v1.1.0 | Result |
|---|---|---|---|
| Finder entry names | Seven `.command` files | Same seven names, generated for Release | Compatible |
| Installation directory | `/Library/Application Support/Proxy-OpenVPN` | Unchanged | Compatible |
| LaunchDaemon label | `com.local.proxy-openvpn` | Unchanged | Compatible |
| Installation behavior | Installs configuration and remains disconnected | Unchanged | Compatible |
| Homebrew ownership | Records installed/pre-existing OpenVPN and dependencies | Same metadata and uninstall policy | Compatible |
| Profile transformation | Removes managed directives and appends protected auth/cipher/retry settings | Preserves those settings; runtime generation owns endpoint expansion and polling timeout | Compatible refactor |
| Runtime remote resolution | Leaves the VPN hostname in `runtime.ovpn` | Expands the hostname to all unique IPv4 addresses at each connection attempt | Intentional reliability improvement |
| SOCKS5 discovery | macOS system SOCKS proxy or manual loopback endpoint | Same rules in an independent runtime asset | Compatible |
| Runtime configuration | Adds current `socks-proxy` and UDP exit notification | Unchanged | Compatible |
| Start idempotency | Reuses connected/in-progress session and cleans stale attempts | Unchanged | Compatible |
| Missing TLS response | One delayed retry | Unchanged | Compatible |
| `AUTH_FAILED` | Stops without automatic authentication retry | Unchanged | Compatible |
| Proxy endpoint change | Stops OpenVPN and rebuilds with the new endpoint | Unchanged | Compatible |
| Status output | Service, tunnel, proxy, and recent logs | Unchanged | Compatible |
| Credential update | Atomic replacement followed by reconnect | Unchanged, with explicit failure short-circuit | Compatible improvement |
| Stop cleanup | Processes, transient files, routes, and compatible proxy UDP sessions | Same cleanup plus the baseline 8-second release window | Compatible improvement |
| Multi-address VPN host | OpenVPN could remain on one silent resolved address until the external guard stopped it | Uses explicit resolved remotes, a 5-second per-endpoint poll timeout, and an endpoint-count-derived outer budget | Intentional reliability improvement |
| Uninstall | Runs complete stop, removes installation, applies Homebrew ownership policy | Unchanged, including the release-window wait | Compatible improvement |
| Script replacement while running | Single-script snapshot | Complete runtime source snapshot | Stronger equivalent protection |

## Intentional internal differences

- The monolithic installer is replaced by one CLI and domain-specific modules.
- Runtime scripts, plist, and Python helpers are independent source files instead of heredocs.
- Finder launchers are generated only for Release packages.
- The OpenVPN binary path is stored in root-owned `install.meta`; it still uses Homebrew's stable `opt/openvpn` path.
- Failed installation now rolls back partial files and plist state.
- Command wrappers use explicit macOS argument ordering; recursive ownership uses `chown -R root:wheel PATH`.
- Tests can inject temporary paths and mock system commands with `OPB_TEST_MODE=1`; production ignores these overrides.

## Stop semantics

The local tool can guarantee that its LaunchDaemon, processes, routes, transient files, and supported proxy connection entries are removed. It cannot directly observe or force the release of remote VPN server or NAT state.

v1.1.0 keeps the baseline stop release window but treats a silent endpoint as an endpoint-selection problem. OpenVPN gets 5 seconds per resolved address and the outer connection guard allows 35 seconds for endpoint rotation. A second start attempt still re-resolves the hostname once.

If both rounds exhaust every resolved endpoint while the local SOCKS5 listener remains available, the tool reports the outbound proxy node's UDP path as the likely failure. Restarting or switching a third-party proxy node remains a user action and is not automated by this project.

The outbound proxy client must not route the resolved VPN server IP addresses to a direct or blocked outbound. Such a rule overrides the intended SOCKS5 proxy chain and can make every VPN endpoint appear silent even though the local SOCKS5 listener is healthy. An explicit proxy rule is unnecessary when the client's default route already uses the proxy.

Company application domains have the opposite requirement when applications use the macOS system proxy. They must use the proxy client's direct outbound so the connection returns to the local network stack and follows the company IP routes installed on the OpenVPN `utun`. Without this rule, browser traffic can leave through the outbound proxy node while SSH remains healthy because SSH normally bypasses the system proxy.

v1.1.0 resolves VPN hostnames locally and writes explicit IP remotes into `runtime.ovpn`. As a result, a broad company-domain direct rule does not match the VPN transport because the proxy receives an IP destination with no hostname metadata.

## Validation evidence

- v1.0.0 and v1.1.0 preserve the same authentication, cipher, compression, and retry directives; v1.1.0 intentionally adds the endpoint polling timeout.
- Runtime remote expansion is unit-tested for multiple addresses, duplicate removal, literal IPv4 preservation, and DNS failure fallback.
- ShellCheck, shfmt, plist validation, privacy scanning, Python unit tests, Bats behavior tests, release build, SHA-256 verification, and a release-path-with-spaces smoke test pass locally.
- Real-device testing remains required before the branch is pushed or a v1.1.0 artifact is published.
