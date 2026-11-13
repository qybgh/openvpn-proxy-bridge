# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-11-13

### Changed

- Refactored the monolithic installer into one CLI with domain-specific Shell modules.
- Moved the runtime monitor, proxy detector, LaunchDaemon plist, and Python helpers into independent source files.
- Generate Finder `.command` launchers only when building a release package.
- Added reproducible release packaging with SHA-256 output.
- Added ShellCheck, shfmt, Bats, Python unit tests, plist validation, privacy scanning, and draft release automation.
- Documented the required uninstall-and-reinstall upgrade path from v1.0.0.
- Added fast failover across multiple addresses returned for a VPN hostname with a 5-second per-endpoint poll timeout and a transport budget derived from the generated endpoint count.
- Expanded VPN hostnames into all unique IPv4 endpoints for each connection attempt so failover does not depend on resolver address ordering.
- Added explicit Python 3.8+ discovery, validation, and interpreter-path persistence for runtime helpers.
- Restricted release packaging to explicit runtime files and unique archive entries so build-time Python bytecode cannot enter published artifacts.

## [1.0.0] - 2026-11-13

### Added

- Install and manage Homebrew OpenVPN from Finder-friendly macOS scripts.
- Route the OpenVPN transport through an automatically detected local SOCKS5 proxy.
- Preserve split routing so company networks use OpenVPN while normal proxy traffic stays with the outbound proxy client.
- Start, stop, status, credential update, proxy configuration, and clean uninstall commands.
- Detect local proxy port changes and rebuild the OpenVPN tunnel.
- Clean stale processes, runtime files, routes, and compatible proxy UDP sessions.
- Retry once when the VPN server does not return an initial TLS packet.
- Protect credentials and configuration in a root-only directory.

[Unreleased]: https://github.com/qybgh/openvpn-proxy-bridge/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/qybgh/openvpn-proxy-bridge/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/qybgh/openvpn-proxy-bridge/releases/tag/v1.0.0
