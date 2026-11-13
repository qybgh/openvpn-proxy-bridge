#!/usr/bin/env bats

setup() {
  export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  export OPB_TEST_MODE=1
  export OPB_BUNDLE_ROOT="$REPO_ROOT"
  export OPB_CLI_PATH="$REPO_ROOT/bin/openvpn-proxy-bridge"
  export OPB_TEST_INSTALL_DIR="$BATS_TEST_TMPDIR/install"
  export OPB_TEST_PLIST="$BATS_TEST_TMPDIR/LaunchDaemons/com.local.proxy-openvpn.plist"
  export OPB_TEST_USERNAME='test-user'
  export OPB_TEST_PASSWORD='test-password'

  source "$REPO_ROOT/lib/config.sh"
  source "$REPO_ROOT/lib/common.sh"
  source "$REPO_ROOT/lib/proxy.sh"
  source "$REPO_ROOT/lib/openvpn.sh"
  source "$REPO_ROOT/lib/homebrew.sh"
  source "$REPO_ROOT/lib/service.sh"
  source "$REPO_ROOT/lib/commands.sh"
}

@test "setup installs files but does not bootstrap a connection" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  touch "$BATS_TEST_TMPDIR/bin/brew" "$BATS_TEST_TMPDIR/bin/openvpn"
  chmod 755 "$BATS_TEST_TMPDIR/bin/brew" "$BATS_TEST_TMPDIR/bin/openvpn"
  profile="$BATS_TEST_TMPDIR/test.ovpn"
  printf 'client\nproto udp\nremote 203.0.113.10 1194\n' > "$profile"

  opb_prepare_service_files() {
    mkdir -p "$(dirname "$OPB_PLIST")"
    touch "$OPB_PLIST"
  }
  launchctl() {
    printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/launchctl.log"
  }

  run opb_cmd_setup_root "$profile" "$BATS_TEST_TMPDIR/bin/brew" "$BATS_TEST_TMPDIR/bin/openvpn" /usr/bin/python3 1 '' tester
  [ "$status" -eq 0 ]
  [ -f "$OPB_BASE_PROFILE" ]
  [ -f "$OPB_AUTH_FILE" ]
  [ ! -f "$OPB_CONNECTED_STATE" ]
  grep -q '^PYTHON_BIN=/usr/bin/python3$' "$OPB_INSTALL_META"
  grep -q '^disable system/com.local.proxy-openvpn$' "$BATS_TEST_TMPDIR/launchctl.log"
  ! grep -q 'bootstrap' "$BATS_TEST_TMPDIR/launchctl.log"
}

@test "failed setup rolls back the partial installation" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  touch "$BATS_TEST_TMPDIR/bin/brew" "$BATS_TEST_TMPDIR/bin/openvpn"
  chmod 755 "$BATS_TEST_TMPDIR/bin/brew" "$BATS_TEST_TMPDIR/bin/openvpn"
  profile="$BATS_TEST_TMPDIR/test.ovpn"
  printf 'client\nproto udp\n' > "$profile"

  opb_filter_profile() { return 80; }

  run opb_cmd_setup_root "$profile" "$BATS_TEST_TMPDIR/bin/brew" "$BATS_TEST_TMPDIR/bin/openvpn" /usr/bin/python3 1 '' tester
  [ "$status" -eq 80 ]
  [ ! -e "$OPB_INSTALL_DIR" ]
  [ ! -e "$OPB_PLIST" ]
}

@test "start returns immediately when already connected" {
  mkdir -p "$OPB_INSTALL_DIR"
  touch "$OPB_CONNECTED_STATE"
  launchctl() { return 0; }
  pgrep() { return 0; }
  opb_connect_service() { echo unexpected; return 99; }

  run opb_cmd_start
  [ "$status" -eq 0 ]
  [[ "$output" == *"无需重复启动"* ]]
  [[ "$output" != *"unexpected"* ]]
}

@test "AUTH_FAILED is not retried" {
  printf '0\n' > "$BATS_TEST_TMPDIR/count"
  opb_bootstrap_service() {
    count="$(cat "$BATS_TEST_TMPDIR/count")"
    printf '%s\n' "$((count + 1))" > "$BATS_TEST_TMPDIR/count"
  }
  opb_wait_for_connection() { return 3; }
  opb_stop_service() { :; }

  run opb_connect_service test
  [ "$status" -eq 3 ]
  [[ "$output" == *"AUTH_FAILED"* ]]
  [ "$(cat "$BATS_TEST_TMPDIR/count")" -eq 1 ]
}

@test "transport failure retries exactly once" {
  printf '0\n' > "$BATS_TEST_TMPDIR/count"
  opb_bootstrap_service() {
    count="$(cat "$BATS_TEST_TMPDIR/count")"
    printf '%s\n' "$((count + 1))" > "$BATS_TEST_TMPDIR/count"
  }
  opb_wait_for_connection() { return 2; }
  opb_stop_service() { :; }

  run opb_connect_service test
  [ "$status" -eq 1 ]
  [ "$(cat "$BATS_TEST_TMPDIR/count")" -eq 2 ]
  [[ "$output" == *"第 2 次连接尝试"* ]]
}

@test "uninstall stops service before removing install directory" {
  mkdir -p "$OPB_INSTALL_DIR"
  printf 'OPENVPN_INSTALLED_BY_SCRIPT=0\n' > "$OPB_INSTALL_META"
  printf 'FORMULAE_INSTALLED_BY_SCRIPT=\n' >> "$OPB_INSTALL_META"
  printf 'OWNER_USER=tester\n' >> "$OPB_INSTALL_META"
  printf 'BREW_BIN=/bin/false\n' >> "$OPB_INSTALL_META"

  opb_stop_service() {
    [ -d "$OPB_INSTALL_DIR" ] || return 90
    printf 'stop\n' >> "$BATS_TEST_TMPDIR/order"
  }
  opb_wait_for_proxy_release() {
    printf 'wait\n' >> "$BATS_TEST_TMPDIR/order"
  }
  opb_remove_install_dir() {
    printf 'remove\n' >> "$BATS_TEST_TMPDIR/order"
    rm -rf "$OPB_INSTALL_DIR"
  }
  launchctl() { :; }

  run opb_cmd_uninstall_root /bin/false tester
  [ "$status" -eq 0 ]
  expected="$(printf 'stop\nwait\nremove')"
  [ "$(cat "$BATS_TEST_TMPDIR/order")" = "$expected" ]
  [ ! -e "$OPB_INSTALL_DIR" ]
}

@test "explicit stop waits for the baseline release window before reporting success" {
  mkdir -p "$OPB_INSTALL_DIR"
  touch "$OPB_LAST_STOP_STATE"
  opb_stop_service() { printf 'stop\n' >> "$BATS_TEST_TMPDIR/order"; }
  opb_wait_for_proxy_release() {
    printf 'wait:%s\n' "$1" >> "$BATS_TEST_TMPDIR/order"
  }

  run opb_cmd_stop
  [ "$status" -eq 0 ]
  expected="$(printf 'stop\nwait:%s' "$OPB_PROXY_RELEASE_WAIT")"
  [ "$(cat "$BATS_TEST_TMPDIR/order")" = "$expected" ]
  [ ! -e "$OPB_LAST_STOP_STATE" ]
  [[ "$output" == *"已停止"* ]]
}

@test "credential update replaces the file atomically" {
  mkdir -p "$OPB_INSTALL_DIR"
  printf 'old-user\nold-password\n' > "$OPB_AUTH_FILE"

  run opb_update_credentials_atomic new-user new-password
  [ "$status" -eq 0 ]
  [ "$(sed -n '1p' "$OPB_AUTH_FILE")" = new-user ]
  [ "$(sed -n '2p' "$OPB_AUTH_FILE")" = new-password ]
  [ ! -e "$OPB_AUTH_FILE.new.$$" ]
}

@test "stop removes transient runtime state" {
  mkdir -p "$OPB_INSTALL_DIR"
  touch "$OPB_CONNECTED_STATE" "$OPB_ATTEMPT_STATE" "$OPB_TRANSPORT_STATE"
  touch "$OPB_FAILURE_STATE" "$OPB_RUNTIME_PROFILE" "$OPB_CURRENT_PROXY_STATE"
  launchctl() { return 1; }
  pgrep() { return 1; }
  opb_cleanup_proxy_sessions() { :; }

  run opb_stop_service
  [ "$status" -eq 0 ]
  [ ! -e "$OPB_CONNECTED_STATE" ]
  [ ! -e "$OPB_ATTEMPT_STATE" ]
  [ ! -e "$OPB_TRANSPORT_STATE" ]
  [ ! -e "$OPB_FAILURE_STATE" ]
  [ ! -e "$OPB_RUNTIME_PROFILE" ]
  [ ! -e "$OPB_CURRENT_PROXY_STATE" ]
}

@test "stop clears proxy session before unloading the service" {
  mkdir -p "$OPB_INSTALL_DIR"
  launchctl() {
    printf 'launchctl:%s\n' "$*" >>"$BATS_TEST_TMPDIR/order"
    return 1
  }
  pgrep() { return 1; }
  opb_cleanup_proxy_sessions() {
    printf 'proxy-cleanup\n' >>"$BATS_TEST_TMPDIR/order"
  }

  run opb_stop_service
  [ "$status" -eq 0 ]
  cleanup_line="$(grep -n '^proxy-cleanup$' "$BATS_TEST_TMPDIR/order" | head -1 | cut -d: -f1)"
  bootout_line="$(grep -n '^launchctl:bootout' "$BATS_TEST_TMPDIR/order" | head -1 | cut -d: -f1)"
  [ -n "$cleanup_line" ]
  [ -n "$bootout_line" ]
  [ "$cleanup_line" -lt "$bootout_line" ]
}

@test "runtime classifies exhausted remote endpoints as transport failure" {
  runtime_dir="$BATS_TEST_TMPDIR/runtime"
  mkdir -p "$runtime_dir"
  fake_openvpn="$BATS_TEST_TMPDIR/openvpn"
  cat >"$fake_openvpn" <<'SH'
#!/bin/bash
while [ "$#" -gt 0 ]; do
  if [ "$1" = --log-append ]; then
    shift
    log="$1"
  fi
  shift
done
printf '%s\n' 'Server poll timeout, restarting' >>"$log"
printf '%s\n' 'All connections have been connect-retry-max (1) times unsuccessful, exiting' >>"$log"
exit 1
SH
  chmod 755 "$fake_openvpn"
  printf 'OPENVPN_BIN=%q\n' "$fake_openvpn" >"$runtime_dir/install.meta"
  printf 'client\nproto udp\nremote 203.0.113.10 1194\n' >"$runtime_dir/base.ovpn"
  cat >"$runtime_dir/detect-proxy.sh" <<'SH'
#!/bin/bash
echo '127.0.0.1 1080'
SH
  cat >"$runtime_dir/resolve-remotes.py" <<'PY'
#!/usr/bin/env python3
import pathlib, sys
pathlib.Path(sys.argv[2]).write_text(pathlib.Path(sys.argv[1]).read_text())
PY
  chmod 755 "$runtime_dir/detect-proxy.sh" "$runtime_dir/resolve-remotes.py"

  run /bin/bash "$REPO_ROOT/assets/run-openvpn.sh" "$runtime_dir"
  [ "$status" -eq 1 ]
  [ "$(cat "$runtime_dir/failure.state")" = transport ]
}

@test "connection wait handles delayed failure classification after process exit" {
  mkdir -p "$OPB_INSTALL_DIR"
  launchctl() { return 1; }
  pgrep() { return 1; }
  (
    sleep 0.2
    printf 'transport\n' >"$OPB_FAILURE_STATE"
  ) &

  run opb_wait_for_connection 5
  [ "$status" -eq 2 ]
}

@test "transport wait scales with the generated remote count" {
  mkdir -p "$OPB_INSTALL_DIR"
  printf '8\n' >"$OPB_REMOTE_COUNT_STATE"
  launchctl() { return 0; }
  pgrep() { return 0; }
  sleep() {
    count="$(cat "$BATS_TEST_TMPDIR/sleeps" 2>/dev/null || echo 0)"
    printf '%s\n' "$((count + 1))" >"$BATS_TEST_TMPDIR/sleeps"
  }

  run opb_wait_for_connection 80
  [ "$status" -eq 2 ]
  [ "$(cat "$BATS_TEST_TMPDIR/sleeps")" -eq 50 ]
}

@test "unmanaged Homebrew OpenVPN is preserved" {
  opb_as_console_user() {
    printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/brew.log"
  }

  run opb_uninstall_managed_formulae tester /opt/homebrew/bin/brew 0 'openvpn,lz4'
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/brew.log" ]
}

@test "managed Homebrew OpenVPN is uninstalled" {
  opb_as_console_user() {
    printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/brew.log"
    case "$*" in
      *' uses --installed '*) return 0 ;;
    esac
    return 0
  }

  run opb_uninstall_managed_formulae tester /opt/homebrew/bin/brew 1 'openvpn'
  [ "$status" -eq 0 ]
  grep -q 'uninstall openvpn' "$BATS_TEST_TMPDIR/brew.log"
}

@test "manual proxy accepts loopback endpoint" {
  mkdir -p "$OPB_INSTALL_DIR"
  run opb_save_manual_proxy 127.0.0.1 1080
  [ "$status" -eq 0 ]
  [ "$(cat "$OPB_PROXY_CONFIG")" = '127.0.0.1 1080' ]
}

@test "manual proxy rejects remote addresses and invalid ports" {
  mkdir -p "$OPB_INSTALL_DIR"
  run opb_save_manual_proxy 192.0.2.10 1080
  [ "$status" -eq 1 ]
  run opb_save_manual_proxy 127.0.0.1 65536
  [ "$status" -eq 1 ]
  [ ! -e "$OPB_PROXY_CONFIG" ]
}

@test "automatic proxy discovery reads macOS SOCKS settings" {
  mkdir -p "$OPB_INSTALL_DIR"
  scutil_mock="$BATS_TEST_TMPDIR/scutil"
  nc_mock="$BATS_TEST_TMPDIR/nc"
  cat > "$scutil_mock" <<'SH'
#!/bin/bash
cat <<'EOF'
<dictionary> {
  SOCKSEnable : 1
  SOCKSPort : 12450
  SOCKSProxy : 127.0.0.1
}
EOF
SH
  printf '#!/bin/bash\nexit 0\n' > "$nc_mock"
  chmod 755 "$scutil_mock" "$nc_mock"

  run env OPB_TEST_MODE=1 OPB_SCUTIL_BIN="$scutil_mock" OPB_NC_BIN="$nc_mock" \
    /bin/bash "$REPO_ROOT/assets/detect-proxy.sh" "$OPB_INSTALL_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = '127.0.0.1 12450' ]
}

@test "root ownership helpers place macOS options before owner and paths" {
  chown_mock="$BATS_TEST_TMPDIR/chown"
  cat > "$chown_mock" <<'SH'
#!/bin/bash
printf '<%s>\n' "$@" >> "$OPB_CHOWN_LOG"
SH
  chmod 755 "$chown_mock"
  export OPB_CHOWN_BIN="$chown_mock"
  export OPB_CHOWN_LOG="$BATS_TEST_TMPDIR/chown.log"

  run opb_chown_root '/tmp/one file'
  [ "$status" -eq 0 ]
  run opb_chown_root_recursive '/tmp/tree path'
  [ "$status" -eq 0 ]

  expected="$(cat <<'EOF'
<root:wheel>
</tmp/one file>
<-R>
<root:wheel>
</tmp/tree path>
EOF
)"
  [ "$(cat "$OPB_CHOWN_LOG")" = "$expected" ]
}

@test "installed metadata restores the recorded Python path for runtime commands" {
  mkdir -p "$OPB_INSTALL_DIR"
  custom_python="$BATS_TEST_TMPDIR/python3"
  printf '#!/bin/bash\nexit 0\n' >"$custom_python"
  chmod 755 "$custom_python"
  printf 'PYTHON_BIN=%q\n' "$custom_python" >"$OPB_INSTALL_META"

  opb_load_install_meta
  [ "$OPB_PYTHON_BIN" = "$custom_python" ]
}

@test "invalid recorded Python path is discarded for runtime fallback" {
  mkdir -p "$OPB_INSTALL_DIR"
  printf 'PYTHON_BIN=%q\n' '/missing/python3' >"$OPB_INSTALL_META"
  export OPB_PYTHON_BIN='/stale/python3'

  opb_load_install_meta
  [ -z "${OPB_PYTHON_BIN:-}" ]
}

@test "Python discovery rejects unsupported versions and selects a compatible interpreter" {
  old_python="$BATS_TEST_TMPDIR/python-old"
  new_python="$BATS_TEST_TMPDIR/python-new"
  printf '#!/bin/bash\nexit 1\n' >"$old_python"
  printf '#!/bin/bash\nexit 0\n' >"$new_python"
  chmod 755 "$old_python" "$new_python"

  run opb_python_compatible "$old_python"
  [ "$status" -eq 1 ]
  run opb_python_compatible "$new_python"
  [ "$status" -eq 0 ]
}

@test "active CLI uses a snapshot when source files change" {
  bundle="$BATS_TEST_TMPDIR/bundle"
  mkdir -p "$bundle"
  cp -R "$REPO_ROOT/bin" "$REPO_ROOT/lib" "$REPO_ROOT/assets" "$REPO_ROOT/tools" "$bundle/"

  cat >> "$bundle/lib/commands.sh" <<'SH'
opb_main() {
  while [ ! -e "$OPB_TEST_SNAPSHOT_GATE" ]; do sleep 0.1; done
  echo original
}
SH

  output_file="$BATS_TEST_TMPDIR/output"
  OPB_TEST_MODE=1 OPB_TEST_SNAPSHOT=1 OPB_TEST_SNAPSHOT_GATE="$BATS_TEST_TMPDIR/gate" \
    /bin/bash "$bundle/bin/openvpn-proxy-bridge" status > "$output_file" &
  cli_pid=$!
  sleep 0.5
  cat >> "$bundle/lib/commands.sh" <<'SH'
opb_main() { echo changed; }
SH
  touch "$BATS_TEST_TMPDIR/gate"
  wait "$cli_pid"

  [ "$(cat "$output_file")" = original ]
}
