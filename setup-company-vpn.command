#!/bin/bash
case "$0" in
  */setup-company-vpn.command)
    snapshot="$(mktemp "${TMPDIR:-/tmp}/proxy-openvpn.XXXXXX")" || exit 1
    cp "$0" "$snapshot" && chmod 700 "$snapshot" || { rm -f "$snapshot"; exit 1; }
    /bin/bash "$snapshot" "$@"
    status=$?
    rm -f "$snapshot"
    exit "$status"
    ;;
esac
set -euo pipefail

LABEL='com.local.proxy-openvpn'
DIR='/Library/Application Support/Proxy-OpenVPN'
PLIST="/Library/LaunchDaemons/$LABEL.plist"
ACTION="${1:-setup}"

write_launchd_plist() {
  local tmp_plist="$PLIST.tmp.$$"
  cat > "$tmp_plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$LABEL</string>
<key>ProgramArguments</key><array>
  <string>/bin/bash</string>
  <string>$DIR/run-openvpn.sh</string>
</array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><false/>
<key>ExitTimeOut</key><integer>30</integer>
<key>StandardOutPath</key><string>$DIR/launchd.log</string>
<key>StandardErrorPath</key><string>$DIR/launchd.log</string>
</dict></plist>
EOF
  if ! plutil -lint "$tmp_plist" >/dev/null; then
    rm -f "$tmp_plist"
    return 1
  fi
  chown root:wheel "$tmp_plist"
  chmod 644 "$tmp_plist"
  mv -f "$tmp_plist" "$PLIST"
}

bootout_job() {
  local label="$1" plist="$2"
  launchctl bootout "system/$label" 2>/dev/null || true
  if [ -f "$plist" ]; then launchctl bootout system "$plist" 2>/dev/null || true; fi
}

service_pids() {
  {
    pgrep -f "$DIR/run-openvpn.sh" 2>/dev/null || true
    pgrep -f "$DIR/runtime.ovpn" 2>/dev/null || true
  } | sort -u
}

cleanup_proxy_sessions() {
  local proxy='' proxy_port=''
  [ -f "$DIR/base.ovpn" ] || return 0
  if [ -s "$DIR/current-proxy.state" ]; then
    proxy="$(cat "$DIR/current-proxy.state" 2>/dev/null || true)"
  else
    proxy="$($DIR/detect-proxy.sh 2>/dev/null || true)"
  fi
  [ -n "$proxy" ] || return 0
  read -r _ proxy_port <<<"$proxy"
  /usr/bin/python3 - "$DIR/base.ovpn" "$proxy_port" <<'PY' >/dev/null 2>&1 || true
import ipaddress, json, pathlib, re, socket, sys, urllib.request
import time
from urllib.parse import quote

profile = pathlib.Path(sys.argv[1]).read_text(errors='ignore').splitlines()
proxy_port = int(sys.argv[2])
targets = set()
for line in profile:
    match = re.match(r'^\s*remote\s+(\S+)\s+(\d+)', line)
    if not match:
        continue
    host, port = match.group(1), int(match.group(2))
    try:
        ips = {host} if ipaddress.ip_address(host) else set()
    except ValueError:
        try:
            ips = {item[4][0] for item in socket.getaddrinfo(host, port, type=socket.SOCK_DGRAM)}
        except OSError:
            ips = set()
    targets.update((ip, port) for ip in ips)

candidates = []
if proxy_port > 10:
    candidates.append(proxy_port - 10)
candidates.extend([9090, 9097])
for controller_port in dict.fromkeys(candidates):
    base = f'http://127.0.0.1:{controller_port}'
    try:
        with urllib.request.urlopen(base + '/connections', timeout=0.8) as response:
            payload = json.load(response)
    except Exception:
        continue
    for attempt in range(5):
        remaining = []
        for connection in payload.get('connections', []):
            metadata = connection.get('metadata') or {}
            destination = metadata.get('destinationIP') or ''
            try:
                port = int(metadata.get('destinationPort') or 0)
            except (TypeError, ValueError):
                continue
            if (destination, port) not in targets:
                continue
            connection_id = connection.get('id')
            if connection_id:
                remaining.append(connection_id)
        if not remaining:
            break
        for connection_id in remaining:
            request = urllib.request.Request(
                base + '/connections/' + quote(connection_id, safe=''),
                method='DELETE',
            )
            try:
                urllib.request.urlopen(request, timeout=0.8).read()
            except Exception:
                pass
        time.sleep(0.4)
        try:
            with urllib.request.urlopen(base + '/connections', timeout=0.8) as response:
                payload = json.load(response)
        except Exception:
            break
    break
PY
}

stop_service() {
  local pids='' i=0 had_service=0
  if launchctl print "system/$LABEL" >/dev/null 2>&1 || [ -n "$(service_pids)" ]; then had_service=1; fi
  bootout_job "$LABEL" "$PLIST"
  launchctl disable "system/$LABEL" 2>/dev/null || true
  while [ "$i" -lt 50 ]; do
    pids="$(service_pids)"
    [ -z "$pids" ] && break
    sleep 0.2
    i=$((i + 1))
  done
  pids="$(service_pids)"
  if [ -n "$pids" ]; then
    kill -TERM $pids 2>/dev/null || true
    sleep 2
  fi
  pids="$(service_pids)"
  if [ -n "$pids" ]; then
    kill -KILL $pids 2>/dev/null || true
    sleep 1
  fi
  pids="$(service_pids)"
  if [ -n "$pids" ]; then
    echo "无法清理残留的公司 VPN 进程：$pids"
    return 1
  fi
  rm -f "$DIR/connected.state" "$DIR/attempt.started"
  rm -f "$DIR/transport.state" "$DIR/failure.state"
  rm -f "$DIR/runtime.ovpn"
  cleanup_proxy_sessions
  rm -f "$DIR/current-proxy.state"
  if [ "$had_service" -eq 1 ] && [ -d "$DIR" ]; then date +%s > "$DIR/last-stop.state"; fi
}

wait_for_proxy_release() {
  local minimum="${1:-8}" stopped now elapsed remaining
  [ -f "$DIR/last-stop.state" ] || return 0
  stopped="$(cat "$DIR/last-stop.state" 2>/dev/null || echo 0)"
  now="$(date +%s)"
  elapsed=$((now - stopped))
  if [ "$elapsed" -ge 0 ] && [ "$elapsed" -lt "$minimum" ]; then
    remaining=$((minimum - elapsed))
    echo "等待旧代理会话释放（${remaining} 秒）..."
    sleep "$remaining"
  fi
}

write_runtime_monitor() {
  local brew_bin openvpn_bin
  brew_bin="$(find_brew || true)"
  [ -x "$brew_bin" ] || { echo '未找到 Homebrew。'; return 1; }
  openvpn_bin="$($brew_bin --prefix openvpn)/sbin/openvpn"
  [ -x "$openvpn_bin" ] || { echo '未找到 Homebrew OpenVPN。'; return 1; }
  cat > "$DIR/run-openvpn.sh" <<SH
#!/bin/bash
set -u
DIR='$DIR'; OPENVPN_BIN='$openvpn_bin'; LOG="\$DIR/openvpn.log"; child=''
cleanup() {
  rm -f "\$DIR/connected.state" "\$DIR/transport.state" "\$DIR/attempt.started"
  if [ -n "\$child" ] && kill -0 "\$child" 2>/dev/null; then
    kill -TERM "\$child" 2>/dev/null || true
    i=0
    while kill -0 "\$child" 2>/dev/null && [ "\$i" -lt 50 ]; do sleep 0.2; i=\$((i + 1)); done
    kill -0 "\$child" 2>/dev/null && kill -KILL "\$child" 2>/dev/null || true
    wait "\$child" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 0' TERM INT
printf '%s proxy monitor started\n' "\$(date '+%Y-%m-%d %H:%M:%S')" >> "\$LOG"
while :; do
  proxy="\$("\$DIR/detect-proxy.sh" 2>/dev/null || true)"
  if [ -z "\$proxy" ]; then sleep 5; continue; fi
  read -r host port <<<"\$proxy"
  printf '%s %s\n' "\$host" "\$port" > "\$DIR/current-proxy.state"
  chmod 600 "\$DIR/current-proxy.state"
  cp "\$DIR/base.ovpn" "\$DIR/runtime.ovpn"
  printf 'socks-proxy %s %s\n' "\$host" "\$port" >> "\$DIR/runtime.ovpn"
  if grep -Eq '^[[:space:]]*proto[[:space:]]+udp(4|6)?([[:space:]]|$)' "\$DIR/base.ovpn" && ! grep -Eq '^[[:space:]]*explicit-exit-notify([[:space:]]|$)' "\$DIR/base.ovpn"; then
    printf 'explicit-exit-notify 3\n' >> "\$DIR/runtime.ovpn"
  fi
  chmod 600 "\$DIR/runtime.ovpn"
  rm -f "\$DIR/connected.state" "\$DIR/transport.state" "\$DIR/failure.state"
  date +%s > "\$DIR/attempt.started"
  touch "\$LOG"
  start_line=\$(wc -l < "\$LOG" | tr -d ' ')
  printf '%s using SOCKS5 %s:%s\n' "\$(date '+%Y-%m-%d %H:%M:%S')" "\$host" "\$port" >> "\$LOG"
  "\$OPENVPN_BIN" --config "\$DIR/runtime.ovpn" --log-append "\$LOG" & child=\$!
  restart=0
  while kill -0 "\$child" 2>/dev/null; do
    sleep 2
    if [ ! -f "\$DIR/connected.state" ] && tail -n "+\$((start_line + 1))" "\$LOG" | grep -q 'Initialization Sequence Completed'; then
      date +%s > "\$DIR/connected.state"
    fi
    if [ ! -f "\$DIR/transport.state" ] && tail -n "+\$((start_line + 1))" "\$LOG" | grep -Eq 'TLS: Initial packet|Peer Connection Initiated'; then
      date +%s > "\$DIR/transport.state"
    fi
    current="\$("\$DIR/detect-proxy.sh" 2>/dev/null || true)"
    if [ "\$current" != "\$proxy" ]; then
      printf '%s proxy changed: %s -> %s\n' "\$(date '+%Y-%m-%d %H:%M:%S')" "\$proxy" "\${current:-unavailable}" >> "\$LOG"
      kill -TERM "\$child" 2>/dev/null || true
      wait "\$child" 2>/dev/null || true
      child=''; restart=1
      rm -f "\$DIR/connected.state" "\$DIR/transport.state" "\$DIR/attempt.started"
      break
    fi
  done
  [ "\$restart" -eq 1 ] && continue
  wait "\$child" 2>/dev/null; status=\$?; child=''
  if tail -n "+\$((start_line + 1))" "\$LOG" | grep -q 'AUTH_FAILED'; then
    printf 'auth\n' > "\$DIR/failure.state"
  elif tail -n "+\$((start_line + 1))" "\$LOG" | grep -Eq 'TLS Error|TLS handshake failed'; then
    printf 'transport\n' > "\$DIR/failure.state"
  else
    printf 'process\n' > "\$DIR/failure.state"
  fi
  rm -f "\$DIR/connected.state" "\$DIR/transport.state" "\$DIR/attempt.started"
  printf '%s OpenVPN exited with status %s; manual start required\n' "\$(date '+%Y-%m-%d %H:%M:%S')" "\$status" >> "\$LOG"
  exit "\$status"
done
SH
  chmod 700 "$DIR/run-openvpn.sh"
}

prepare_service_files() {
  [ -x "$DIR/detect-proxy.sh" ] && [ -f "$DIR/base.ovpn" ] && [ -f "$DIR/auth.txt" ] || {
    echo '后台运行文件缺失，请重新安装。'; return 1;
  }
  write_runtime_monitor
  chown -R root:wheel "$DIR"
  chmod 700 "$DIR" "$DIR/run-openvpn.sh" "$DIR/detect-proxy.sh"
  write_launchd_plist
}

bootstrap_service() {
  local release_wait="${1:-8}" output='' attempt
  stop_service
  wait_for_proxy_release "$release_wait"
  prepare_service_files
  launchctl enable "system/$LABEL" 2>/dev/null || true
  for attempt in 1 2; do
    sleep "$attempt"
    if output="$(launchctl bootstrap system "$PLIST" 2>&1)"; then
      return 0
    fi
    bootout_job "$LABEL" "$PLIST"
  done
  echo "后台服务注册失败：$output"
  echo '请运行 status-company-vpn.command 查看 launchd.log。'
  return 1
}

wait_for_connection() {
  local timeout="${1:-130}" elapsed=0
  while [ "$elapsed" -lt "$timeout" ]; do
    if [ -f "$DIR/connected.state" ] && pgrep -f "$DIR/runtime.ovpn" >/dev/null 2>&1; then return 0; fi
    if [ -f "$DIR/failure.state" ]; then
      case "$(cat "$DIR/failure.state" 2>/dev/null || true)" in
        auth) return 3 ;;
        transport) return 2 ;;
        *) return 1 ;;
      esac
    fi
    if ! launchctl print "system/$LABEL" >/dev/null 2>&1; then return 1; fi
    if [ "$elapsed" -ge 3 ] && ! pgrep -f "$DIR/runtime.ovpn" >/dev/null 2>&1; then return 1; fi
    if [ "$elapsed" -ge 25 ] && [ ! -f "$DIR/transport.state" ]; then return 2; fi
    if [ "$elapsed" -gt 0 ] && [ $((elapsed % 10)) -eq 0 ]; then
      echo "仍在等待公司 VPN 隧道（${elapsed}/${timeout} 秒）..."
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

connect_service() {
  local reason="${1:-启动}" attempt result release_wait=8
  for attempt in 1 2; do
    bootstrap_service "$release_wait"
    if [ "$attempt" -eq 1 ]; then
      echo "${reason}已开始，正在等待公司 VPN 隧道建立..."
    else
      echo '正在进行第 2 次连接尝试...'
    fi
    if wait_for_connection 130; then
      echo '公司 VPN 已连接。'
      return 0
    else
      result=$?
    fi
    stop_service
    if [ "$result" -eq 3 ]; then
      echo 'VPN 服务器返回 AUTH_FAILED。请检查账号、密码或二次认证；本次不会自动重试。'
      return 3
    fi
    if [ "$result" -eq 2 ] && [ "$attempt" -eq 1 ]; then
      echo '25 秒内未收到 VPN 服务器的 TLS 回包，已清理本次连接。'
      echo '等待旧代理或服务端会话释放后自动重试一次（最多约 30 秒）...'
      release_wait=30
      continue
    fi
    if [ "$result" -eq 2 ]; then
      echo '两次连接均未收到 VPN 服务器的 TLS 回包。'
    else
      echo '公司 VPN 未在规定时间内完成连接。'
    fi
    echo '残留进程和运行状态已清理，请运行 status-company-vpn.command 查看日志。'
    return 1
  done
  return 1
}

find_brew() {
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
  done
  command -v brew 2>/dev/null || return 1
}

console_user() {
  local user="${SUDO_USER:-}"
  if [ -z "$user" ] || [ "$user" = root ]; then user="$(stat -f '%Su' /dev/console)"; fi
  [ -n "$user" ] && [ "$user" != root ] || user="$(id -un)"
  printf '%s\n' "$user"
}

as_console_user() {
  local user="$1"; shift
  if [ "$(id -u)" -eq 0 ] && [ "$user" != root ]; then sudo -H -u "$user" "$@"; else "$@"; fi
}

choose_profile() {
  local selected=''
  if command -v osascript >/dev/null 2>&1; then
    selected="$(osascript <<'APPLESCRIPT' 2>/dev/null || true
try
  POSIX path of (choose file with prompt "选择公司 OpenVPN profile（请选择 .ovpn 文件）")
on error
  return ""
end try
APPLESCRIPT
)"
  fi
  if [ -z "$selected" ]; then
    printf '请输入或拖入公司 .ovpn 文件路径: ' >&2
    IFS= read -r selected
    selected="${selected#\'}"; selected="${selected%\'}"
    selected="${selected#\"}"; selected="${selected%\"}"
  fi
  [ -f "$selected" ] || { echo '未找到所选文件。' >&2; return 1; }
  case "$(printf '%s' "$selected" | tr '[:upper:]' '[:lower:]')" in
    *.ovpn) ;;
    *) echo '所选文件不是 .ovpn profile。' >&2; return 1;;
  esac
  [ -r "$selected" ] || { echo '所选 .ovpn 文件不可读。' >&2; return 1; }
  printf '%s\n' "$selected"
}

if [ "$(id -u)" -ne 0 ]; then
  BREW_BIN="$(find_brew || true)"
  [ -n "$BREW_BIN" ] || { echo '未找到 Homebrew。请先安装 Homebrew，再重新运行本脚本。'; exit 1; }
  case "$ACTION" in
    setup)
      PROFILE="$(choose_profile)"
      OPENVPN_PREEXISTING=0; PKCS_PREEXISTING=0
      FORMULAE_BEFORE="$($BREW_BIN list --formula -1 2>/dev/null | sort)"
      "$BREW_BIN" list --versions openvpn >/dev/null 2>&1 && OPENVPN_PREEXISTING=1
      "$BREW_BIN" list --versions pkcs11-helper >/dev/null 2>&1 && PKCS_PREEXISTING=1
      if [ "$OPENVPN_PREEXISTING" -eq 1 ]; then
        printf '检测到已有 Homebrew OpenVPN。卸载本工具时是否一并托管卸载？[y/N]: '
        read -r manage_existing
        case "${manage_existing:-N}" in
          [Yy]*)
            OPENVPN_PREEXISTING=0
            FORMULAE_INSTALLED="openvpn,$($BREW_BIN deps --formula openvpn 2>/dev/null | paste -sd, -)"
            ;;
        esac
      else
        echo '正在通过 Homebrew 安装 OpenVPN...'
        "$BREW_BIN" install openvpn
      fi
      FORMULAE_AFTER="$($BREW_BIN list --formula -1 2>/dev/null | sort)"
      if [ -z "${FORMULAE_INSTALLED:-}" ]; then
        FORMULAE_INSTALLED="$(comm -13 <(printf '%s\n' "$FORMULAE_BEFORE") <(printf '%s\n' "$FORMULAE_AFTER") | paste -sd, -)"
      fi
      OPENVPN_BIN="$($BREW_BIN --prefix openvpn)/sbin/openvpn"
      exec sudo /bin/bash "$0" setup "$PROFILE" "$BREW_BIN" "$OPENVPN_BIN" "$OPENVPN_PREEXISTING" "$PKCS_PREEXISTING" "$FORMULAE_INSTALLED" "$(id -un)"
      ;;
    uninstall) exec sudo /bin/bash "$0" uninstall "$BREW_BIN" "$(id -un)" ;;
    start|stop|status|configure-proxy|update-credentials) exec sudo /bin/bash "$0" "$ACTION" ;;
    *) echo '用法: setup-company-vpn.command [setup|start|stop|status|configure-proxy|update-credentials|uninstall]'; exit 1;;
  esac
fi

case "$ACTION" in
  start)
    [ -d "$DIR" ] || { echo '尚未安装，请先运行 setup-company-vpn.command。'; exit 1; }
    if launchctl print "system/$LABEL" >/dev/null 2>&1 && pgrep -f "$DIR/runtime.ovpn" >/dev/null 2>&1; then
      if [ -f "$DIR/connected.state" ]; then
        echo '公司 VPN 已连接，无需重复启动。'
        exit 0
      fi
      if [ -f "$DIR/attempt.started" ]; then
        started="$(cat "$DIR/attempt.started" 2>/dev/null || echo 0)"
        now="$(date +%s)"
        age=$((now - started))
        if [ "$age" -ge 0 ] && [ "$age" -lt 130 ]; then
          echo '公司 VPN 正在连接，等待隧道建立...'
          if wait_for_connection "$((130 - age))"; then
            echo '公司 VPN 已连接。'
            exit 0
          else
            result=$?
            stop_service
            case "$result" in
              2) echo '25 秒内未收到 VPN 服务器的 TLS 回包，连接已停止并清理。' ;;
              3) echo 'VPN 服务器返回 AUTH_FAILED。请检查账号、密码或二次认证。' ;;
              *) echo '连接未完成，残留进程和运行状态已清理。' ;;
            esac
            echo '请运行 status-company-vpn.command 查看日志。'
            exit 1
          fi
        fi
      fi
      echo '检测到未完成的旧连接，正在清理后重试。'
    fi
    connect_service '后台服务'
    ;;
  stop)
    stop_service
    echo '公司后台 VPN 已停止；现在可以使用 OpenVPN Connect。'
    ;;
  status)
    echo '=== 后台服务 ==='
    launchctl print "system/$LABEL" 2>/dev/null || echo '未运行'
    echo '=== VPN 连接 ==='
    if [ -f "$DIR/connected.state" ] && pgrep -f "$DIR/runtime.ovpn" >/dev/null 2>&1; then
      echo '已连接'
    elif pgrep -f "$DIR/runtime.ovpn" >/dev/null 2>&1; then
      echo '正在连接，尚未建立公司隧道'
    else
      echo '未连接'
    fi
    echo '=== 当前代理 ==='
    [ -x "$DIR/detect-proxy.sh" ] && "$DIR/detect-proxy.sh" || echo '未发现可用的本机 SOCKS5 代理'
    echo '=== 最近日志 ==='
    [ ! -f "$DIR/launchd.log" ] || tail -20 "$DIR/launchd.log"
    [ ! -f "$DIR/openvpn.log" ] || tail -30 "$DIR/openvpn.log"
    ;;
  configure-proxy)
    [ -d "$DIR" ] || { echo '尚未安装。'; exit 1; }
    printf '代理模式 [auto/manual，默认 auto]: '
    read -r mode; mode="${mode:-auto}"
    case "$mode" in
      auto)
        rm -f "$DIR/proxy.conf"
        echo '已恢复自动发现 macOS 系统 SOCKS 代理。重新运行启动脚本后生效。'
        ;;
      manual)
        printf '本地 SOCKS5 地址 [127.0.0.1]: '
        read -r host; host="${host:-127.0.0.1}"
        case "$host" in 127.0.0.1|localhost|::1) ;; *) echo '仅允许本机回环代理地址。'; exit 1;; esac
        printf '本地 SOCKS5 端口: '
        read -r port
        [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || { echo '端口无效。'; exit 1; }
        printf '%s %s\n' "$host" "$port" > "$DIR/proxy.conf"
        chmod 600 "$DIR/proxy.conf"
        echo '已保存手动代理。重新运行启动脚本后生效。'
        ;;
      *) echo '模式只能是 auto 或 manual。'; exit 1;;
    esac
    ;;
  update-credentials)
    [ -d "$DIR" ] && [ -f "$DIR/auth.txt" ] && [ -x "$DIR/detect-proxy.sh" ] || {
      echo '通用版尚未安装，请先运行 setup-company-vpn.command。'; exit 1;
    }
    printf '公司 VPN 用户名: '
    read -r VPN_USER
    printf '公司 VPN 密码（不显示）: '
    IFS= read -r -s VPN_PASSWORD; printf '\n'
    [ -n "$VPN_USER" ] && [ -n "$VPN_PASSWORD" ] || { echo '用户名或密码为空，未修改。'; exit 1; }
    umask 077
    AUTH_TMP="$DIR/auth.txt.new.$$"
    trap 'rm -f "$AUTH_TMP"' EXIT
    printf '%s\n%s\n' "$VPN_USER" "$VPN_PASSWORD" > "$AUTH_TMP"
    unset VPN_PASSWORD
    chmod 600 "$AUTH_TMP"
    mv -f "$AUTH_TMP" "$DIR/auth.txt"
    trap - EXIT
    chown root:wheel "$DIR/auth.txt"
    connect_service '使用新凭据的连接'
    ;;
  setup)
    PROFILE="${2:-}"; BREW_BIN="${3:-}"; OPENVPN_BIN="${4:-}"
    OPENVPN_PREEXISTING="${5:-1}"; PKCS_PREEXISTING="${6:-1}"
    FORMULAE_INSTALLED="${7:-}"; OWNER_USER="${8:-$(console_user)}"
    [ -f "$PROFILE" ] && [ -x "$OPENVPN_BIN" ] && [ -x "$BREW_BIN" ] || { echo 'profile、Homebrew 或 OpenVPN 参数无效。'; exit 1; }
    if [ -e "$DIR" ] || [ -e "$PLIST" ]; then
      echo '通用版后台服务已经安装。请先运行 uninstall-company-vpn.command 再重新安装。'; exit 1
    fi
    umask 077
    mkdir -p -m 700 "$DIR"
    cp "$PROFILE" "$DIR/source.ovpn"; chmod 600 "$DIR/source.ovpn"
    printf '公司 VPN 用户名: '; read -r VPN_USER
    printf '公司 VPN 密码（不显示）: '; IFS= read -r -s VPN_PASSWORD; printf '\n'
    [ -n "$VPN_USER" ] && [ -n "$VPN_PASSWORD" ] || { echo '用户名或密码为空。'; exit 1; }
    printf '%s\n%s\n' "$VPN_USER" "$VPN_PASSWORD" > "$DIR/auth.txt"; unset VPN_PASSWORD
    chmod 600 "$DIR/auth.txt"
    /usr/bin/python3 - "$DIR/source.ovpn" "$DIR/base.ovpn" "$DIR/auth.txt" <<'PY'
import pathlib, re, sys
source, target, auth = map(pathlib.Path, sys.argv[1:])
out, block = [], False
skip = {'max-routes','auth-user-pass','auth-retry','verb','resolv-retry','socks-proxy','socks-proxy-retry'}
for line in source.read_text().splitlines():
    stripped = line.strip()
    if re.match(r'^<[\w-]+>', stripped): block = True
    directive = stripped.split()[0] if stripped else ''
    if block or directive not in skip: out.append(line)
    if re.match(r'^</[\w-]+>', stripped): block = False
out += [f'auth-user-pass "{auth}"','auth-retry none','auth-nocache',
        'data-ciphers AES-256-GCM:AES-128-GCM:AES-256-CBC','data-ciphers-fallback AES-256-CBC',
        'allow-compression asym','connect-retry-max 1','resolv-retry 10','verb 3']
target.write_text('\n'.join(out) + '\n'); target.chmod(0o600)
PY
    cat > "$DIR/detect-proxy.sh" <<'SH'
#!/bin/bash
set -euo pipefail
DIR='/Library/Application Support/Proxy-OpenVPN'
if [ -s "$DIR/proxy.conf" ]; then
  read -r host port < "$DIR/proxy.conf"
else
  proxy="$('/usr/sbin/scutil' --proxy)"
  enabled="$(printf '%s\n' "$proxy" | awk -F': ' '/SOCKSEnable/{gsub(/ /,"",$2); print $2; exit}')"
  host="$(printf '%s\n' "$proxy" | awk -F': ' '/SOCKSProxy/{gsub(/^ +| +$/,"",$2); print $2; exit}')"
  port="$(printf '%s\n' "$proxy" | awk -F': ' '/SOCKSPort/{gsub(/ /,"",$2); print $2; exit}')"
  [ "$enabled" = 1 ] || exit 1
fi
case "$host" in 127.0.0.1|localhost|::1) ;; *) exit 1;; esac
[[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || exit 1
/usr/bin/nc -z -w 2 "$host" "$port" >/dev/null 2>&1 || exit 1
printf '%s %s\n' "$host" "$port"
SH
    chmod 700 "$DIR/detect-proxy.sh"
    cat > "$DIR/install.meta" <<EOF
BREW_BIN='$BREW_BIN'
OWNER_USER='$OWNER_USER'
OPENVPN_INSTALLED_BY_SCRIPT='$((1 - OPENVPN_PREEXISTING))'
PKCS_PREEXISTED='$PKCS_PREEXISTING'
FORMULAE_INSTALLED_BY_SCRIPT='$FORMULAE_INSTALLED'
EOF
    chmod 600 "$DIR/install.meta"
    prepare_service_files
    launchctl disable "system/$LABEL" 2>/dev/null || true
    echo '通用自适应版本已安装，当前未连接公司 VPN。'
    echo '需要访问公司网络时，请运行 start-company-vpn.command。'
    ;;
  uninstall)
    BREW_BIN="${2:-$(find_brew || true)}"; REQUEST_USER="${3:-$(console_user)}"
    OWNER_USER="$REQUEST_USER"; OPENVPN_INSTALLED_BY_SCRIPT=0; PKCS_PREEXISTED=1; FORMULAE_INSTALLED_BY_SCRIPT=''
    if [ -f "$DIR/install.meta" ]; then
      source "$DIR/install.meta"
    fi
    stop_service
    rm -f "$PLIST" "$PLIST".tmp.*
    rm -rf "$DIR"
    launchctl enable "system/$LABEL" 2>/dev/null || true
    if [ "$OPENVPN_INSTALLED_BY_SCRIPT" = 1 ] && [ -x "$BREW_BIN" ]; then
      as_console_user "$OWNER_USER" "$BREW_BIN" uninstall openvpn || true
      IFS=',' read -r -a managed_formulae <<<"$FORMULAE_INSTALLED_BY_SCRIPT"
      for pass in 1 2 3; do
        for formula in "${managed_formulae[@]}"; do
          [ -n "$formula" ] && [ "$formula" != openvpn ] || continue
          as_console_user "$OWNER_USER" "$BREW_BIN" list --versions "$formula" >/dev/null 2>&1 || continue
          users="$(as_console_user "$OWNER_USER" "$BREW_BIN" uses --installed "$formula" 2>/dev/null || true)"
          [ -n "$users" ] || as_console_user "$OWNER_USER" "$BREW_BIN" uninstall "$formula" || true
        done
      done
    fi
    echo '后台服务、配置、凭据、日志和由本脚本安装的 OpenVPN 已清理。'
    ;;
esac
