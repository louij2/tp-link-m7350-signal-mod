#!/bin/sh
# M7350 mod: control actions for the web UI (reboot / ADB toggle / TTL-fix).
#
# SECURITY NOTE: these actions are NOT authenticated at the CGI layer -- any
# client that can reach the LAN/USB web server can call them. That matches the
# stock UI's own trust model (LAN-only, admin/admin) but be aware of it.
#
# TTL-fix: forces a fixed IP TTL on packets leaving the mobile interface so the
# carrier cannot see per-hop TTL decrement from tethered devices (helps with
# "tethering" throttling on SMARTY/Three). Runtime rule; boot persistence is
# handled by the signal_poll init script re-applying it when the marker exists.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
printf 'Content-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nCache-Control: no-store\r\n\r\n'

A=$(printf '%s' "$QUERY_STRING" | sed -n 's/.*action=\([a-zA-Z_]*\).*/\1/p')
WAN=rmnet0
TTL_VAL=65
MARK=/etc/signalmod_ttl
# Bind admin services to the LAN only (never the WAN). Derived from br0 so it
# follows any LAN-IP change instead of being hardcoded.
LAN_IP=$(ip -4 addr show br0 2>/dev/null | grep -o 'inet [0-9.]*' | head -1 | cut -d' ' -f2)
[ -z "$LAN_IP" ] && LAN_IP=192.168.0.1
FTP_MARK=/etc/signalmod_ftp

# --- FTP (busybox ftpd via tcpsvd, rooted at /, LAN-only) ------------------
ftp_state() { netstat -ltn 2>/dev/null | grep -q "$LAN_IP:21\|:::21\|0.0.0.0:21" && echo on || echo off; }
ftp_on() {
  ftp_state | grep -q on && { touch "$FTP_MARK"; return; }
  setsid tcpsvd -vE "$LAN_IP" 21 ftpd -w / </dev/null >/dev/null 2>&1 &
  touch "$FTP_MARK" 2>/dev/null
}
ftp_off() { pkill -f "tcpsvd $LAN_IP 21" 2>/dev/null; pkill -f 'tcpsvd -vE '"$LAN_IP"' 21' 2>/dev/null; rm -f "$FTP_MARK" 2>/dev/null; }

# --- Telnet (busybox telnetd; often already listening on :23) --------------
tel_state() { netstat -ltn 2>/dev/null | grep -q ':23 ' && echo on || echo off; }
tel_on()  { tel_state | grep -q on || { setsid telnetd -l /bin/sh </dev/null >/dev/null 2>&1 & } ; }
tel_off() { pkill telnetd 2>/dev/null; }

ttl_state() {
  iptables -t mangle -S POSTROUTING 2>/dev/null | grep -q 'ttl-set' && echo on || echo off
}
ttl_on() {
  iptables -t mangle -C POSTROUTING -o "$WAN" -j TTL --ttl-set "$TTL_VAL" 2>/dev/null \
    || iptables -t mangle -A POSTROUTING -o "$WAN" -j TTL --ttl-set "$TTL_VAL" 2>/dev/null
  touch "$MARK" 2>/dev/null
}
ttl_off() {
  while iptables -t mangle -C POSTROUTING -o "$WAN" -j TTL --ttl-set "$TTL_VAL" 2>/dev/null; do
    iptables -t mangle -D POSTROUTING -o "$WAN" -j TTL --ttl-set "$TTL_VAL" 2>/dev/null
  done
  rm -f "$MARK" 2>/dev/null
}

case "$A" in
  reboot)
    printf '{"ok":true,"action":"reboot"}'
    ( sleep 1; reboot ) >/dev/null 2>&1 &
    ;;
  adb_on)
    /etc/init.d/adbd start >/dev/null 2>&1
    printf '{"ok":true,"adb":"on"}'
    ;;
  adb_off)
    # Reply first, then stop adbd a moment later so the HTTP response is
    # delivered before the debug bridge (and any adb-side session) drops.
    printf '{"ok":true,"adb":"off"}'
    ( sleep 1; /etc/init.d/adbd stop ) >/dev/null 2>&1 &
    ;;
  adb_status)
    if pgrep adbd >/dev/null 2>&1; then printf '{"adb":"on"}'; else printf '{"adb":"off"}'; fi
    ;;
  ttl_on)  ttl_on;  printf '{"ok":true,"ttl":"%s"}' "$(ttl_state)" ;;
  ttl_off) ttl_off; printf '{"ok":true,"ttl":"%s"}' "$(ttl_state)" ;;
  ttl_status) printf '{"ttl":"%s"}' "$(ttl_state)" ;;
  ftp_on)  ftp_on;  sleep 1; printf '{"ok":true,"ftp":"%s"}' "$(ftp_state)" ;;
  ftp_off) ftp_off; printf '{"ok":true,"ftp":"%s"}' "$(ftp_state)" ;;
  ftp_status) printf '{"ftp":"%s"}' "$(ftp_state)" ;;
  telnet_on)  tel_on;  sleep 1; printf '{"ok":true,"telnet":"%s"}' "$(tel_state)" ;;
  telnet_off) tel_off; printf '{"ok":true,"telnet":"%s"}' "$(tel_state)" ;;
  telnet_status) printf '{"telnet":"%s"}' "$(tel_state)" ;;
  *) printf '{"error":"unknown action"}' ;;
esac
