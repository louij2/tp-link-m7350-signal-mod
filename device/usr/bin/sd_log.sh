#!/bin/sh
# M7350 mod: append one diagnostic sample to the SD card.
#
#   sd_log.sh            append a sample if logging is enabled, else do nothing
#   sd_log.sh --force    append regardless of the toggle
#
# WHY THIS EXISTS: when this device wedges, everything useful about the minutes
# beforehand is in tmpfs and dies with it. /tmp/signal.json, dmesg and the
# process table are all RAM. The SD card is the only thing that survives, so the
# state worth having at 3am gets written there while the device is still healthy.
#
# EVERY WRITE IS SYNCED. A buffered append is worthless for this: the whole
# point is the sample taken just before a hang, and that is exactly the one
# still sitting in the page cache when the power goes. One line every 30s on a
# 59 GB card is nothing, wear or otherwise.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

MARK=/etc/signalmod_sdlog        # toggle: present means on
MNT=/media/card
DIR="$MNT/signalmod/logs"
MAXKB=20480                      # 20 MB per day, then it stops appending

[ "$1" = "--force" ] || [ -f "$MARK" ] || exit 0
# No card, nothing to do. Never fall back to /tmp: a log that dies with the
# device is the thing this exists to avoid.
mount | grep -q " $MNT " || exit 0
mkdir -p "$DIR" 2>/dev/null || exit 0

LOG="$DIR/$(date '+%Y-%m-%d' 2>/dev/null).log"

# Stop rather than fill the card. A runaway log is its own outage.
if [ -f "$LOG" ]; then
  KB=$(du -k "$LOG" 2>/dev/null | cut -f1)
  [ -n "$KB" ] && [ "$KB" -ge "$MAXKB" ] && exit 0
fi

TS=$(date '+%H:%M:%S' 2>/dev/null)
UP=$(cut -d. -f1 /proc/uptime 2>/dev/null)
LOAD=$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)
MF=$(sed -n 's/^MemFree: *\([0-9]*\).*/\1/p' /proc/meminfo 2>/dev/null)
# No MemAvailable here: this is kernel 3.4.0 and that field predates it by
# years. Logging an empty one just puts 'avail=' in every line forever.
BUF=$(sed -n 's/^Buffers: *\([0-9]*\).*/\1/p' /proc/meminfo 2>/dev/null)
CACHE=$(sed -n 's/^Cached: *\([0-9]*\).*/\1/p' /proc/meminfo 2>/dev/null)
SW=$(sed -n 's/^SwapFree: *\([0-9]*\).*/\1/p' /proc/meminfo 2>/dev/null)
PROCS=$(ls -d /proc/[0-9]* 2>/dev/null | wc -l | tr -d ' ')
TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | cut -c1-2)
ROUTE=$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')
[ -n "$ROUTE" ] || ROUTE=none
RX=$(cat /sys/class/net/rmnet0/statistics/rx_bytes 2>/dev/null)
TX=$(cat /sys/class/net/rmnet0/statistics/tx_bytes 2>/dev/null)
STA=$(ubus call wlan_object wlan_get_sta_num 2>/dev/null | sed -n 's/.*: *\([0-9]*\).*/\1/p' | head -1)
RSRP=$(sed -n 's/.*"rsrp":"\([^"]*\)".*/\1/p' /tmp/signal.json 2>/dev/null)
BATT=$(uci get battery.battery_mgr.power_level 2>/dev/null)
# Which of the things that should be running actually are.
alive(){ ps 2>/dev/null | grep -q "[/ ]$1" && printf 'y' || printf 'n'; }
DAEM="poll=$(alive signal_poll.sh) qcmap=$(alive QCMAP_ConnectionManager) http=$(alive lighttpd) dns=$(alive dnsmasq) ssh=$(alive dropbear)"

printf '%s up=%s load=%s memfree=%s buffers=%s cached=%s swapfree=%s procs=%s temp=%s gw=%s rx=%s tx=%s wifi_sta=%s rsrp=%s batt=%s %s\n' \
  "$TS" "$UP" "$LOAD" "$MF" "$BUF" "$CACHE" "$SW" "$PROCS" "$TEMP" "$ROUTE" "$RX" "$TX" "$STA" "$RSRP" "$BATT" "$DAEM" >> "$LOG"

# New kernel messages since last time. A hang is usually visible here first
# (OOM kills, watchdog, USB resets) and dmesg is a RAM ring buffer that a reboot
# throws away, so it has to be captured while the device is still up.
KLOG="$DIR/$(date '+%Y-%m-%d' 2>/dev/null).kernel.log"
SEEN=/tmp/.sigmod_dmesg_seen
NOW=$(dmesg 2>/dev/null | wc -l | tr -d ' ')
LAST=$(cat "$SEEN" 2>/dev/null | tr -dc '0-9')
[ -n "$LAST" ] || LAST=0
# A smaller count than last time means the ring wrapped or the box rebooted;
# start over rather than printing nothing for the rest of the day.
[ "$NOW" -lt "$LAST" ] && LAST=0
if [ "$NOW" -gt "$LAST" ]; then
  dmesg 2>/dev/null | tail -n $((NOW - LAST)) | sed "s/^/$TS /" >> "$KLOG"
  printf '%s' "$NOW" > "$SEEN"
fi

sync
