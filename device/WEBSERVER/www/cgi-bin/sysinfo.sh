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
WIFI=$(ubus call wlan_object wlan_get_switch 2>/dev/null | sed -n 's/.*"wlan": *"\([a-z]*\)".*/\1/p')
ROAM=$(uci get network_status.network_status_data.roam_switch 2>/dev/null)
ROAMST=$(uci get network_status.network_status_data.roam_status 2>/dev/null)
APNIDX=$(uci get isp_profile.profile_isp_data.isp_index 2>/dev/null); [ -n "$APNIDX" ] || APNIDX=1
APN=$(uci get "isp_profile.profile_isp_data_$APNIDX.apn_name_v4" 2>/dev/null)

# ---- CPU utilisation ------------------------------------------------------
# /proc/stat is cumulative, so a single read says nothing. Normally we diff
# against the previous poll, which is free. But on the first call after boot
# there is no previous sample, and two calls inside the same jiffy give a zero
# window -- both used to render the card blank. Fall back to sampling twice
# in-script so this always returns a number.
cpu_sample() {
  awk '/^cpu /{idle=$5+$6; tot=0; for(i=2;i<=NF;i++) tot+=$i; print tot" "idle}' /proc/stat 2>/dev/null
}
cpu_pct() {
  awk -v c="$1" -v p="$2" 'BEGIN{
    split(c,a," "); split(p,b," ");
    dt=a[1]-b[1]; di=a[2]-b[2];
    if (dt>0) { u=(dt-di)*100/dt; if(u<0)u=0; if(u>100)u=100; printf "%.0f", u }
  }'
}

CPU=""
CUR=$(cpu_sample)
PREVF=/tmp/.sigmod_cpu
if [ -n "$CUR" ]; then
  [ -f "$PREVF" ] && CPU=$(cpu_pct "$CUR" "$(cat "$PREVF" 2>/dev/null)")
  if [ -z "$CPU" ]; then
    sleep 0.3
    CUR2=$(cpu_sample)
    CPU=$(cpu_pct "$CUR2" "$CUR")
    [ -n "$CUR2" ] && CUR=$CUR2
  fi
  printf '%s' "$CUR" > "$PREVF" 2>/dev/null
fi
[ -n "$CPU" ] || CPU=0

# ---- swap + storage -------------------------------------------------------
SWT=$(grep -m1 SwapTotal /proc/meminfo 2>/dev/null | tr -dc '0-9')
SWF=$(grep -m1 SwapFree  /proc/meminfo 2>/dev/null | tr -dc '0-9')
dfree() { df "$1" 2>/dev/null | awk 'NR==2{print $4}'; }   # KB available
dpct()  { df "$1" 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}'; }
ROOTF=$(dfree /); ROOTP=$(dpct /)
USRF=$(dfree /usr); USRP=$(dpct /usr)

# ---- SD card --------------------------------------------------------------
# The slot exists (/sys/class/mmc_host/mmc0) even with nothing in it, so report
# the slot's state rather than pretending the feature is missing.
SAVER=$([ -f /etc/signalmod_saver ] && echo on || echo off)

SD="no slot"
SDDAYS=""
if [ -d /sys/class/mmc_host/mmc0 ]; then
  SD="empty"
  MMC=$(awk '/mmcblk[0-9]+$/{print $4; exit}' /proc/partitions 2>/dev/null)
  if [ -n "$MMC" ]; then
    MP=$(awk -v d="/dev/$MMC" '$1 ~ d {print $2; exit}' /proc/mounts 2>/dev/null)
    if [ -z "$MP" ]; then MP=$(awk -v d="$MMC" '$1 ~ d {print $2; exit}' /proc/mounts 2>/dev/null); fi
    if [ -n "$MP" ]; then
      SD=$(df "$MP" 2>/dev/null | awk 'NR==2{ if ($4 > 1048576) printf "%.1fGB free", $4/1048576; else printf "%dMB free", $4/1024 }')
      SDDAYS=$(ls "$MP"/signalmod/history/*.csv 2>/dev/null | wc -l | tr -d ' ')
    else
      SD="present, not mounted"
    fi
  fi
fi

printf '{"uptime":"%s","temp":"%s","load":"%s","memtotal":"%s","memfree":"%s","wan":"%s","ttl":"%s","adb":"%s","ftp":"%s","telnet":"%s","ssh":"%s","battery":"%s","charging":"%s","wifi":"%s","cpu":"%s","swaptotal":"%s","swapfree":"%s","rootfree":"%s","rootpct":"%s","usrfree":"%s","usrpct":"%s","sd":"%s","sddays":"%s","roaming":"%s","roamstatus":"%s","apn":"%s","apnidx":"%s","saver":"%s"}' \
  "$UP" "$TEMP" "$LOAD" "$MT" "$MF" "$WAN" "$TTL" "$ADBST" "$FTP" "$TELNET" "$SSH" "$BATT" "$CHG" "$WIFI" "$CPU" "$SWT" "$SWF" "$ROOTF" "$ROOTP" "$USRF" "$USRP" "$SD" "$SDDAYS" "$ROAM" "$ROAMST" "$APN" "$APNIDX" "$SAVER"
