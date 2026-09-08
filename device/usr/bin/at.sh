#!/bin/sh
# Send AT commands to the modem and print the reply.
#
#   at.sh [-d /dev/smdN] 'AT+CGDCONT?' ['AT+CGATT?' ...]
#
# WHY IT IS WRITTEN THIS WAY: the obvious approach, backgrounding a reader
# (`cat /dev/smdX > out &`) and killing it afterwards, hangs any adb shell that
# calls this. The reader keeps the pty as its controlling terminal even with
# every fd redirected, so adb waits for it forever. Redirecting stdin, killing
# by PID and wrapping in `timeout` all fail to fix that. So: one bidirectional
# fd and `read -t`, with no background process anywhere.
#
# CHANNELS ARE NOT INTERCHANGEABLE. On this modem smd7 answers +COPS and
# $QCSYSMODE but errors on $QCRSRP?, while smd8/smd11 are the other way round.
# Probing hard enough wedges a channel: it then returns EIO on open until the
# device is rebooted. Keep batches small, and prefer reads over writes.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

DEV=/dev/smd11
[ "$1" = "-d" ] && { DEV="$2"; shift 2; }
[ $# -gt 0 ] || { echo "usage: at.sh [-d /dev/smdN] 'AT+CMD' ..."; exit 1; }

# A wedged channel returns EIO on open. Say so rather than hanging.
exec 3<>"$DEV" 2>/dev/null || { echo "$DEV will not open (wedged?). A reboot clears it." >&2; exit 1; }

for c in "$@"; do
  printf '%s\r' "$c" >&3 || { echo "write to $DEV failed" >&2; exit 1; }
  # Read until the modem falls quiet. Every terminal response ends in OK,
  # ERROR or +CME ERROR, so stop there rather than always paying the timeout.
  while IFS= read -t 3 -r line <&3; do
    line=$(printf '%s' "$line" | tr -d '\r')
    [ -n "$line" ] && printf '%s\n' "$line"
    case "$line" in
      OK|ERROR|+CME\ ERROR*|+CMS\ ERROR*) break ;;
    esac
  done
done

exec 3>&-
