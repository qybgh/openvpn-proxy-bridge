#!/bin/bash

opb_detect_proxy() {
  "$OPB_DETECT_SCRIPT" "$OPB_INSTALL_DIR"
}

opb_install_proxy_detector() {
  cp "$OPB_BUNDLE_ROOT/assets/detect-proxy.sh" "$OPB_DETECT_SCRIPT"
  chmod 700 "$OPB_DETECT_SCRIPT"
}

opb_cleanup_proxy_sessions() {
  local proxy='' proxy_port='' deleted='0' python_bin profile
  [ -f "$OPB_BASE_PROFILE" ] || return 0
  profile="$OPB_BASE_PROFILE"
  [ ! -f "$OPB_RUNTIME_PROFILE" ] || profile="$OPB_RUNTIME_PROFILE"

  if [ -s "$OPB_CURRENT_PROXY_STATE" ]; then
    proxy="$(cat "$OPB_CURRENT_PROXY_STATE" 2>/dev/null || true)"
  else
    proxy="$(opb_detect_proxy 2>/dev/null || true)"
  fi
  [ -n "$proxy" ] || return 0

  read -r _ proxy_port <<<"$proxy"
  python_bin="${OPB_PYTHON_BIN:-$(opb_find_python || true)}"
  [ -n "$python_bin" ] || return 0
  deleted="$("$python_bin" \
    "$OPB_BUNDLE_ROOT/tools/cleanup_proxy_sessions.py" \
    "$profile" "$proxy_port" 2>/dev/null || echo 0)"
  case "$deleted" in
    '' | *[!0-9]*) deleted=0 ;;
  esac
  if [ "$deleted" -gt 0 ]; then
    printf '%s cleared %s proxy UDP session(s)\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$deleted" >>"$OPB_OPENVPN_LOG"
  fi
}

opb_save_manual_proxy() {
  local host="$1" port="$2"
  case "$host" in
    127.0.0.1 | localhost | ::1) ;;
    *)
      echo '仅允许本机回环代理地址。'
      return 1
      ;;
  esac
  [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || {
    echo '端口无效。'
    return 1
  }
  printf '%s %s\n' "$host" "$port" >"$OPB_PROXY_CONFIG"
  chmod 600 "$OPB_PROXY_CONFIG"
}
