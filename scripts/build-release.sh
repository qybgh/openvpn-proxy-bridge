#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT/dist"
SKIP_CHECKS=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --skip-checks)
      SKIP_CHECKS=1
      ;;
    --output)
      shift
      OUTPUT_DIR="${1:-}"
      [ -n "$OUTPUT_DIR" ] || {
        echo '--output requires a directory' >&2
        exit 2
      }
      ;;
    *)
      echo "unknown option: $1" >&2
      exit 2
      ;;
  esac
  shift
done

VERSION="$(tr -d '[:space:]' <"$ROOT/VERSION")"
case "$VERSION" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *)
    echo "invalid VERSION: $VERSION" >&2
    exit 1
    ;;
esac

if [ "$SKIP_CHECKS" -eq 0 ]; then
  "$ROOT/tests/check.sh" --skip-build
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
STAGING="$(mktemp -d /tmp/openvpn-proxy-bridge-release.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT INT TERM

PACKAGE_NAME="openvpn-proxy-bridge-$VERSION"
PACKAGE_ROOT="$STAGING/$PACKAGE_NAME"
mkdir -p "$PACKAGE_ROOT/libexec"

cp "$ROOT/README.md" "$ROOT/LICENSE" "$ROOT/VERSION" "$PACKAGE_ROOT/"
cp -R "$ROOT/bin" "$ROOT/lib" "$ROOT/assets" "$ROOT/tools" "$PACKAGE_ROOT/libexec/"
"$ROOT/scripts/generate-launchers.sh" "$PACKAGE_ROOT"

chmod 755 "$PACKAGE_ROOT"/*.command
chmod 755 "$PACKAGE_ROOT/libexec/bin/openvpn-proxy-bridge"
chmod 755 "$PACKAGE_ROOT/libexec/assets"/*.sh "$PACKAGE_ROOT/libexec/tools"/*.py

"$ROOT/scripts/privacy-scan.sh" "$PACKAGE_ROOT"

find "$PACKAGE_ROOT" -exec touch -t 202601010000 {} +

ARCHIVE="$OUTPUT_DIR/$PACKAGE_NAME.tar.gz"
CHECKSUM="$ARCHIVE.sha256"
COPYFILE_DISABLE=1 find "$STAGING/$PACKAGE_NAME" -print | LC_ALL=C sort |
  sed "s#^$STAGING/##" |
  COPYFILE_DISABLE=1 tar -C "$STAGING" --uid 0 --gid 0 --uname root --gname wheel --no-xattrs -cf - -T - |
  gzip -n >"$ARCHIVE"
(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$(basename "$ARCHIVE")" >"$(basename "$CHECKSUM")"
)

printf '%s\n%s\n' "$ARCHIVE" "$CHECKSUM"
