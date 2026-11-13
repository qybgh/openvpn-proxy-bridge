#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKIP_BUILD=0

if [ "${1:-}" = '--skip-build' ]; then
  SKIP_BUILD=1
fi

TEMP_ROOT="$(mktemp -d /tmp/openvpn-proxy-bridge-check.XXXXXX)"
trap 'rm -rf "$TEMP_ROOT"' EXIT INT TERM

shell_sources=(
  "$ROOT/bin/openvpn-proxy-bridge"
  "$ROOT/lib/"*.sh
  "$ROOT/assets/"*.sh
  "$ROOT/scripts/"*.sh
  "$ROOT/tests/check.sh"
)

for script in "${shell_sources[@]}"; do
  bash -n "$script"
done

"$ROOT/scripts/generate-launchers.sh" "$TEMP_ROOT/launchers"
for launcher in "$TEMP_ROOT/launchers/"*.command; do
  bash -n "$launcher"
done

plutil -lint "$ROOT/assets/com.local.proxy-openvpn.plist" >/dev/null
python3 -m unittest discover -s "$ROOT/tests/python" -p 'test_*.py'

command -v shellcheck >/dev/null 2>&1 || {
  echo 'shellcheck is required. Install it with: brew install shellcheck' >&2
  exit 1
}
shellcheck -x -P "$ROOT" "${shell_sources[@]}" "$TEMP_ROOT/launchers/"*.command

command -v shfmt >/dev/null 2>&1 || {
  echo 'shfmt is required. Install it with: brew install shfmt' >&2
  exit 1
}
shfmt -d -i 2 -ci "${shell_sources[@]}" "$TEMP_ROOT/launchers/"*.command

command -v bats >/dev/null 2>&1 || {
  echo 'bats is required. Install it with: brew install bats-core' >&2
  exit 1
}
bats "$ROOT/tests/bats"

"$ROOT/scripts/privacy-scan.sh" "$ROOT"

privacy_fixture="$TEMP_ROOT/privacy-fixture"
mkdir -p "$privacy_fixture"
printf '%s%s\n' '-----BEGIN PRIVATE ' 'KEY-----' >"$privacy_fixture/secret.txt"
if "$ROOT/scripts/privacy-scan.sh" "$privacy_fixture" >/dev/null 2>&1; then
  echo 'Privacy scanner did not reject a private key marker.' >&2
  exit 1
fi

if [ "$SKIP_BUILD" -eq 0 ]; then
  "$ROOT/scripts/build-release.sh" --skip-checks --output "$TEMP_ROOT/dist" >/dev/null
  archive="$TEMP_ROOT/dist/openvpn-proxy-bridge-$(tr -d '[:space:]' <"$ROOT/VERSION").tar.gz"
  [ -s "$archive" ]
  [ -s "$archive.sha256" ]
  archive_entries="$TEMP_ROOT/archive-entries.txt"
  tar -tzf "$archive" >"$archive_entries"
  grep -q '/setup-company-vpn.command$' "$archive_entries"
  grep -q '/libexec/bin/openvpn-proxy-bridge$' "$archive_entries"
  if sort "$archive_entries" | uniq -d | grep -q .; then
    echo 'Release archive contains duplicate paths.' >&2
    sort "$archive_entries" | uniq -d >&2
    exit 1
  fi
  if grep -E -q '(^|/)(__pycache__/|[^/]+\.pyc$)' "$archive_entries"; then
    echo 'Release archive contains Python bytecode.' >&2
    grep -E '(^|/)(__pycache__/|[^/]+\.pyc$)' "$archive_entries" >&2
    exit 1
  fi
  checksum_name="$(awk '{print $2}' "$archive.sha256")"
  [ "$checksum_name" = "$(basename "$archive")" ]

  second_dist="$TEMP_ROOT/dist-second"
  "$ROOT/scripts/build-release.sh" --skip-checks --output "$second_dist" >/dev/null
  cmp "$archive" "$second_dist/$(basename "$archive")"
fi

echo 'All checks passed.'
