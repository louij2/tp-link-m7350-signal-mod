#!/usr/bin/env bash
# Bundle a release tarball of the mod: the device payload + installer scripts +
# docs. The resulting archive is what gets attached to a GitHub Release; a user
# downloads it, extracts, connects the router over root ADB, and runs
# scripts/install.sh.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
VER="$(cat "$HERE/VERSION" 2>/dev/null || echo dev)"
OUT="$HERE/dist"; mkdir -p "$OUT"
NAME="m7350-extreme-mod-$VER"
STAGE="$(mktemp -d)/$NAME"; mkdir -p "$STAGE"

cp -R "$HERE/device" "$HERE/scripts" "$STAGE/"
for f in README.md CHANGELOG.md LICENSE VERSION; do [ -f "$HERE/$f" ] && cp "$HERE/$f" "$STAGE/"; done

TAR="$OUT/$NAME.tar.gz"
( cd "$(dirname "$STAGE")" && tar czf "$TAR" "$NAME" )
rm -rf "$(dirname "$STAGE")"

echo "Built $TAR"
( cd "$OUT" && shasum -a 256 "$NAME.tar.gz" | tee "$NAME.tar.gz.sha256" )
