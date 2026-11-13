#!/usr/bin/env python3
import ast
import pathlib
import re


root = pathlib.Path(__file__).resolve().parents[1]
source = (root / "setup-company-vpn.command").read_text()
blocks = re.findall(r"<<'PY'[^\n]*\n(.*?)\nPY", source, re.DOTALL)

if not blocks:
    raise SystemExit("No embedded Python blocks found")

for index, block in enumerate(blocks, start=1):
    try:
        ast.parse(block)
    except SyntaxError as error:
        raise SystemExit(f"Embedded Python block {index} is invalid: {error}") from error

print(f"Validated {len(blocks)} embedded Python blocks.")
