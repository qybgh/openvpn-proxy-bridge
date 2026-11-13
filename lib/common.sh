#!/bin/bash

opb_find_brew() {
  local candidate
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  command -v brew 2>/dev/null || return 1
}

opb_python_compatible() {
  local candidate="$1"
  [ -x "$candidate" ] || return 1
  "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 8) else 1)' >/dev/null 2>&1
}

opb_find_python() {
  local candidate discovered
  for candidate in /usr/bin/python3 /opt/homebrew/bin/python3 /usr/local/bin/python3; do
    if opb_python_compatible "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  discovered="$(command -v python3 2>/dev/null || true)"
  if [ -n "$discovered" ] && opb_python_compatible "$discovered"; then
    printf '%s\n' "$discovered"
    return 0
  fi
  return 1
}

opb_console_user() {
  local user="${SUDO_USER:-}"
  if [ -z "$user" ] || [ "$user" = root ]; then
    user="$(stat -f '%Su' /dev/console)"
  fi
  if [ -z "$user" ] || [ "$user" = root ]; then
    user="$(id -un)"
  fi
  printf '%s\n' "$user"
}

opb_as_console_user() {
  local user="$1"
  shift
  if [ "$(id -u)" -eq 0 ] && [ "$user" != root ]; then
    sudo -H -u "$user" "$@"
  else
    "$@"
  fi
}

opb_run_as_root() {
  if [ "${OPB_TEST_MODE:-0}" = 1 ]; then
    /bin/bash "$OPB_CLI_PATH" "$@"
  else
    exec sudo /usr/bin/env OPB_SNAPSHOT_ACTIVE=1 /bin/bash "$OPB_CLI_PATH" "$@"
  fi
}

opb_is_root() {
  [ "${OPB_TEST_MODE:-0}" = 1 ] || [ "$(id -u)" -eq 0 ]
}

opb_chown_root() {
  if [ "${OPB_TEST_MODE:-0}" = 1 ] && [ -z "${OPB_CHOWN_BIN:-}" ]; then
    return 0
  fi
  "${OPB_CHOWN_BIN:-/usr/sbin/chown}" root:wheel "$@"
}

opb_chown_root_recursive() {
  if [ "${OPB_TEST_MODE:-0}" = 1 ] && [ -z "${OPB_CHOWN_BIN:-}" ]; then
    return 0
  fi
  "${OPB_CHOWN_BIN:-/usr/sbin/chown}" -R root:wheel "$@"
}

opb_choose_profile() {
  local selected=''
  if command -v osascript >/dev/null 2>&1; then
    selected="$(
      osascript <<'APPLESCRIPT' 2>/dev/null || true
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
    selected="${selected#\'}"
    selected="${selected%\'}"
    selected="${selected#\"}"
    selected="${selected%\"}"
  fi
  [ -f "$selected" ] || {
    echo '未找到所选文件。' >&2
    return 1
  }
  case "$(printf '%s' "$selected" | tr '[:upper:]' '[:lower:]')" in
    *.ovpn) ;;
    *)
      echo '所选文件不是 .ovpn profile。' >&2
      return 1
      ;;
  esac
  [ -r "$selected" ] || {
    echo '所选 .ovpn 文件不可读。' >&2
    return 1
  }
  printf '%s\n' "$selected"
}

opb_remove_install_dir() {
  if [ "${OPB_TEST_MODE:-0}" = 1 ]; then
    [ -n "$OPB_INSTALL_DIR" ] && [ "$OPB_INSTALL_DIR" != / ] || {
      echo "拒绝删除非预期测试目录：$OPB_INSTALL_DIR" >&2
      return 1
    }
    rm -rf "$OPB_INSTALL_DIR"
    return 0
  fi
  case "$OPB_INSTALL_DIR" in
    '/Library/Application Support/Proxy-OpenVPN')
      rm -rf "$OPB_INSTALL_DIR"
      ;;
    *)
      echo "拒绝删除非预期目录：$OPB_INSTALL_DIR" >&2
      return 1
      ;;
  esac
}

opb_write_install_meta() {
  local brew_bin="$1" owner_user="$2" openvpn_owned="$3" formulae="$4" openvpn_bin="$5" python_bin="$6" server_poll_timeout="$7"
  {
    printf 'BREW_BIN=%q\n' "$brew_bin"
    printf 'OWNER_USER=%q\n' "$owner_user"
    printf 'OPENVPN_INSTALLED_BY_SCRIPT=%q\n' "$openvpn_owned"
    printf 'FORMULAE_INSTALLED_BY_SCRIPT=%q\n' "$formulae"
    printf 'OPENVPN_BIN=%q\n' "$openvpn_bin"
    printf 'PYTHON_BIN=%q\n' "$python_bin"
    printf 'SERVER_POLL_TIMEOUT=%q\n' "$server_poll_timeout"
  } >"$OPB_INSTALL_META"
  chmod 600 "$OPB_INSTALL_META"
  opb_chown_root "$OPB_INSTALL_META"
}

opb_load_install_meta() {
  [ -r "$OPB_INSTALL_META" ] || return 0
  # install.meta is root-owned and mode 600.
  # shellcheck disable=SC1090
  source "$OPB_INSTALL_META"
  if [ -n "${PYTHON_BIN:-}" ] && opb_python_compatible "$PYTHON_BIN"; then
    export OPB_PYTHON_BIN="$PYTHON_BIN"
  else
    unset OPB_PYTHON_BIN
  fi
}
