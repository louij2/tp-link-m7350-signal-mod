#!/usr/bin/env bash
# Restore the M7350 to stock: revert the patched pages, remove the mod files,
# the init script and its boot symlink, and stop the daemon.
set -euo pipefail

ADB="${ADB:-adb}"
WWW=/WEBSERVER/www
say(){ printf '\033[1;36m[*]\033[0m %s\n' "$1"; }

"$ADB" get-state >/dev/null 2>&1 || { echo "No ADB device found." >&2; exit 1; }

say "Stopping + removing the signal daemon..."
"$ADB" shell "/etc/init.d/signal_poll stop" 2>/dev/null || true
"$ADB" shell 'ME=$$; for d in /proc/[0-9]*; do p=${d##*/}; [ "$p" = "$ME" ] && continue; grep -qs /usr/bin/signal_poll.sh $d/cmdline 2>/dev/null && kill $p 2>/dev/null; done' || true
"$ADB" shell "rm -f /etc/rc5.d/S98signal_poll /etc/init.d/signal_poll /usr/bin/signal_poll.sh /tmp/signal.json"

say "Removing web assets + CGI..."
"$ADB" shell "rm -f $WWW/sigmod.js $WWW/darkmode.css $WWW/console.html $WWW/cgi-bin/signal_stats.sh $WWW/cgi-bin/metrics.sh $WWW/cgi-bin/exec.sh"

say "Restoring stock pages from .bak..."
for f in login.html status.html settings.html; do
  "$ADB" shell "[ -e $WWW/$f.bak ] && cat $WWW/$f.bak > $WWW/$f && chmod 644 $WWW/$f && echo '    restored $f' || echo '    no backup for $f (left as-is)'"
done

say "Done. The web UI is back to stock. (The daemon will not return on reboot.)"
