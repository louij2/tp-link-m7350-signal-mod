#!/bin/sh
# Show -- and optionally restore -- AUTOMATIC network selection (AT+COPS).
#
# WHY THIS EXISTS: a manual COPS selection looks exactly like "No service" even
# with a full-strength signal (CSQ 31). If the modem is pinned to an operator it
# can no longer see, it will sit there refusing to attach forever. Auto is the
# mode you want on a router that has to look after itself.
#
#   network_select.sh            # report current mode, change nothing
#   network_select.sh --auto     # set automatic selection (AT+COPS=0)
#
# RUN THIS BY HAND ONLY -- never from a CGI and never in a loop:
#   * a CGI that reads an smd channel blocks and takes lighttpd down with it;
#   * heavy AT probing has wedged /dev/smd7 on this device before (EIO on open),
#     which then needs a reboot to clear.
# It never issues AT+COPS=? (the full network scan) -- that is the slow call that
# ties the channel up for a minute and is the usual cause of a wedge. AT+COPS?
# is just a status read.
#
# The signal daemon is stopped for the few seconds this needs the AT channel, so
# the two do not interleave reads on the same device, and is always restarted.

CANDIDATES="/dev/smd7 /dev/smd8 /dev/smd11"
SET_AUTO=0
[ "$1" = "--auto" ] && SET_AUTO=1

DAEMON_WAS_RUNNING=0
stop_daemon() {
  for d in /proc/[0-9]*; do
    q=${d##*/}
    # Never match our own shell or our parent: a command line that merely
    # mentions the daemon name reads as a running daemon otherwise, which is
    # exactly how a dead daemon looked alive for 23 hours.
    [ "$q" = "$$" ] || [ "$q" = "$PPID" ] && continue
    grep -qs /usr/bin/signal_poll "$d/cmdline" 2>/dev/null || continue
    DAEMON_WAS_RUNNING=1
    kill "${d#/proc/}" 2>/dev/null
  done
  [ "$DAEMON_WAS_RUNNING" = 1 ] && sleep 2
  return 0
}
start_daemon() {
  [ "$DAEMON_WAS_RUNNING" = 1 ] || return 0
  [ -x /usr/bin/signal_poll.sh ] || return 0
  nohup setsid /usr/bin/signal_poll.sh </dev/null >/dev/null 2>&1 &
  echo "signal daemon restarted"
}
# Restart the daemon no matter how we leave.
trap 'start_daemon' EXIT INT TERM

probe() { # a channel that opens and answers OK is usable
  [ -c "$1" ] || return 1
  ( cat "$1" > /tmp/cops_probe.txt 2>/dev/null ) & p=$!
  sleep 0.1
  printf 'AT\r\n' > "$1" 2>/dev/null || { kill $p 2>/dev/null; return 1; }
  sleep 1
  kill $p 2>/dev/null; wait $p 2>/dev/null
  grep -q 'OK' /tmp/cops_probe.txt 2>/dev/null
}

at() { # at <command> -> prints the response
  ( cat "$SMD" > /tmp/cops_raw.txt 2>/dev/null ) & p=$!
  sleep 0.1
  printf '%s\r\n' "$1" > "$SMD" 2>/dev/null
  sleep 2
  kill $p 2>/dev/null; wait $p 2>/dev/null
  cat /tmp/cops_raw.txt 2>/dev/null
}

stop_daemon

SMD=""
for c in $CANDIDATES; do probe "$c" && { SMD="$c"; break; }; done
[ -z "$SMD" ] && { echo "No usable AT channel (tried: $CANDIDATES)."; echo "smd7 may be wedged -- a reboot clears that."; exit 1; }
echo "AT channel: $SMD"

RESP=$(at 'AT+COPS?')
COPS=$(printf '%s' "$RESP" | grep -o '+COPS: [^\r]*' | head -1)
MODE=$(printf '%s' "$COPS" | sed 's/+COPS: //' | cut -d, -f1)

echo "raw: ${COPS:-<no response>}"
case "$MODE" in
  0) echo "mode: 0 = AUTOMATIC  (this is what you want)" ;;
  1) echo "mode: 1 = MANUAL     <-- pinned to one operator; this is what looks like 'No service'" ;;
  4) echo "mode: 4 = MANUAL/AUTO fallback" ;;
  *) echo "mode: ${MODE:-unknown}" ;;
esac

if [ "$SET_AUTO" = 1 ]; then
  if [ "$MODE" = "0" ]; then
    echo "already automatic -- nothing to do"
  else
    echo "setting automatic selection (AT+COPS=0)..."
    at 'AT+COPS=0' >/dev/null
    sleep 3
    RESP=$(at 'AT+COPS?')
    NEW=$(printf '%s' "$RESP" | grep -o '+COPS: [^\r]*' | head -1)
    echo "now: ${NEW:-<no response>}"
    printf '%s' "$NEW" | grep -q '+COPS: 0' && echo "OK -- automatic selection confirmed" \
      || echo "WARNING: did not read back as automatic; re-run to check"
  fi
else
  [ "$MODE" = "0" ] || echo "run with --auto to restore automatic selection"
fi
