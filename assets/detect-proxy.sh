#!/bin/bash
set -euo pipefail

DIR="${1:-/Library/Application Support/Proxy-OpenVPN}"
SCUTIL_BIN='/usr/sbin/scutil'
NC_BIN='/usr/bin/nc'

if [ "${OPB_TEST_MODE:-0}" = 1 ]; then
  SCUTIL_BIN="${OPB_SCUTIL_BIN:-$SCUTIL_BIN}"
  NC_BIN="${OPB_NC_BIN:-$NC_BIN}"
fi

if [ -s "$DIR/proxy.conf" ]; then
  read -r host port <"$DIR/proxy.conf"
else
  proxy="$($SCUTIL_BIN --proxy)"
  enabled="$(printf '%s\n' "$proxy" | awk -F': ' '/SOCKSEnable/{gsub(/ /,"",$2); print $2; exit}')"
  host="$(printf '%s\n' "$proxy" | awk -F': ' '/SOCKSProxy/{gsub(/^ +| +$/,"",$2); print $2; exit}')"
  port="$(printf '%s\n' "$proxy" | awk -F': ' '/SOCKSPort/{gsub(/ /,"",$2); print $2; exit}')"
  [ "$enabled" = 1 ] || exit 1
fi

case "$host" in
  127.0.0.1 | localhost | ::1) ;;
  *) exit 1 ;;
esac

[[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || exit 1
"$NC_BIN" -z -w 2 "$host" "$port" >/dev/null 2>&1 || exit 1
printf '%s %s\n' "$host" "$port"
