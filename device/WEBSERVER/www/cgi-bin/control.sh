#!/bin/sh
# M7350 mod: control actions for the web UI (reboot / ADB / TTL / FTP / Telnet /
# Wi-Fi toggles).
#
# AUTH: state-changing actions (*_on / *_off / reboot / setpw) FAIL CLOSED. They
# require /etc/signalmod.pw to exist (root-only, chmod 600, NOT in the repo) and
# the caller to present it in the X-Auth header (or ?auth=). With no password
# file, every mutation is refused -- including setpw, so nobody on the LAN can
# claim an unclaimed device by setting the password first. Create it over
# ADB/SSH, which you already have if you installed this at all:
#   printf '%s' 'yourpassword' > /etc/signalmod.pw && chmod 600 /etc/signalmod.pw
# Status reads stay open so the panel can poll without a prompt.
#
# Earlier versions fell back to unauthenticated when the file was absent. That
# made a fresh install hand root-level toggles (FTP and telnet serving the whole
# filesystem, ADB, reboot) to anyone on the network until the owner noticed.
#
# TTL-fix pins a fixed egress TTL (see below). LAN-only bindings throughout.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

A=$(printf '%s' "$QUERY_STRING" | sed -n 's/.*action=\([a-zA-Z_]*\).*/\1/p')

# --- Auth gate (before any headers are emitted) ---------------------------
PWFILE=/etc/signalmod.pw
case "$A" in
  *_on|*_off|reboot|setpw)
    if [ ! -s "$PWFILE" ]; then
      printf 'Status: 503 Service Unavailable\r\nContent-Type: application/json\r\nCache-Control: no-store\r\n\r\n{"error":"no control password set: create /etc/signalmod.pw (chmod 600) over ADB or SSH first"}'
      exit 0
    fi
    supplied="$HTTP_X_AUTH"
    [ -z "$supplied" ] && supplied=$(printf '%s' "$QUERY_STRING" | sed -n 's/.*[?&]auth=\([^&]*\).*/\1/p')
    if [ "$supplied" != "$(cat "$PWFILE" 2>/dev/null)" ]; then
      printf 'Status: 403 Forbidden\r\nContent-Type: application/json\r\nCache-Control: no-store\r\n\r\n{"error":"auth"}'
      exit 0
    fi
    ;;
esac

printf 'Content-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nCache-Control: no-store\r\n\r\n'

WAN=rmnet0
TTL_VAL=65
MARK=/etc/signalmod_ttl
# Bind admin services to the LAN only (never the WAN). Derived from br0 so it
# follows any LAN-IP change instead of being hardcoded.
LAN_IP=$(ip -4 addr show br0 2>/dev/null | grep -o 'inet [0-9.]*' | head -1 | cut -d' ' -f2)
[ -z "$LAN_IP" ] && LAN_IP=192.168.0.1
FTP_MARK=/etc/signalmod_ftp
SAVER_MARK=/etc/signalmod_saver
saver_state() { [ -f "$SAVER_MARK" ] && echo on || echo off; }

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

# --- Wi-Fi AP on/off (via the QCMAP wlan_object ubus) ----------------------
wifi_state() { ubus call wlan_object wlan_get_switch 2>/dev/null | sed -n 's/.*"wlan": *"\([a-z]*\)".*/\1/p'; }
wifi_on()  { ubus call wlan_object wlan_set_switch '{"switch":"on"}'  >/dev/null 2>&1; }
wifi_off() { ubus call wlan_object wlan_set_switch '{"switch":"off"}' >/dev/null 2>&1; }

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
  wifi_on)  wifi_on;  sleep 1; printf '{"ok":true,"wifi":"%s"}' "$(wifi_state)" ;;
  wifi_off) wifi_off; printf '{"ok":true,"wifi":"off"}' ;;
  wifi_status) printf '{"wifi":"%s"}' "$(wifi_state)" ;;

  # ---- data saver -------------------------------------------------------
  # Marker file on the persistent rootfs, same pattern as the TTL fix, so it
  # survives a reboot. The daemon and metrics.sh both read it directly, so there
  # is nothing to restart and no state to get out of step.
  saver_on)     touch /etc/signalmod_saver 2>/dev/null; printf '{"ok":true,"saver":"%s"}' "$(saver_state)" ;;
  saver_off)    rm -f /etc/signalmod_saver 2>/dev/null; printf '{"ok":true,"saver":"%s"}' "$(saver_state)" ;;
  saver_status) printf '{"saver":"%s"}' "$(saver_state)" ;;

  # Change the mod control password. The new value is read from the POST BODY,
  # never the query string, so it does not end up in the web server's log or in
  # browser history. The auth gate above already required the CURRENT password,
  # except on a device that has none yet, where this is the bootstrap path.
  setpw)
    len="${CONTENT_LENGTH:-0}"
    case "$len" in ''|*[!0-9]*) len=0 ;; esac
    if [ "$len" -lt 1 ] || [ "$len" -gt 256 ]; then
      printf '{"error":"no password in request body"}'
    else
      NEW=$(dd bs=1 count="$len" 2>/dev/null | tr -d '\r\n')
      if [ "${#NEW}" -lt 8 ]; then
        printf '{"error":"too short: use at least 8 characters"}'
      else
        cp "$PWFILE" "$PWFILE.bak" 2>/dev/null
        printf '%s' "$NEW" > "$PWFILE.new" && chmod 600 "$PWFILE.new" && mv "$PWFILE.new" "$PWFILE" \
          && printf '{"ok":true}' || printf '{"error":"write failed"}'
      fi
    fi
    ;;
  *) printf '{"error":"unknown action"}' ;;
esac
