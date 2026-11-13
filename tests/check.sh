#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_MONITOR="$(mktemp "${TMPDIR:-/tmp}/openvpn-proxy-bridge-monitor.XXXXXX")"
trap 'rm -f "$TMP_MONITOR"' EXIT

for script in "$ROOT"/*.command; do
  bash -n "$script"
done

awk '
  /cat > "\$DIR\/run-openvpn\.sh" <<SH/ { inside=1; next }
  inside && /^SH$/ { exit }
  inside { print }
' "$ROOT/setup-company-vpn.command" | sed 's/\\\$/\$/g' > "$TMP_MONITOR"

bash -n "$TMP_MONITOR"
python3 "$ROOT/tests/validate_embedded.py"

if rg -n -i 'iyunquna|yqn-vpn|/Users/[^/]+/|auth_token|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY' "$ROOT" \
  --glob '!tests/check.sh' --glob '!.git/**'; then
  echo 'Potential private or environment-specific data found.' >&2
  exit 1
fi

echo 'All checks passed.'
