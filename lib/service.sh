#!/bin/bash

opb_bootout_job() {
  launchctl bootout "system/$OPB_LABEL" 2>/dev/null || true
  if [ -f "$OPB_PLIST" ]; then
    launchctl bootout system "$OPB_PLIST" 2>/dev/null || true
  fi
}

opb_service_pids() {
  {
    pgrep -f "$OPB_RUN_SCRIPT" 2>/dev/null || true
    pgrep -f "$OPB_RUNTIME_PROFILE" 2>/dev/null || true
  } | sort -u
}

opb_signal_pids() {
  local signal="$1" pids="$2" pid
  while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    kill "-$signal" "$pid" 2>/dev/null || true
  done <<<"$pids"
}

opb_write_launchd_plist() {
  local temporary="$OPB_PLIST.tmp.$$"
  cp "$OPB_BUNDLE_ROOT/assets/com.local.proxy-openvpn.plist" "$temporary"
  if ! plutil -lint "$temporary" >/dev/null; then
    rm -f "$temporary"
    return 1
  fi
  opb_chown_root "$temporary"
  chmod 644 "$temporary"
  mv -f "$temporary" "$OPB_PLIST"
}

opb_prepare_service_files() {
  [ -f "$OPB_BASE_PROFILE" ] && [ -f "$OPB_AUTH_FILE" ] && [ -f "$OPB_INSTALL_META" ] || {
    echo '后台运行文件缺失，请重新安装。'
    return 1
  }

  cp "$OPB_BUNDLE_ROOT/assets/run-openvpn.sh" "$OPB_RUN_SCRIPT"
  cp "$OPB_BUNDLE_ROOT/tools/cleanup_proxy_sessions.py" "$OPB_INSTALL_DIR/cleanup-proxy-sessions.py"
  cp "$OPB_BUNDLE_ROOT/tools/resolve_remotes.py" "$OPB_INSTALL_DIR/resolve-remotes.py"
  opb_install_proxy_detector
  chmod 700 "$OPB_INSTALL_DIR" "$OPB_RUN_SCRIPT" "$OPB_DETECT_SCRIPT" \
    "$OPB_INSTALL_DIR/cleanup-proxy-sessions.py" "$OPB_INSTALL_DIR/resolve-remotes.py"
  opb_chown_root_recursive "$OPB_INSTALL_DIR"
  opb_write_launchd_plist
}

opb_stop_service() {
  local pids='' i=0 had_service=0
  if launchctl print "system/$OPB_LABEL" >/dev/null 2>&1 || [ -n "$(opb_service_pids)" ]; then
    had_service=1
  fi

  # Delete the proxy UDP session while OpenVPN's SOCKS control connection is
  # still alive; after process exit the controller may no longer expose it.
  opb_cleanup_proxy_sessions
  opb_bootout_job
  launchctl disable "system/$OPB_LABEL" 2>/dev/null || true

  while [ "$i" -lt 50 ]; do
    pids="$(opb_service_pids)"
    [ -z "$pids" ] && break
    sleep 0.2
    i=$((i + 1))
  done

  pids="$(opb_service_pids)"
  if [ -n "$pids" ]; then
    opb_signal_pids TERM "$pids"
    sleep 2
  fi
  pids="$(opb_service_pids)"
  if [ -n "$pids" ]; then
    opb_signal_pids KILL "$pids"
    sleep 1
  fi
  pids="$(opb_service_pids)"
  if [ -n "$pids" ]; then
    echo "无法清理残留的公司 VPN 进程：$pids"
    return 1
  fi

  rm -f "$OPB_CONNECTED_STATE" "$OPB_ATTEMPT_STATE" "$OPB_TRANSPORT_STATE" "$OPB_FAILURE_STATE" "$OPB_REMOTE_COUNT_STATE"
  rm -f "$OPB_RUNTIME_PROFILE"
  opb_cleanup_proxy_sessions
  rm -f "$OPB_CURRENT_PROXY_STATE"
  if [ "$had_service" -eq 1 ] && [ -d "$OPB_INSTALL_DIR" ]; then
    date +%s >"$OPB_LAST_STOP_STATE"
  fi
}

opb_wait_for_proxy_release() {
  local minimum="${1:-$OPB_PROXY_RELEASE_WAIT}" stopped now elapsed remaining
  [ -f "$OPB_LAST_STOP_STATE" ] || return 0
  stopped="$(cat "$OPB_LAST_STOP_STATE" 2>/dev/null || echo 0)"
  now="$(date +%s)"
  elapsed=$((now - stopped))
  if [ "$elapsed" -ge 0 ] && [ "$elapsed" -lt "$minimum" ]; then
    remaining=$((minimum - elapsed))
    echo "等待旧代理会话释放（${remaining} 秒）..."
    sleep "$remaining"
  fi
}

opb_bootstrap_service() {
  local release_wait="${1:-$OPB_PROXY_RELEASE_WAIT}" output='' attempt
  opb_stop_service
  opb_wait_for_proxy_release "$release_wait"
  opb_prepare_service_files
  launchctl enable "system/$OPB_LABEL" 2>/dev/null || true
  for attempt in 1 2; do
    sleep "$attempt"
    if output="$(launchctl bootstrap system "$OPB_PLIST" 2>&1)"; then
      return 0
    fi
    opb_bootout_job
  done
  echo "后台服务注册失败：$output"
  echo '请运行 status-company-vpn.command 查看 launchd.log。'
  return 1
}

opb_failure_code() {
  case "$(cat "$OPB_FAILURE_STATE" 2>/dev/null || true)" in
    auth) printf '3\n' ;;
    transport) printf '2\n' ;;
    *) printf '1\n' ;;
  esac
}

opb_wait_for_failure_state() {
  local count=0
  while [ "$count" -lt 30 ]; do
    [ -f "$OPB_FAILURE_STATE" ] && return 0
    sleep 0.1
    count=$((count + 1))
  done
  return 1
}

opb_wait_for_connection() {
  local timeout="${1:-$OPB_CONNECT_TIMEOUT}" elapsed=0 transport_timeout remote_count server_poll_timeout
  while [ "$elapsed" -lt "$timeout" ]; do
    if [ -f "$OPB_CONNECTED_STATE" ] && pgrep -f "$OPB_RUNTIME_PROFILE" >/dev/null 2>&1; then
      return 0
    fi
    if [ -f "$OPB_FAILURE_STATE" ]; then
      return "$(opb_failure_code)"
    fi
    if ! launchctl print "system/$OPB_LABEL" >/dev/null 2>&1; then
      if opb_wait_for_failure_state; then
        return "$(opb_failure_code)"
      fi
      return 1
    fi
    if [ "$elapsed" -ge 3 ] && ! pgrep -f "$OPB_RUNTIME_PROFILE" >/dev/null 2>&1; then
      if opb_wait_for_failure_state; then
        return "$(opb_failure_code)"
      fi
      return 1
    fi
    remote_count="$(cat "$OPB_REMOTE_COUNT_STATE" 2>/dev/null || echo 1)"
    server_poll_timeout="${SERVER_POLL_TIMEOUT:-$OPB_SERVER_POLL_TIMEOUT}"
    [[ "$remote_count" =~ ^[0-9]+$ ]] || remote_count=1
    [[ "$server_poll_timeout" =~ ^[0-9]+$ ]] || server_poll_timeout="$OPB_SERVER_POLL_TIMEOUT"
    transport_timeout=$((remote_count * server_poll_timeout + OPB_TRANSPORT_GRACE))
    [ "$transport_timeout" -lt "$OPB_DEFAULT_TRANSPORT_TIMEOUT" ] && transport_timeout="$OPB_DEFAULT_TRANSPORT_TIMEOUT"
    [ "$transport_timeout" -gt "$timeout" ] && transport_timeout="$timeout"
    if [ "$elapsed" -ge "$transport_timeout" ] && [ ! -f "$OPB_TRANSPORT_STATE" ]; then
      return 2
    fi
    if [ "$elapsed" -gt 0 ] && [ $((elapsed % 10)) -eq 0 ]; then
      echo "仍在等待公司 VPN 隧道（${elapsed}/${timeout} 秒）..."
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

opb_connect_service() {
  local reason="${1:-启动}" attempt result release_wait="$OPB_PROXY_RELEASE_WAIT"
  for attempt in 1 2; do
    opb_bootstrap_service "$release_wait"
    if [ "$attempt" -eq 1 ]; then
      echo "${reason}已开始，正在等待公司 VPN 隧道建立..."
    else
      echo '正在进行第 2 次连接尝试...'
    fi
    if opb_wait_for_connection "$OPB_CONNECT_TIMEOUT"; then
      echo '公司 VPN 已连接。'
      return 0
    else
      result=$?
    fi
    opb_stop_service
    if [ "$result" -eq 3 ]; then
      echo 'VPN 服务器返回 AUTH_FAILED。请检查账号、密码或二次认证；本次不会自动重试。'
      return 3
    fi
    if [ "$result" -eq 2 ] && [ "$attempt" -eq 1 ]; then
      echo '当前端点等待预算内没有 VPN 服务器返回 TLS，已清理本次连接。'
      echo '重新解析 VPN 地址后自动重试一次...'
      release_wait="$OPB_PROXY_RELEASE_WAIT"
      continue
    fi
    if [ "$result" -eq 2 ]; then
      echo '两次连接中所有已解析的 VPN 端点均未返回 TLS。'
      echo '本机 SOCKS5 端口可用，但当前出海节点可能无法转发 VPN UDP。'
      echo '请切换出海节点或完全重启出海客户端，然后重新运行启动脚本。'
    else
      echo '公司 VPN 未在规定时间内完成连接。'
    fi
    echo '残留进程和运行状态已清理，请运行 status-company-vpn.command 查看日志。'
    return 1
  done
  return 1
}
