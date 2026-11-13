#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DESTINATION="${1:-}"

if [ -z "$DESTINATION" ]; then
  echo 'usage: generate-launchers.sh DESTINATION' >&2
  exit 2
fi

mkdir -p "$DESTINATION"

while IFS='|' read -r filename action; do
  [ -n "$filename" ] && [ -n "$action" ] || continue
  sed "s/@ACTION@/$action/g" "$ROOT/packaging/launcher.command.template" >"$DESTINATION/$filename"
  chmod 755 "$DESTINATION/$filename"
done <"$ROOT/packaging/actions.tsv"
