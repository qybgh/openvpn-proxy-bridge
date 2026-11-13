#!/bin/bash

opb_filter_profile() {
  local python_bin="${OPB_PYTHON_BIN:-$(opb_find_python || true)}"
  [ -n "$python_bin" ] || {
    echo '未找到可用的 Python 3.8 或更高版本。'
    return 1
  }
  "$python_bin" \
    "$OPB_BUNDLE_ROOT/tools/filter_profile.py" \
    "$OPB_SOURCE_PROFILE" "$OPB_BASE_PROFILE" "$OPB_AUTH_FILE"
}

opb_write_credentials() {
  local user="$1" password="$2" target="${3:-$OPB_AUTH_FILE}"
  [ -n "$user" ] && [ -n "$password" ] || return 1
  printf '%s\n%s\n' "$user" "$password" >"$target"
  chmod 600 "$target"
}

opb_update_credentials_atomic() {
  local user="$1" password="$2" temporary
  temporary="$OPB_AUTH_FILE.new.$$"
  if ! opb_write_credentials "$user" "$password" "$temporary"; then
    rm -f "$temporary"
    return 1
  fi
  if ! mv -f "$temporary" "$OPB_AUTH_FILE"; then
    rm -f "$temporary"
    return 1
  fi
  opb_chown_root "$OPB_AUTH_FILE"
}

opb_read_credentials() {
  local user password
  if [ "${OPB_TEST_MODE:-0}" = 1 ] && [ -n "${OPB_TEST_USERNAME:-}" ] && [ -n "${OPB_TEST_PASSWORD:-}" ]; then
    OPB_CREDENTIAL_USER="$OPB_TEST_USERNAME"
    OPB_CREDENTIAL_PASSWORD="$OPB_TEST_PASSWORD"
    return 0
  fi
  printf '公司 VPN 用户名: '
  read -r user
  printf '公司 VPN 密码（不显示）: '
  IFS= read -r -s password
  printf '\n'
  [ -n "$user" ] && [ -n "$password" ] || {
    unset password
    return 1
  }
  # Values are consumed by command orchestration after this function returns.
  # shellcheck disable=SC2034
  OPB_CREDENTIAL_USER="$user"
  # shellcheck disable=SC2034
  OPB_CREDENTIAL_PASSWORD="$password"
}
