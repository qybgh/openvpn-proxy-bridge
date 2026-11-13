#!/usr/bin/env python3
import ipaddress
import json
import pathlib
import re
import socket
import sys
import time
import urllib.request
from urllib.parse import quote


def profile_targets(profile_text: str):
    targets = set()
    for line in profile_text.splitlines():
        match = re.match(r"^\s*remote\s+(\S+)\s+(\d+)", line)
        if not match:
            continue
        host, port = match.group(1), int(match.group(2))
        try:
            ips = {host} if ipaddress.ip_address(host) else set()
        except ValueError:
            try:
                ips = {
                    item[4][0]
                    for item in socket.getaddrinfo(
                        host, port, type=socket.SOCK_DGRAM
                    )
                }
            except OSError:
                ips = set()
        targets.update((ip, port) for ip in ips)
    return targets


def controller_ports(proxy_port: int):
    candidates = []
    if proxy_port > 10:
        candidates.append(proxy_port - 10)
    candidates.extend([9090, 9097])
    return list(dict.fromkeys(candidates))


def matching_connection_ids(payload, targets):
    result = []
    for connection in payload.get("connections", []):
        metadata = connection.get("metadata") or {}
        destination = metadata.get("destinationIP") or ""
        try:
            port = int(metadata.get("destinationPort") or 0)
        except (TypeError, ValueError):
            continue
        if (destination, port) in targets and connection.get("id"):
            result.append(connection["id"])
    return result


def load_connections(base: str):
    with urllib.request.urlopen(base + "/connections", timeout=0.8) as response:
        return json.load(response)


def cleanup(profile_path: pathlib.Path, proxy_port: int) -> int:
    targets = profile_targets(profile_path.read_text(errors="ignore"))
    deleted = 0
    for controller_port in controller_ports(proxy_port):
        base = f"http://127.0.0.1:{controller_port}"
        try:
            payload = load_connections(base)
        except Exception:
            continue

        for _ in range(5):
            connection_ids = matching_connection_ids(payload, targets)
            if not connection_ids:
                break
            for connection_id in connection_ids:
                request = urllib.request.Request(
                    base + "/connections/" + quote(connection_id, safe=""),
                    method="DELETE",
                )
                try:
                    urllib.request.urlopen(request, timeout=0.8).read()
                    deleted += 1
                except Exception:
                    pass
            time.sleep(0.4)
            try:
                payload = load_connections(base)
            except Exception:
                break
        break
    return deleted


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "usage: cleanup_proxy_sessions.py PROFILE PROXY_PORT", file=sys.stderr
        )
        return 2
    deleted = cleanup(pathlib.Path(sys.argv[1]), int(sys.argv[2]))
    print(deleted)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
