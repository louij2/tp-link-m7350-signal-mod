#!/usr/bin/env bash
# Snapshot the router's live web root + the mod's device files into a local,
# timestamped folder. Run this BEFORE modding a fresh device so you always have
# a pristine copy to restore, and any time you want a checkpoint.
set -euo pipefail

ADB="${ADB:-adb}"
WWW=/WEBSERVER/www
# Timestamp (passed in or derived); avoids depending on the device clock.
STAMP="${1:-$(date +%Y%m%d-%H%M%S)}"
OUT="backup-$STAMP"
say(){ printf '\033[1;36m[*]\033[0m %s\n' "$1"; }

"$ADB" get-state >/dev/null 2>&1 || { echo "No ADB device found." >&2; exit 1; }
. "$(cd "$(dirname "$0")" && pwd)/lib/assert-device.sh"; assert_is_m7350

mkdir -p "$OUT/www/cgi-bin" "$OUT/usr-bin" "$OUT/etc-init.d"
say "Pulling web root..."
"$ADB" pull "$WWW/." "$OUT/www/" >/dev/null 2>&1 || true

say "Pulling mod device files (if present)..."
"$ADB" pull /usr/bin/signal_poll.sh   "$OUT/usr-bin/signal_poll.sh"   >/dev/null 2>&1 || true
"$ADB" pull /etc/init.d/signal_poll   "$OUT/etc-init.d/signal_poll"   >/dev/null 2>&1 || true

say "Backup written to ./$OUT"
find "$OUT" -type f | sort | sed 's/^/    /'
