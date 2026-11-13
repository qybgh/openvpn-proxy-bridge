#!/bin/bash
set -euo pipefail

ROOT="${1:-}"
[ -d "$ROOT" ] || {
  echo 'usage: privacy-scan.sh DIRECTORY' >&2
  exit 2
}

command -v rg >/dev/null 2>&1 || {
  echo 'ripgrep is required for privacy scanning.' >&2
  exit 1
}

forbidden_content='iyunquna|yqn-vpn|/Users/[^/]+/|auth_token|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|BEGIN OpenVPN Static key V1|<[[:space:]]*(tls-auth|tls-crypt|secret)[[:space:]]*>'

if rg -n -i "$forbidden_content" "$ROOT" \
  --glob '!scripts/privacy-scan.sh' --glob '!.git/**'; then
  echo 'Potential private key or environment-specific data found.' >&2
  exit 1
fi

if find "$ROOT" -type f \( -name '*.ovpn' -o -name 'auth.txt' -o -name '*.key' -o -name '*.p12' -o -name '*.pfx' \) -print -quit | grep -q .; then
  echo 'Sensitive profile or credential file found.' >&2
  exit 1
fi
