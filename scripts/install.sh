#!/usr/bin/env bash
# Install the M7350 LTE signal-stats + dark-theme mod over ADB.
#
# Prerequisites:
#   - ADB enabled on the router (see the README: usb_composition 902B) and the
#     device connected over USB (`adb devices` shows it).
#   - `adb` on your PATH, or set ADB=/path/to/adb.
#
# This is idempotent: it backs up the stock pages once, then (re)deploys the
# mod. It does NOT install the web console (that is opt-in: scripts/enable-console.sh).
set -euo pipefail

ADB="${ADB:-adb}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEV="$HERE/device"
WWW=/WEBSERVER/www

say(){ printf '\033[1;36m[*]\033[0m %s\n' "$1"; }

say "Checking for a connected device..."
"$ADB" get-state >/dev/null 2>&1 || {
  echo "No ADB device found. Enable ADB on the router and connect USB." >&2
  exit 1
}
. "$(cd "$(dirname "$0")" && pwd)/lib/assert-device.sh"; assert_is_m7350

say "Backing up stock pages (once)..."
for f in login.html status.html settings.html; do
  "$ADB" shell "[ -e $WWW/$f ] && { [ -e $WWW/$f.bak ] || cp $WWW/$f $WWW/$f.bak; }" || true
done

say "Deploying signal daemon + init script..."
"$ADB" push "$DEV/usr/bin/signal_poll.sh"          /usr/bin/signal_poll.sh
"$ADB" shell "chmod 755 /usr/bin/signal_poll.sh"
for d in oled_brand.sh lte_reconnect.sh network_select.sh sd_setup.sh; do
  [ -f "$DEV/usr/bin/$d" ] && { "$ADB" push "$DEV/usr/bin/$d" "/usr/bin/$d"; "$ADB" shell "chmod 755 /usr/bin/$d"; }
done
# Login banner: /etc/profile already sources /etc/profile.d/*.sh, so this is a
# drop-in and removing the file removes the feature.
if [ -f "$DEV/etc/profile.d/sigmod-banner.sh" ]; then
  "$ADB" shell "mkdir -p /etc/profile.d"
  "$ADB" push "$DEV/etc/profile.d/sigmod-banner.sh" /etc/profile.d/sigmod-banner.sh
  "$ADB" shell "chmod 644 /etc/profile.d/sigmod-banner.sh"
fi
"$ADB" push "$DEV/etc/init.d/signal_poll"          /etc/init.d/signal_poll
"$ADB" shell "chmod 755 /etc/init.d/signal_poll"
"$ADB" shell "ln -sf ../init.d/signal_poll /etc/rc5.d/S98signal_poll"

say "Deploying CGI + web assets..."
"$ADB" push "$DEV/WEBSERVER/www/cgi-bin/signal_stats.sh" "$WWW/cgi-bin/signal_stats.sh"
"$ADB" shell "chmod 755 $WWW/cgi-bin/signal_stats.sh"
"$ADB" push "$DEV/WEBSERVER/www/cgi-bin/metrics.sh"      "$WWW/cgi-bin/metrics.sh"
"$ADB" shell "chmod 755 $WWW/cgi-bin/metrics.sh"
"$ADB" push "$DEV/WEBSERVER/www/cgi-bin/sysinfo.sh"     "$WWW/cgi-bin/sysinfo.sh"
"$ADB" shell "chmod 755 $WWW/cgi-bin/sysinfo.sh"
"$ADB" push "$DEV/WEBSERVER/www/cgi-bin/control.sh"     "$WWW/cgi-bin/control.sh"
"$ADB" push "$DEV/WEBSERVER/www/cgi-bin/deviceinfo.sh"  "$WWW/cgi-bin/deviceinfo.sh"
"$ADB" shell "chmod 755 $WWW/cgi-bin/deviceinfo.sh"
"$ADB" shell "chmod 755 $WWW/cgi-bin/control.sh"
"$ADB" push "$DEV/WEBSERVER/www/sigmod.js"              "$WWW/sigmod.js"
"$ADB" push "$DEV/WEBSERVER/www/darkmode.css"           "$WWW/darkmode.css"
"$ADB" shell "chmod 644 $WWW/sigmod.js $WWW/darkmode.css"

say "Wiring sigmod.js into login.html and settings.html..."
# Insert the <script> ref right before </head> on the same line (portable sed:
# no embedded newline, works on GNU and BSD/macOS sed). Done host-side because
# busybox sed on the device does not handle newlines in the replacement.
tmp="$(mktemp -d)"
for f in login.html settings.html; do
  "$ADB" pull "$WWW/$f" "$tmp/$f" >/dev/null 2>&1 || continue
  if ! grep -q 'sigmod.js' "$tmp/$f"; then
    sed 's#</head>#<script src="sigmod.js"></script></head>#' "$tmp/$f" > "$tmp/$f.new"
    "$ADB" push "$tmp/$f.new" "$WWW/$f" >/dev/null
    "$ADB" shell "chmod 644 $WWW/$f"
    echo "    patched $f"
  else
    echo "    $f already wired"
  fi
done
rm -rf "$tmp"

say "Starting the signal daemon..."
# -t forces a PTY so setsid can fully detach the daemon from the adb session.
# If this appears to hang in your terminal, press Ctrl-C: the daemon has already
# started (it also auto-starts on every boot via /etc/rc5.d/S98signal_poll).
"$ADB" shell -t "/etc/init.d/signal_poll start" || true

say "Done. Open http://192.168.0.1/ (login admin/admin) -- the Status page now"
say "shows RSRP/RSRQ and Band, in a dark theme. Give it ~10s for the first read."
