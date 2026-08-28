#!/bin/sh
# M7350 mod: read-only system info for the web UI System panel.
# Safe to call from a CGI context -- reads only /proc, /sys, ip and iptables.
# NEVER read /dev/smd7 here (blocks and kills lighttpd); modem metrics come
# from the signal_poll.sh daemon via signal_stats.sh.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
printf 'Content-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nCache-Control: no-store\r\n\r\n'

UP=$(cut -d. -f1 /proc/uptime 2>/dev/null)
TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
LOAD=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null)
MT=$(grep -m1 MemTotal /proc/meminfo 2>/dev/null | tr -dc '0-9')
MF=$(grep -m1 MemAvailable /proc/meminfo 2>/dev/null | tr -dc '0-9')
[ -z "$MF" ] && MF=$(grep -m1 MemFree /proc/meminfo 2>/dev/null | tr -dc '0-9')
WAN=$(ip -4 addr show rmnet0 2>/dev/null | grep -o 'inet [0-9.]*' | head -1 | cut -d' ' -f2)

if iptables -t mangle -S POSTROUTING 2>/dev/null | grep -q 'ttl-set'; then TTL=on; else TTL=off; fi
if pgrep adbd >/dev/null 2>&1; then ADBST=on; else ADBST=off; fi
if netstat -ltn 2>/dev/null | grep -q ':21 '; then FTP=on; else FTP=off; fi
if netstat -ltn 2>/dev/null | grep -q ':23 '; then TELNET=on; else TELNET=off; fi
if netstat -ltn 2>/dev/null | grep -q ':22 '; then SSH=on; else SSH=off; fi
BATT=$(uci get battery.battery_mgr.power_level 2>/dev/null)
CHG=$(uci get battery.battery_mgr.is_charging 2>/dev/null)

printf '{"uptime":"%s","temp":"%s","load":"%s","memtotal":"%s","memfree":"%s","wan":"%s","ttl":"%s","adb":"%s","ftp":"%s","telnet":"%s","ssh":"%s","battery":"%s","charging":"%s"}' \
  "$UP" "$TEMP" "$LOAD" "$MT" "$MF" "$WAN" "$TTL" "$ADBST" "$FTP" "$TELNET" "$SSH" "$BATT" "$CHG"
