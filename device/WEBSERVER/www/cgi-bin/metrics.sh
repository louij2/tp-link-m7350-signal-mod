#!/bin/sh
# Prometheus exposition endpoint for the M7350 mod.
# Scrape http://<router>/cgi-bin/metrics.sh from Prometheus to graph LTE signal,
# throughput and latency in Grafana. Reads the daemon's cache only (safe).
printf 'Content-Type: text/plain; version=0.0.4; charset=utf-8\r\nCache-Control: no-store\r\n\r\n'

J=$(cat /tmp/signal.json 2>/dev/null)
[ -z "$J" ] && { echo "# no data"; exit 0; }

# Extract a flat-JSON string field by key.
val() { printf '%s' "$J" | sed -n 's/.*"'"$1"'":"\([^"]*\)".*/\1/p'; }

emit() { # metric_name  json_key  help
  v=$(val "$2")
  [ -z "$v" ] && return
  echo "# HELP $1 $3"
  echo "# TYPE $1 gauge"
  echo "$1 $v"
}

emit m7350_rsrp_dbm          rsrp       "LTE reference signal received power (dBm)"
emit m7350_rsrq_db           rsrq       "LTE reference signal received quality (dB)"
emit m7350_rssi_dbm          rssi       "Received signal strength indicator (dBm)"
emit m7350_earfcn            earfcn     "Serving cell EARFCN"
emit m7350_band              band       "LTE band number"
emit m7350_downlink_kbps     dl_kbps    "WAN downlink throughput (kbit/s)"
emit m7350_uplink_kbps       ul_kbps    "WAN uplink throughput (kbit/s)"
emit m7350_latency_ms        latency_ms "Uplink ping latency (ms)"
emit m7350_uptime_seconds    uptime     "Device uptime (seconds)"
counter() { # metric_name  json_key  help
  v=$(val "$2")
  [ -z "$v" ] && return
  echo "# HELP $1 $3"
  echo "# TYPE $1 counter"
  echo "$1 $v"
}
counter m7350_rx_bytes_total rx_bytes   "WAN interface received bytes"
counter m7350_tx_bytes_total tx_bytes   "WAN interface transmitted bytes"

# Info metric carrying non-numeric labels; value is 1 when connected (mode set).
MODE=$(val mode); BAND=$(val band)
if [ -n "$MODE" ]; then
  echo "# HELP m7350_info Static-ish info as labels; 1 while a mode is reported"
  echo "# TYPE m7350_info gauge"
  echo "m7350_info{mode=\"$MODE\",band=\"$BAND\"} 1"
fi

# ---------------------------------------------------------------------------
# Host health. Read straight from /proc and /sys -- no AT channel, no ubus, so
# this stays safe to scrape as often as Prometheus likes.
# ---------------------------------------------------------------------------
gauge() { # name value help
  [ -z "$2" ] && return
  echo "# HELP $1 $3"
  echo "# TYPE $1 gauge"
  echo "$1 $2"
}

# This SoC reports thermal_zone0 in whole degrees, not the millidegrees most
# drivers use, so dividing by 1000 gave a flat 0.0. Handle both conventions.
T=$(awk '{ if ($1 > 1000) printf "%.1f", $1/1000; else printf "%.1f", $1 }' /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
gauge m7350_temperature_celsius "$T" "SoC temperature (C)"

awk '/^MemTotal:/{t=$2} /^MemFree:/{f=$2} /^Cached:/{c=$2} END{
  if(t){ printf "# HELP m7350_memory_total_bytes Total RAM\n# TYPE m7350_memory_total_bytes gauge\nm7350_memory_total_bytes %d\n", t*1024;
         printf "# HELP m7350_memory_available_bytes Free plus cached RAM\n# TYPE m7350_memory_available_bytes gauge\nm7350_memory_available_bytes %d\n", (f+c)*1024 }
}' /proc/meminfo 2>/dev/null

awk '{ printf "# HELP m7350_load1 1-minute load average\n# TYPE m7350_load1 gauge\nm7350_load1 %s\n", $1;
       printf "# HELP m7350_load5 5-minute load average\n# TYPE m7350_load5 gauge\nm7350_load5 %s\n", $2;
       printf "# HELP m7350_load15 15-minute load average\n# TYPE m7350_load15 gauge\nm7350_load15 %s\n", $3 }' /proc/loadavg 2>/dev/null

BATT=$(uci get battery.battery_mgr.power_level 2>/dev/null)
CHG=$(uci get battery.battery_mgr.is_charging 2>/dev/null)
gauge m7350_battery_percent "$BATT" "Battery charge (%)"
case "$CHG" in ''|*[!0-9]*) ;; *) gauge m7350_battery_charging "$CHG" "1 while charging" ;; esac

# Service reachability, so an alert can fire when telnet or FTP is left on.
svc_up() { netstat -ltn 2>/dev/null | grep -q ":$1 " && echo 1 || echo 0; }
echo "# HELP m7350_service_enabled 1 when the service is listening"
echo "# TYPE m7350_service_enabled gauge"
for pair in "ftp 21" "telnet 23" "ssh 22" "http 80"; do
  set -- $pair
  echo "m7350_service_enabled{service=\"$1\"} $(svc_up "$2")"
done
echo "m7350_service_enabled{service=\"ttl_fix\"} $([ -f /etc/signalmod_ttl ] && echo 1 || echo 0)"
echo "m7350_service_enabled{service=\"lte_watchdog\"} $([ -f /etc/signalmod_lte ] && echo 1 || echo 0)"

echo "# HELP m7350_scrape_success 1 when the daemon cache was readable"
echo "# TYPE m7350_scrape_success gauge"
echo "m7350_scrape_success 1"
