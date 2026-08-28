#!/usr/bin/env bash
# Local render harness for the web-UI mod -- NO DEVICE NEEDED.
#
# Builds a throwaway web root containing the mod's real sigmod.js plus a mock of
# the stock M7350 DOM and static JSON stand-ins for the CGIs, then serves it on
# localhost so you can eyeball (and screenshot) the layout while iterating on
# the CSS. What you see is the real injection + real dark theme against a
# faithful copy of the stock page structure.
#
#   tools/mock/serve.sh [port]      -> http://127.0.0.1:8777/status.html
set -euo pipefail
PORT="${1:-8777}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
ROOT="${MOCK_ROOT:-${TMPDIR:-/tmp}}/m7350-mock"

rm -rf "$ROOT"; mkdir -p "$ROOT/cgi-bin"
cp "$REPO/device/WEBSERVER/www/sigmod.js" "$ROOT/sigmod.js"
[ -f "$REPO/device/WEBSERVER/www/darkmode.css" ] && cp "$REPO/device/WEBSERVER/www/darkmode.css" "$ROOT/" || true
cp "$HERE"/*.html "$HERE"/stock.css "$ROOT/"
cp "$HERE"/cgi-bin/* "$ROOT/cgi-bin/"

echo "[*] Mock web root: $ROOT"
echo "[*] http://127.0.0.1:$PORT/status.html   (login.html for the pre-auth page)"
cd "$ROOT"
exec python3 -m http.server "$PORT" --bind 127.0.0.1
