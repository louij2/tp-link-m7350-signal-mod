#!/bin/sh
# Keep the LTE (WWAN) data link up unattended -- useful when the M7350 is tucked
# behind a GL.iNet as a USB uplink with no one watching it.
#
# Strategy: enable the modem's own autoconnect (this is the part that actually
# does the work, and it is VERIFIED), then act as a backstop watchdog that only
# re-brings-up the data call after a SUSTAINED outage -- never on a blip.
#
# SAFETY: the backstop is DISARMED UNLESS IT CAN PROVE ITSELF.
#   * qcmap_method_set_autoconnect {"operation":1}  -- verified on-device.
#   * qcmap_method_bring_up_wwan   {"operation":1}  -- NOT verified. A wrong
#     operation code here could tear the data call DOWN rather than up, which on
#     a headless box is unrecoverable remotely. So the method is only armed if
#     `ubus -v list qcmap` actually advertises it; otherwise the watchdog runs
#     autoconnect-only and says so in the log.
# Run scripts/verify-lte-reconnect.sh for a read-only look at what this device
# advertises before you trust the backstop.
#
# Opt-in: only started when /etc/signalmod_lte exists.

LOG=/tmp/lte_reconnect.log
PING_TARGET="${LTE_PING_TARGET:-1.1.1.1}"
DOWN_STREAK_LIMIT=3          # ~3 x 20s => link considered down after ~60s
INTERVAL=20
BACKOFF_MAX=300              # never hammer the modem faster than this after acting

exec </dev/null
log(){ # keep the log small: the device has tmpfs, not a disk
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG" 2>/dev/null
  [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 500 ] && \
    { tail -n 200 "$LOG" > "$LOG.t" 2>/dev/null && mv "$LOG.t" "$LOG"; }
  return 0
}

# ---- capability probe (read-only) -----------------------------------------
UBUS_METHODS="$(ubus -v list qcmap 2>/dev/null)"
have_method(){ printf '%s' "$UBUS_METHODS" | grep -q "$1"; }

if have_method qcmap_method_set_autoconnect; then
  AUTOCONNECT=1
else
  AUTOCONNECT=0
  log "WARN: qcmap_method_set_autoconnect not advertised -- autoconnect disabled"
fi

# The backstop stays disarmed unless the device actually advertises the method.
if have_method qcmap_method_bring_up_wwan; then
  BRINGUP=1
  log "backstop armed (qcmap_method_bring_up_wwan is advertised)"
else
  BRINGUP=0
  log "backstop DISARMED (qcmap_method_bring_up_wwan not advertised) -- autoconnect only"
fi

enable_autoconnect(){
  [ "$AUTOCONNECT" = 1 ] || return 0
  ubus call qcmap qcmap_method_set_autoconnect '{"operation":1}' >/dev/null 2>&1
}
bring_up(){
  [ "$BRINGUP" = 1 ] || return 0
  ubus call qcmap qcmap_method_bring_up_wwan '{"operation":1}' >/dev/null 2>&1
}

# ---- ping self-test --------------------------------------------------------
# busybox ping does not always support -W. If it does not, every probe would
# "fail" and the watchdog would act on a link that is perfectly healthy.
PING_OPTS="-c1 -W3"
if ! ping $PING_OPTS "$PING_TARGET" >/dev/null 2>&1; then
  if ping -c1 "$PING_TARGET" >/dev/null 2>&1; then
    PING_OPTS="-c1"
    log "note: ping -W unsupported here, falling back to 'ping -c1'"
  fi
fi

link_up(){
  ip route 2>/dev/null | grep -q '^default.*rmnet' || return 1
  ping $PING_OPTS "$PING_TARGET" >/dev/null 2>&1
}

log "started (target=$PING_TARGET autoconnect=$AUTOCONNECT backstop=$BRINGUP)"
enable_autoconnect

fails=0
while true; do
  if link_up; then
    fails=0
  else
    fails=$((fails + 1))
    if [ "$fails" -ge "$DOWN_STREAK_LIMIT" ]; then
      log "link down for ~$((fails * INTERVAL))s -- re-asserting autoconnect${BRINGUP:+ + bring_up}"
      enable_autoconnect
      bring_up
      fails=0
      sleep "$BACKOFF_MAX"   # let the modem re-attach; do not hammer it
      continue
    fi
  fi
  sleep "$INTERVAL"
done
