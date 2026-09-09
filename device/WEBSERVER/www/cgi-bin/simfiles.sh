#!/bin/sh
# M7350 mod: serve the cached SIM elementary files to the web UI.
#
# AUTH: FAILS CLOSED. IMSI and ICCID identify the subscriber, and the PLMN
# selector lists say which networks the card will and will not use. That is not
# LAN-readable without the password.
#
#   ?op=get       the cache as-is
#   ?op=rescan    ask the daemon to re-read the card, then return the cache
#
# This NEVER opens an AT channel itself. A CGI that opens /dev/smd* blocks and
# takes lighttpd down with it, which is why the read lives in sim_scan.sh and is
# driven by signal_poll.sh. A rescan here just drops a marker and returns; the
# daemon picks it up on its next tick.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

PWFILE=/etc/signalmod.pw
CACHE=/tmp/sim_files.json
MARK=/tmp/.sigmod_simscan
J='Content-Type: application/json\r\nCache-Control: no-store\r\n'

fail(){ printf "Status: $1\r\n${J}\r\n{\"error\":\"$2\"}"; exit 0; }

[ -s "$PWFILE" ] || fail "503 Service Unavailable" "no password set: create /etc/signalmod.pw first"
supplied="$HTTP_X_AUTH"
[ -z "$supplied" ] && supplied=$(printf '%s' "$QUERY_STRING" | sed -n 's/.*[?&]auth=\([^&]*\).*/\1/p')
[ "$supplied" = "$(cat "$PWFILE" 2>/dev/null)" ] || fail "403 Forbidden" "auth"

case "$QUERY_STRING" in
  *op=rescan*) : > "$MARK" 2>/dev/null ;;
esac

if [ -s "$CACHE" ]; then
  printf "${J}\r\n"
  cat "$CACHE"
else
  # Not an error: the daemon may simply not have scanned yet. Say which, so the
  # UI can show "waiting" rather than "broken".
  printf "${J}\r\n"
  printf '{"apdu_access":"unknown","files":[],"pending":true,"note":"no scan yet; the daemon writes this on its slow tick"}'
fi
