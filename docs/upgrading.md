# Upgrading

## From v1.0.0 to v1.1.0

v1.1.0 changes the internal package layout and does not support an in-place upgrade.

1. Keep the v1.0.0 package until uninstall completes.
2. Run the v1.0.0 `uninstall-company-vpn.command`.
3. Confirm the old connection is stopped and `/Library/Application Support/Proxy-OpenVPN` has been removed.
4. Download and extract the v1.1.0 Release package.
5. Run the v1.1.0 `setup-company-vpn.command` and select the original `.ovpn` file.
6. Run `start-company-vpn.command` when installation finishes.

The uninstall does not remove the original `.ovpn` file or OpenVPN Connect. Credentials must be entered again because the protected v1.0.0 credential file is intentionally deleted during uninstall.

Do not copy v1.1.0 files over an active v1.0.0 package or installation directory.
