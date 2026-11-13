#!/bin/bash
set -u

DIR="${1:-/Library/Application Support/Proxy-OpenVPN}"
LOG="$DIR/openvpn.log"
child=''

if [ ! -r "$DIR/install.meta" ]; then
  printf '%s missing install metadata\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>"$LOG"
  exit 1
fi

# install.meta is root-owned and mode 600.
# shellcheck disable=SC1091
source "$DIR/install.meta"

if [ -z "${OPENVPN_BIN:-}" ] || [ ! -x "$OPENVPN_BIN" ]; then
  printf '%s OpenVPN binary is unavailable\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>"$LOG"
  exit 1
fi

if [ -z "${PYTHON_BIN:-}" ] || [ ! -x "$PYTHON_BIN" ]; then
  for candidate in /usr/bin/python3 /opt/homebrew/bin/python3 /usr/local/bin/python3; do
    if [ -x "$candidate" ] && "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 8) else 1)' >/dev/null 2>&1; then
      PYTHON_BIN="$candidate"
      break
    fi
  done
fi

if ! [[ "${SERVER_POLL_TIMEOUT:-}" =~ ^[0-9]+$ ]] || [ "$SERVER_POLL_TIMEOUT" -lt 1 ]; then
  SERVER_POLL_TIMEOUT=5
fi

if [ -z "${PYTHON_BIN:-}" ] || [ ! -x "$PYTHON_BIN" ]; then
  printf '%s Python 3.8 or newer is unavailable\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>"$LOG"
  exit 1
fi

cleanup() {
  rm -f "$DIR/connected.state" "$DIR/transport.state" "$DIR/attempt.started"
  if [ -n "$child" ] && kill -0 "$child" 2>/dev/null; then
    kill -TERM "$child" 2>/dev/null || true
    i=0
    while kill -0 "$child" 2>/dev/null && [ "$i" -lt 50 ]; do
      sleep 0.2
      i=$((i + 1))
    done
    if kill -0 "$child" 2>/dev/null; then
      kill -KILL "$child" 2>/dev/null || true
    fi
    wait "$child" 2>/dev/null || true
  fi
}

trap cleanup EXIT
trap 'exit 0' TERM INT

printf '%s proxy monitor started\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>"$LOG"

while :; do
  proxy="$("$DIR/detect-proxy.sh" "$DIR" 2>/dev/null || true)"
  if [ -z "$proxy" ]; then
    sleep 5
    continue
  fi

  read -r host port <<<"$proxy"
  printf '%s %s\n' "$host" "$port" >"$DIR/current-proxy.state"
  chmod 600 "$DIR/current-proxy.state"
  "$PYTHON_BIN" "$DIR/resolve-remotes.py" "$DIR/base.ovpn" "$DIR/runtime.ovpn" "$SERVER_POLL_TIMEOUT"
  printf 'socks-proxy %s %s\n' "$host" "$port" >>"$DIR/runtime.ovpn"
  if grep -Eq '^[[:space:]]*proto[[:space:]]+udp(4|6)?([[:space:]]|$)' "$DIR/base.ovpn" && ! grep -Eq '^[[:space:]]*explicit-exit-notify([[:space:]]|$)' "$DIR/base.ovpn"; then
    printf 'explicit-exit-notify 3\n' >>"$DIR/runtime.ovpn"
  fi
  chmod 600 "$DIR/runtime.ovpn"
  rm -f "$DIR/connected.state" "$DIR/transport.state" "$DIR/failure.state" "$DIR/remote-count.state"
  date +%s >"$DIR/attempt.started"
  touch "$LOG"
  start_line="$(wc -l <"$LOG" | tr -d ' ')"
  printf '%s using SOCKS5 %s:%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$host" "$port" >>"$LOG"

  "$OPENVPN_BIN" --config "$DIR/runtime.ovpn" --log-append "$LOG" &
  child=$!
  restart=0

  while kill -0 "$child" 2>/dev/null; do
    sleep 2
    if [ ! -f "$DIR/connected.state" ] && tail -n "+$((start_line + 1))" "$LOG" | grep -q 'Initialization Sequence Completed'; then
      date +%s >"$DIR/connected.state"
    fi
    if [ ! -f "$DIR/transport.state" ] && tail -n "+$((start_line + 1))" "$LOG" | grep -Eq 'TLS: Initial packet|Peer Connection Initiated'; then
      date +%s >"$DIR/transport.state"
    fi
    current="$("$DIR/detect-proxy.sh" "$DIR" 2>/dev/null || true)"
    if [ "$current" != "$proxy" ]; then
      printf '%s proxy changed: %s -> %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$proxy" "${current:-unavailable}" >>"$LOG"
      kill -TERM "$child" 2>/dev/null || true
      wait "$child" 2>/dev/null || true
      child=''
      "$PYTHON_BIN" "$DIR/cleanup-proxy-sessions.py" "$DIR/base.ovpn" "$port" >/dev/null 2>&1 || true
      restart=1
      rm -f "$DIR/connected.state" "$DIR/transport.state" "$DIR/attempt.started"
      break
    fi
  done

  [ "$restart" -eq 1 ] && continue

  wait "$child" 2>/dev/null
  status=$?
  child=''
  if tail -n "+$((start_line + 1))" "$LOG" | grep -q 'AUTH_FAILED'; then
    printf 'auth\n' >"$DIR/failure.state"
  elif tail -n "+$((start_line + 1))" "$LOG" | grep -Eq 'TLS Error|TLS handshake failed|Server poll timeout|All connections have been connect-retry-max'; then
    printf 'transport\n' >"$DIR/failure.state"
  else
    printf 'process\n' >"$DIR/failure.state"
  fi
  rm -f "$DIR/connected.state" "$DIR/transport.state" "$DIR/attempt.started"
  printf '%s OpenVPN exited with status %s; manual start required\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$status" >>"$LOG"
  exit "$status"
done
