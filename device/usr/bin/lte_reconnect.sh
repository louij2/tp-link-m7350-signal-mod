#!/bin/sh
# Keep the LTE (WWAN) data link up unattended -- useful when the M7350 is tucked
# behind a GL.iNet as a USB uplink with no one watching it.
#
# Strategy: enable the modem's own autoconnect, then act as a backstop watchdog
# that only re-brings-up the data call after a SUSTAINED outage (never on a blip).
#
# !! VERIFY ON-DEVICE before relying on this !!  The QCMAP ubus "operation"
# codes below are the expected "enable / bring-up" values (1). Confirm with:
#   ubus -v list qcmap        # see qcmap_method_set_autoconnect / bring_up_wwan
# and test each call once by hand over SSH, watching `ifconfig rmnet0` /
# `ip route`, before trusting the watchdog to fire them automatically.
exec </dev/null >/dev/null 2>&1

PING_TARGET=1.1.1.1
DOWN_STREAK_LIMIT=3          # ~3 x 20s = link considered down after ~60s
enable_autoconnect() { ubus call qcmap qcmap_method_set_autoconnect '{"operation":1}' 2>/dev/null; }
bring_up()           { ubus call qcmap qcmap_method_bring_up_wwan   '{"operation":1}' 2>/dev/null; }

enable_autoconnect
fails=0
while true; do
  if ip route 2>/dev/null | grep -q '^default.*rmnet' && ping -c1 -W3 "$PING_TARGET" >/dev/null 2>&1; then
    fails=0
  else
    fails=$((fails + 1))
    if [ "$fails" -ge "$DOWN_STREAK_LIMIT" ]; then
      enable_autoconnect
      bring_up
      fails=0
      sleep 25            # let the modem re-attach before re-checking
    fi
  fi
  sleep 20
done
