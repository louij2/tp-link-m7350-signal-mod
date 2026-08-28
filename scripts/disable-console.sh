#!/usr/bin/env bash
# Remove the browser-based root console (console.html + exec.sh).
set -euo pipefail
ADB="${ADB:-adb}"
WWW=/WEBSERVER/www
"$ADB" get-state >/dev/null 2>&1 || { echo "No ADB device found." >&2; exit 1; }
echo "[*] Removing web console..."
"$ADB" shell "rm -f $WWW/console.html $WWW/cgi-bin/exec.sh"
echo "[*] Done."
