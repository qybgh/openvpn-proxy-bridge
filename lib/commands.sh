#!/bin/bash

opb_cmd_start() {
  local started now age result
  [ -d "$OPB_INSTALL_DIR" ] || {
    echo '尚未安装，请先运行 setup-company-vpn.command。'
    return 1
  }

  if launchctl print "system/$OPB_LABEL" >/dev/null 2>&1 && pgrep -f "$OPB_RUNTIME_PROFILE" >/dev/null 2>&1; then
    if [ -f "$OPB_CONNECTED_STATE" ]; then
      echo '公司 VPN 已连接，无需重复启动。'
      return 0
    fi
    if [ -f "$OPB_ATTEMPT_STATE" ]; then
      started="$(cat "$OPB_ATTEMPT_STATE" 2>/dev/null || echo 0)"
      now="$(date +%s)"
      age=$((now - started))
      if [ "$age" -ge 0 ] && [ "$age" -lt "$OPB_CONNECT_TIMEOUT" ]; then
        echo '公司 VPN 正在连接，等待隧道建立...'
        if opb_wait_for_connection "$((OPB_CONNECT_TIMEOUT - age))"; then
          echo '公司 VPN 已连接。'
          return 0
        else
          result=$?
        fi
        opb_stop_service
        case "$result" in
          2) echo '当前端点等待预算内没有 VPN 服务器返回 TLS，连接已停止并清理。' ;;
          3) echo 'VPN 服务器返回 AUTH_FAILED。请检查账号、密码或二次认证。' ;;
          *) echo '连接未完成，残留进程和运行状态已清理。' ;;
        esac
        echo '请运行 status-company-vpn.command 查看日志。'
        return 1
      fi
    fi
    echo '检测到未完成的旧连接，正在清理后重试。'
  fi
  opb_connect_service '后台服务'
}

opb_cmd_stop() {
  opb_stop_service
  opb_wait_for_proxy_release "$OPB_PROXY_RELEASE_WAIT"
  rm -f "$OPB_LAST_STOP_STATE"
  echo '公司后台 VPN 已停止；现在可以使用 OpenVPN Connect。'
}

opb_cmd_status() {
  echo '=== 后台服务 ==='
  launchctl print "system/$OPB_LABEL" 2>/dev/null || echo '未运行'
  echo '=== VPN 连接 ==='
  if [ -f "$OPB_CONNECTED_STATE" ] && pgrep -f "$OPB_RUNTIME_PROFILE" >/dev/null 2>&1; then
    echo '已连接'
  elif pgrep -f "$OPB_RUNTIME_PROFILE" >/dev/null 2>&1; then
    echo '正在连接，尚未建立公司隧道'
  else
    echo '未连接'
  fi
  echo '=== 当前代理 ==='
  [ -x "$OPB_DETECT_SCRIPT" ] && opb_detect_proxy || echo '未发现可用的本机 SOCKS5 代理'
  echo '=== 最近日志 ==='
  [ ! -f "$OPB_LAUNCHD_LOG" ] || tail -20 "$OPB_LAUNCHD_LOG"
  [ ! -f "$OPB_OPENVPN_LOG" ] || tail -30 "$OPB_OPENVPN_LOG"
}

opb_cmd_configure_proxy() {
  local mode host port
  [ -d "$OPB_INSTALL_DIR" ] || {
    echo '尚未安装。'
    return 1
  }
  printf '代理模式 [auto/manual，默认 auto]: '
  read -r mode
  mode="${mode:-auto}"
  case "$mode" in
    auto)
      rm -f "$OPB_PROXY_CONFIG"
      echo '已恢复自动发现 macOS 系统 SOCKS 代理。重新运行启动脚本后生效。'
      ;;
    manual)
      printf '本地 SOCKS5 地址 [127.0.0.1]: '
      read -r host
      host="${host:-127.0.0.1}"
      printf '本地 SOCKS5 端口: '
      read -r port
      opb_save_manual_proxy "$host" "$port"
      echo '已保存手动代理。重新运行启动脚本后生效。'
      ;;
    *)
      echo '模式只能是 auto 或 manual。'
      return 1
      ;;
  esac
}

opb_cmd_update_credentials() {
  [ -d "$OPB_INSTALL_DIR" ] && [ -f "$OPB_AUTH_FILE" ] && [ -x "$OPB_DETECT_SCRIPT" ] || {
    echo '通用版尚未安装，请先运行 setup-company-vpn.command。'
    return 1
  }
  if ! opb_read_credentials; then
    echo '用户名或密码为空，未修改。'
    return 1
  fi
  umask 077
  opb_update_credentials_atomic "$OPB_CREDENTIAL_USER" "$OPB_CREDENTIAL_PASSWORD" || return $?
  unset OPB_CREDENTIAL_PASSWORD
  opb_connect_service '使用新凭据的连接'
}

opb_cmd_setup_root() {
  local profile="${1:-}" brew_bin="${2:-}" openvpn_bin="${3:-}" python_bin="${4:-}"
  local openvpn_preexisting="${5:-1}" formulae_installed="${6:-}"
  local owner_user="${7:-$(opb_console_user)}"

  if [ ! -f "$profile" ] || [ ! -x "$openvpn_bin" ] || [ ! -x "$brew_bin" ] || ! opb_python_compatible "$python_bin"; then
    echo 'profile、Homebrew、OpenVPN 或 Python 参数无效。'
    return 1
  fi
  if [ -e "$OPB_INSTALL_DIR" ] || [ -e "$OPB_PLIST" ]; then
    echo '通用版后台服务已经安装。请先运行 uninstall-company-vpn.command 再重新安装。'
    return 1
  fi

  OPB_SETUP_COMMITTED=0
  trap 'if [ "${OPB_SETUP_COMMITTED:-0}" != 1 ]; then rm -f "$OPB_PLIST" "$OPB_PLIST".tmp.*; opb_remove_install_dir; fi' EXIT

  umask 077
  mkdir -p "$OPB_INSTALL_DIR"
  chmod 700 "$OPB_INSTALL_DIR"
  mkdir -p "$(dirname "$OPB_PLIST")"
  cp "$profile" "$OPB_SOURCE_PROFILE"
  chmod 600 "$OPB_SOURCE_PROFILE"

  if ! opb_read_credentials; then
    echo '用户名或密码为空。'
    opb_remove_install_dir
    return 1
  fi
  opb_write_credentials "$OPB_CREDENTIAL_USER" "$OPB_CREDENTIAL_PASSWORD" || return $?
  unset OPB_CREDENTIAL_PASSWORD
  export OPB_PYTHON_BIN="$python_bin"
  opb_filter_profile || return $?
  opb_write_install_meta "$brew_bin" "$owner_user" "$((1 - openvpn_preexisting))" \
    "$formulae_installed" "$openvpn_bin" "$python_bin" "$OPB_SERVER_POLL_TIMEOUT" || return $?
  opb_prepare_service_files || return $?
  launchctl disable "system/$OPB_LABEL" 2>/dev/null || true
  OPB_SETUP_COMMITTED=1
  trap - EXIT
  echo '通用自适应版本已安装，当前未连接公司 VPN。'
  echo '需要访问公司网络时，请运行 start-company-vpn.command。'
}

opb_cmd_uninstall_root() {
  local brew_bin="${1:-$(opb_find_brew || true)}" request_user="${2:-$(opb_console_user)}"
  local owner_user="$request_user" openvpn_owned=0 formulae=''
  # install.meta may define these fields even though uninstall does not consume them.
  # shellcheck disable=SC2034
  local OPENVPN_BIN='' PYTHON_BIN='' SERVER_POLL_TIMEOUT=''

  if [ -f "$OPB_INSTALL_META" ]; then
    # install.meta is root-owned and mode 600.
    # shellcheck disable=SC1090
    source "$OPB_INSTALL_META"
    owner_user="${OWNER_USER:-$owner_user}"
    brew_bin="${BREW_BIN:-$brew_bin}"
    openvpn_owned="${OPENVPN_INSTALLED_BY_SCRIPT:-0}"
    formulae="${FORMULAE_INSTALLED_BY_SCRIPT:-}"
    export SERVER_POLL_TIMEOUT="${SERVER_POLL_TIMEOUT:-$OPB_SERVER_POLL_TIMEOUT}"
  fi

  opb_stop_service
  opb_wait_for_proxy_release "$OPB_PROXY_RELEASE_WAIT"
  rm -f "$OPB_PLIST" "$OPB_PLIST".tmp.*
  opb_remove_install_dir
  launchctl enable "system/$OPB_LABEL" 2>/dev/null || true
  opb_uninstall_managed_formulae "$owner_user" "$brew_bin" "$openvpn_owned" "$formulae"
  echo '后台服务、配置、凭据、日志和由本脚本安装的 OpenVPN 已清理。'
}

opb_dispatch_root() {
  local action="$1"
  shift
  case "$action" in
    setup) opb_cmd_setup_root "$@" ;;
    start) opb_cmd_start ;;
    stop) opb_cmd_stop ;;
    status) opb_cmd_status ;;
    configure-proxy) opb_cmd_configure_proxy ;;
    update-credentials) opb_cmd_update_credentials ;;
    uninstall) opb_cmd_uninstall_root "$@" ;;
    *)
      echo '用法: openvpn-proxy-bridge [setup|start|stop|status|configure-proxy|update-credentials|uninstall]'
      return 1
      ;;
  esac
}

opb_main() {
  local action="${1:-}"
  shift || true
  case "$action" in
    setup | start | stop | status | configure-proxy | update-credentials | uninstall) ;;
    *)
      echo '用法: openvpn-proxy-bridge [setup|start|stop|status|configure-proxy|update-credentials|uninstall]'
      return 1
      ;;
  esac

  if ! opb_is_root; then
    case "$action" in
      setup)
        opb_prepare_setup_as_user
        ;;
      uninstall)
        opb_run_as_root uninstall "$(opb_find_brew || true)" "$(id -un)"
        ;;
      *)
        opb_run_as_root "$action"
        ;;
    esac
    return
  fi

  opb_load_install_meta
  opb_dispatch_root "$action" "$@"
}
