#!/usr/bin/env bash
# READ-ONLY probe of what the modem stack actually advertises, so the LTE
# auto-reconnect watchdog can be trusted before it is armed.
#
# This script CALLS NOTHING that changes state. It only lists ubus objects and
# reads the current link state. That matters because the watchdog's backstop
# (qcmap_method_bring_up_wwan) is the one call that has never been verified, and
# a wrong operation code would drop the data call -- taking any remote session
# riding that link down with it.
#
#   scripts/verify-lte-reconnect.sh                  # auto: ADB, else SSH
#   M7350_SSH_TARGET=m7350 scripts/verify-lte-reconnect.sh
set -euo pipefail

ADB="${ADB:-adb}"
HOST="${M7350_HOST:-192.168.2.1}"
USER_="${M7350_USER-root}"
TARGET="${M7350_SSH_TARGET:-${USER_:+$USER_@}$HOST}"
SSH_OPTS="${M7350_SSH_OPTS:--o ConnectTimeout=8 -o ServerAliveInterval=5 -o ServerAliveCountMax=3 -o BatchMode=yes}"

say(){ printf '\033[1;36m[*]\033[0m %s\n' "$1"; }
die(){ printf '\033[1;31m[!]\033[0m %s\n' "$1" >&2; exit 1; }

TRANSPORT="${M7350_TRANSPORT:-auto}"
if [ "$TRANSPORT" = auto ]; then
  if "$ADB" get-state >/dev/null 2>&1; then TRANSPORT=adb
  elif ssh $SSH_OPTS -T "$TARGET" true >/dev/null 2>&1; then TRANSPORT=ssh
  else die "No device: ADB not connected and SSH to $TARGET did not answer."; fi
fi
run(){ case "$TRANSPORT" in
  adb) "$ADB" shell "$1" ;;
  ssh) ssh $SSH_OPTS -T "$TARGET" "$1" ;;
esac; }

say "Transport: $TRANSPORT"

echo
say "ubus objects matching qcmap:"
run 'ubus list 2>/dev/null | grep -i qcmap || echo "  (none)"' | sed 's/^/    /'

echo
say "qcmap methods and their signatures:"
run 'ubus -v list qcmap 2>/dev/null || echo "  (qcmap not present)"' | sed 's/^/    /'

echo
say "Current WWAN link state (read-only):"
run 'echo "-- default routes --"; ip route 2>/dev/null | grep "^default" || echo "  (no default route)";
     echo "-- rmnet0 --"; ifconfig rmnet0 2>/dev/null | head -3 || echo "  (no rmnet0)"' | sed 's/^/    /'

echo
say "Watchdog state:"
run '[ -f /etc/signalmod_lte ] && echo "  marker /etc/signalmod_lte PRESENT (watchdog enabled at boot)" || echo "  marker /etc/signalmod_lte absent (watchdog off)";
     [ -f /tmp/lte_reconnect.log ] && { echo "  --- last 15 log lines ---"; tail -15 /tmp/lte_reconnect.log; } || echo "  (no log yet)"' | sed 's/^/    /'

echo
METHODS="$(run 'ubus -v list qcmap 2>/dev/null' || true)"
printf '\033[1;36m[*]\033[0m Verdict: '
if printf '%s' "$METHODS" | grep -q qcmap_method_bring_up_wwan; then
  printf 'bring_up_wwan IS advertised -- the backstop will arm itself.\n'
  echo "    Check the signature printed above: confirm \"operation\" really means"
  echo "    bring-up (1) and not tear-down before relying on it unattended."
else
  printf 'bring_up_wwan is NOT advertised -- the backstop stays disarmed.\n'
  echo "    The watchdog will still run autoconnect-only, which is the verified path."
fi
