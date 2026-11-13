#!/usr/bin/env python3
import ipaddress
import pathlib
import socket
import sys
from typing import Optional


DEFAULT_PORT = 1194


def socket_protocol(proto: Optional[str]) -> str:
    return "tcp" if proto and proto.startswith("tcp") else "udp"


def parse_port(value: str, proto: Optional[str] = None) -> int:
    try:
        port = int(value)
    except ValueError:
        port = socket.getservbyname(value, socket_protocol(proto))
    if not 1 <= port <= 65535:
        raise ValueError(f"invalid port: {value}")
    return port


def resolve_ipv4(host: str, port: int, socket_type=socket.SOCK_DGRAM):
    try:
        address = ipaddress.ip_address(host)
        return [host] if address.version == 4 else []
    except ValueError:
        pass

    addresses = []
    for item in socket.getaddrinfo(
        host, port, family=socket.AF_INET, type=socket_type
    ):
        address = item[4][0]
        if address not in addresses:
            addresses.append(address)
    return addresses


def profile_defaults(lines):
    port = DEFAULT_PORT
    proto = None

    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith(("#", ";")):
            continue
        parts = stripped.split()
        if parts[0] == "proto" and len(parts) >= 2:
            proto = parts[1]

    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith(("#", ";")):
            continue
        parts = stripped.split()
        if parts[0] in {"port", "rport"} and len(parts) >= 2:
            try:
                port = parse_port(parts[1], proto)
            except (OSError, ValueError):
                pass
    return port, proto


def remote_fields(parts, default_port, default_proto):
    host = parts[1]
    port = default_port
    proto = default_proto

    if len(parts) >= 3:
        try:
            line_proto = parts[3] if len(parts) >= 4 else proto
            port = parse_port(parts[2], line_proto)
            if len(parts) >= 4:
                proto = line_proto
        except (OSError, ValueError):
            proto = parts[2]

    return host, port, proto


def expand_remote_line(line: str, default_port: int, default_proto: Optional[str]):
    stripped = line.strip()
    if not stripped or stripped.startswith(("#", ";")):
        return [line], 0
    parts = stripped.split()
    if parts[0] != "remote" or len(parts) < 2:
        return [line], 0

    host, port, proto = remote_fields(parts, default_port, default_proto)
    socket_type = socket.SOCK_STREAM if socket_protocol(proto) == "tcp" else socket.SOCK_DGRAM
    try:
        addresses = resolve_ipv4(host, port, socket_type)
    except OSError:
        return [line], 1
    if not addresses:
        return [line], 1

    suffix = [str(port)]
    if proto:
        suffix.append(proto)
    return [" ".join(["remote", address, *suffix]) for address in addresses], len(addresses)


def transform_profile(source: str, server_poll_timeout: int = 5):
    lines = source.splitlines()
    default_port, default_proto = profile_defaults(lines)
    output = []
    remote_count = 0
    for line in lines:
        if line.strip().split()[:1] == ["server-poll-timeout"]:
            continue
        expanded, count = expand_remote_line(line, default_port, default_proto)
        output.extend(expanded)
        remote_count += count
    output.append(f"server-poll-timeout {server_poll_timeout}")
    return "\n".join(output) + "\n", remote_count


def main() -> int:
    if len(sys.argv) != 4:
        print(
            "usage: resolve_remotes.py SOURCE TARGET SERVER_POLL_TIMEOUT",
            file=sys.stderr,
        )
        return 2
    source_path, target_path = map(pathlib.Path, sys.argv[1:3])
    server_poll_timeout = int(sys.argv[3])
    transformed, remote_count = transform_profile(
        source_path.read_text(), server_poll_timeout
    )
    target_path.write_text(transformed)
    target_path.chmod(0o600)
    state_path = target_path.with_name("remote-count.state")
    state_path.write_text(f"{max(remote_count, 1)}\n")
    state_path.chmod(0o600)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
