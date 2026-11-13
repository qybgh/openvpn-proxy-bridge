#!/usr/bin/env python3
import pathlib
import re
import sys


SKIP_DIRECTIVES = {
    "max-routes",
    "auth-user-pass",
    "auth-retry",
    "verb",
    "resolv-retry",
    "socks-proxy",
    "socks-proxy-retry",
    "server-poll-timeout",
}


def transform_profile(source: str, auth_path: str) -> str:
    output = []
    in_inline_block = False

    for line in source.splitlines():
        stripped = line.strip()
        if re.match(r"^<[\w-]+>", stripped):
            in_inline_block = True
        directive = stripped.split()[0] if stripped else ""
        if in_inline_block or directive not in SKIP_DIRECTIVES:
            output.append(line)
        if re.match(r"^</[\w-]+>", stripped):
            in_inline_block = False

    output.extend(
        [
            f'auth-user-pass "{auth_path}"',
            "auth-retry none",
            "auth-nocache",
            "data-ciphers AES-256-GCM:AES-128-GCM:AES-256-CBC",
            "data-ciphers-fallback AES-256-CBC",
            "allow-compression asym",
            "connect-retry-max 1",
            "resolv-retry 10",
            "verb 3",
        ]
    )
    return "\n".join(output) + "\n"


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: filter_profile.py SOURCE TARGET AUTH_FILE", file=sys.stderr)
        return 2

    source_path, target_path, auth_path = map(pathlib.Path, sys.argv[1:])
    transformed = transform_profile(source_path.read_text(), str(auth_path))
    target_path.write_text(transformed)
    target_path.chmod(0o600)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
