# Security Policy

## Reporting a vulnerability

Please use GitHub private vulnerability reporting when available. Do not open a public issue containing credentials, VPN profiles, private certificates, company domains, internal addresses, or exploitable details.

Include the affected version, macOS version, reproduction steps, expected behavior, and impact. Redact all secrets before attaching logs.

## Security boundaries

- VPN credentials are stored in a root-only file with mode `600`.
- Runtime configuration and logs are stored under `/Library/Application Support/Proxy-OpenVPN`.
- The project does not read credentials saved by OpenVPN Connect.
- The project accepts only loopback SOCKS5 endpoints.
- The project does not fall back to a direct VPN connection when the proxy is unavailable.
