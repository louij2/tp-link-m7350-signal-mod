#!/usr/bin/env bash
# Fast redeploy of the web-UI mod to the device over ADB.
# Pushes the JS + CGIs and AUTO-BUMPS the ?v= cache-buster on the injected
# <script> so browsers always fetch your latest edit (no manual version bump).
# Does NOT restart the signal daemon (use scripts/install.sh for a full install).
#
# Typical loop: edit device/WEBSERVER/www/sigmod.js in VS Code -> save ->
#   scripts/deploy.sh   (or let the git post-merge hook run it for you)
set -euo pipefail
ADB="${ADB:-adb}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEV="$HERE/device"; WWW=/WEBSERVER/www
say(){ printf '\033[1;36m[*]\033[0m %s\n' "$1"; }

"$ADB" get-state >/dev/null 2>&1 || { echo "No ADB device connected — skipping deploy."; exit 0; }

say "Pushing web assets..."
for f in sigmod.js; do
  "$ADB" push "$DEV/WEBSERVER/www/$f" "$WWW/$f" >/dev/null && "$ADB" shell "chmod 644 $WWW/$f"
done
for c in signal_stats.sh sysinfo.sh control.sh deviceinfo.sh metrics.sh; do
  [ -f "$DEV/WEBSERVER/www/cgi-bin/$c" ] || continue
  "$ADB" push "$DEV/WEBSERVER/www/cgi-bin/$c" "$WWW/cgi-bin/$c" >/dev/null && "$ADB" shell "chmod 755 $WWW/cgi-bin/$c"
done

# Bump the cache-buster to the current epoch so edits show without a hard-refresh.
V="$("$ADB" shell 'cut -d. -f1 /proc/uptime' | tr -d '\r')$RANDOM"
say "Cache-busting sigmod.js?v=$V ..."
for p in login.html settings.html; do
  "$ADB" shell "sed -i 's#sigmod.js?v=[0-9]*#sigmod.js?v=$V#g; s#src=\"sigmod.js\"#src=\"sigmod.js?v=$V\"#g' $WWW/$p" || true
done
say "Deployed. Refresh the page (http://<router-ip>/)."
