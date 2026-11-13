# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/qybgh/openvpn-proxy-bridge/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/qybgh/openvpn-proxy-bridge/releases/tag/v1.0.0
