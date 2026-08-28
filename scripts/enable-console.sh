#!/usr/bin/env bash
# OPT-IN: install the browser-based root console (console.html + exec.sh).
#
# !!! SECURITY WARNING !!!
# exec.sh is an UNAUTHENTICATED endpoint that runs arbitrary shell commands as
# root on the router. Only enable this on a device you physically control (USB
# tether / trusted LAN). NEVER enable it on a device whose web UI is reachable
# from the internet. Remove it with scripts/disable-console.sh when done.
#
# You are enabling a root command endpoint on purpose. Re-run with CONFIRM=yes.
set -euo pipefail

ADB="${ADB:-adb}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEV="$HERE/device"
WWW=/WEBSERVER/www

if [ "${CONFIRM:-}" != "yes" ]; then
  cat >&2 <<EOF
Refusing to enable the root web console without confirmation.
This installs an UNAUTHENTICATED root command endpoint on the router.
If you understand the risk and the device is not internet-exposed, run:

    CONFIRM=yes $0

EOF
  exit 1
fi

"$ADB" get-state >/dev/null 2>&1 || { echo "No ADB device found." >&2; exit 1; }

echo "[*] Installing web console (console.html + cgi-bin/exec.sh)..."
"$ADB" push "$DEV/WEBSERVER/www/console.html"        "$WWW/console.html"
"$ADB" shell "chmod 644 $WWW/console.html"
"$ADB" push "$DEV/WEBSERVER/www/cgi-bin/exec.sh"      "$WWW/cgi-bin/exec.sh"
"$ADB" shell "chmod 755 $WWW/cgi-bin/exec.sh"

echo "[*] Done. Open http://192.168.0.1/console.html"
echo "    Disable again with: scripts/disable-console.sh"
