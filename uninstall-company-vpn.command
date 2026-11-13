#!/bin/bash
set -u
main="$(cd "$(dirname "$0")" && pwd)/setup-company-vpn.command"
snapshot="$(mktemp "${TMPDIR:-/tmp}/proxy-openvpn.XXXXXX")"
trap 'rm -f "$snapshot"' EXIT
if ! cp "$main" "$snapshot" || ! chmod 700 "$snapshot"; then
  echo '无法创建脚本安全运行副本，请确认工具包文件完整。' >&2
  exit 1
fi
/bin/bash "$snapshot" uninstall
