#!/usr/bin/env bats

setup() {
  export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  export TEST_ROOT="$BATS_TEST_TMPDIR/release package"
  mkdir -p "$TEST_ROOT/libexec/bin"
  cat > "$TEST_ROOT/libexec/bin/openvpn-proxy-bridge" <<'SH'
#!/bin/bash
printf '%s\n' "$1"
SH
  chmod 755 "$TEST_ROOT/libexec/bin/openvpn-proxy-bridge"
  "$REPO_ROOT/scripts/generate-launchers.sh" "$TEST_ROOT"
}

@test "all release launchers map to their declared action" {
  while IFS='|' read -r filename action; do
    run /bin/bash "$TEST_ROOT/$filename"
    [ "$status" -eq 0 ]
    [ "$output" = "$action" ]
  done < "$REPO_ROOT/packaging/actions.tsv"
}

@test "launchers work when the release path contains spaces" {
  run /bin/bash "$TEST_ROOT/start-company-vpn.command"
  [ "$status" -eq 0 ]
  [ "$output" = "start" ]
}
