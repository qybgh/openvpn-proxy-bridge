#!/bin/bash
# shellcheck disable=SC2034

OPB_LABEL='com.local.proxy-openvpn'

if [ "${OPB_TEST_MODE:-0}" = 1 ]; then
  OPB_INSTALL_DIR="${OPB_TEST_INSTALL_DIR:-/tmp/openvpn-proxy-bridge-test/Proxy-OpenVPN}"
  OPB_PLIST="${OPB_TEST_PLIST:-/tmp/openvpn-proxy-bridge-test/com.local.proxy-openvpn.plist}"
else
  OPB_INSTALL_DIR='/Library/Application Support/Proxy-OpenVPN'
  OPB_PLIST="/Library/LaunchDaemons/$OPB_LABEL.plist"
fi

OPB_CONNECT_TIMEOUT=130
OPB_DEFAULT_TRANSPORT_TIMEOUT=25
OPB_SERVER_POLL_TIMEOUT=5
OPB_TRANSPORT_GRACE=10
OPB_PROXY_RELEASE_WAIT=8

OPB_RUN_SCRIPT="$OPB_INSTALL_DIR/run-openvpn.sh"
OPB_DETECT_SCRIPT="$OPB_INSTALL_DIR/detect-proxy.sh"
OPB_SOURCE_PROFILE="$OPB_INSTALL_DIR/source.ovpn"
OPB_BASE_PROFILE="$OPB_INSTALL_DIR/base.ovpn"
OPB_RUNTIME_PROFILE="$OPB_INSTALL_DIR/runtime.ovpn"
OPB_AUTH_FILE="$OPB_INSTALL_DIR/auth.txt"
OPB_INSTALL_META="$OPB_INSTALL_DIR/install.meta"
OPB_PROXY_CONFIG="$OPB_INSTALL_DIR/proxy.conf"
OPB_CURRENT_PROXY_STATE="$OPB_INSTALL_DIR/current-proxy.state"
OPB_REMOTE_COUNT_STATE="$OPB_INSTALL_DIR/remote-count.state"
OPB_CONNECTED_STATE="$OPB_INSTALL_DIR/connected.state"
OPB_TRANSPORT_STATE="$OPB_INSTALL_DIR/transport.state"
OPB_FAILURE_STATE="$OPB_INSTALL_DIR/failure.state"
OPB_ATTEMPT_STATE="$OPB_INSTALL_DIR/attempt.started"
OPB_LAST_STOP_STATE="$OPB_INSTALL_DIR/last-stop.state"
OPB_OPENVPN_LOG="$OPB_INSTALL_DIR/openvpn.log"
OPB_LAUNCHD_LOG="$OPB_INSTALL_DIR/launchd.log"
