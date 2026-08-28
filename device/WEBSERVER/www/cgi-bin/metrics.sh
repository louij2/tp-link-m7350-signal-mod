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
emit m7350_rx_bytes_total    rx_bytes   "WAN interface received bytes"
emit m7350_tx_bytes_total    tx_bytes   "WAN interface transmitted bytes"

# Info metric carrying non-numeric labels; value is 1 when connected (mode set).
MODE=$(val mode); BAND=$(val band)
if [ -n "$MODE" ]; then
  echo "# HELP m7350_info Static-ish info as labels; 1 while a mode is reported"
  echo "# TYPE m7350_info gauge"
  echo "m7350_info{mode=\"$MODE\",band=\"$BAND\"} 1"
fi
