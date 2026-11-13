#!/bin/bash

opb_prepare_setup_as_user() {
  local profile brew_bin openvpn_preexisting=0
  local formulae_before formulae_after formulae_installed='' openvpn_bin python_bin manage_existing

  brew_bin="$(opb_find_brew || true)"
  [ -n "$brew_bin" ] || {
    echo '未找到 Homebrew。请先安装 Homebrew，再重新运行本脚本。'
    return 1
  }

  python_bin="$(opb_find_python || true)"
  [ -n "$python_bin" ] || {
    echo '未找到 Python 3.8 或更高版本。请先运行 brew install python，再重新安装。'
    return 1
  }

  profile="$(opb_choose_profile)"
  formulae_before="$($brew_bin list --formula -1 2>/dev/null | sort)"
  if "$brew_bin" list --versions openvpn >/dev/null 2>&1; then
    openvpn_preexisting=1
  fi
  if [ "$openvpn_preexisting" -eq 1 ]; then
    printf '检测到已有 Homebrew OpenVPN。卸载本工具时是否一并托管卸载？[y/N]: '
    read -r manage_existing
    case "${manage_existing:-N}" in
      [Yy]*)
        openvpn_preexisting=0
        formulae_installed="openvpn,$($brew_bin deps --formula openvpn 2>/dev/null | paste -sd, -)"
        ;;
    esac
  else
    echo '正在通过 Homebrew 安装 OpenVPN...'
    "$brew_bin" install openvpn
  fi

  formulae_after="$($brew_bin list --formula -1 2>/dev/null | sort)"
  if [ -z "$formulae_installed" ]; then
    formulae_installed="$(comm -13 \
      <(printf '%s\n' "$formulae_before") \
      <(printf '%s\n' "$formulae_after") | paste -sd, -)"
  fi
  openvpn_bin="$($brew_bin --prefix openvpn)/sbin/openvpn"

  opb_run_as_root setup "$profile" "$brew_bin" "$openvpn_bin" "$python_bin" \
    "$openvpn_preexisting" "$formulae_installed" "$(id -un)"
}

opb_uninstall_managed_formulae() {
  local owner_user="$1" brew_bin="$2" openvpn_owned="$3" formulae="$4"
  local formula users

  [ "$openvpn_owned" = 1 ] && [ -x "$brew_bin" ] || return 0
  opb_as_console_user "$owner_user" "$brew_bin" uninstall openvpn || true

  IFS=',' read -r -a managed_formulae <<<"$formulae"
  for _ in 1 2 3; do
    for formula in "${managed_formulae[@]}"; do
      [ -n "$formula" ] && [ "$formula" != openvpn ] || continue
      opb_as_console_user "$owner_user" "$brew_bin" list --versions "$formula" >/dev/null 2>&1 || continue
      users="$(opb_as_console_user "$owner_user" "$brew_bin" uses --installed "$formula" 2>/dev/null || true)"
      if [ -z "$users" ]; then
        opb_as_console_user "$owner_user" "$brew_bin" uninstall "$formula" || true
      fi
    done
  done
}
