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
  *_on|*_off|reboot|setpw|setapn)
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
MARK=/etc/signalmod_ttl
# Bind admin services to the LAN only (never the WAN). Derived from br0 so it
# follows any LAN-IP change instead of being hardcoded.
LAN_IP=$(ip -4 addr show br0 2>/dev/null | grep -o 'inet [0-9.]*' | head -1 | cut -d' ' -f2)
[ -z "$LAN_IP" ] && LAN_IP=192.168.0.1

# Configurable ports and values, written by settings.sh. Read with sed rather
# than sourced: this file is 600 and settings.sh range-checks everything that
# goes in, but sourcing a config as shell means any future path that writes it
# becomes code execution. Reading key=value costs nothing and closes that off.
CONF=/etc/signalmod.conf
cfg(){ v=$(sed -n "s/^$1=//p" "$CONF" 2>/dev/null | tail -1)
       case "$v" in ''|*[!0-9]*) printf '%s' "$2" ;; *) printf '%s' "$v" ;; esac; }
TELNET_PORT=$(cfg telnet_port 23)
TTL_VAL=$(cfg ttl_value 65)
FTP_MARK=/etc/signalmod_ftp
SAVER_MARK=/etc/signalmod_saver
saver_state() { [ -f "$SAVER_MARK" ] && echo on || echo off; }
SDLOG_MARK=/etc/signalmod_sdlog
sdlog_state() { [ -f "$SDLOG_MARK" ] && echo on || echo off; }

# --- FTP (busybox ftpd via tcpsvd, rooted at /, LAN-only) ------------------
# FTP on this device is the FIRMWARE'S OWN vsftpd, started by
# /etc/init.d/service_storageshare and holding 0.0.0.0:21 from boot. The mod
# used to spawn its own tcpsvd ftpd and grep port 21 for state, which meant:
#   * the pill read ON because vsftpd was listening, not because we started it;
#   * ftp_off could never stop it, since it killed tcpsvd and not vsftpd;
#   * our tcpsvd could never bind 21 anyway, vsftpd already had it.
# So the toggle reported and controlled the wrong thing. It drives vsftpd now.
ftp_state() { pgrep -x vsftpd >/dev/null 2>&1 && echo on || echo off; }
# Use the FIRMWARE'S OWN start_vsftpd, not a bare "vsftpd &". That helper also
# regenerates the config from the right template, creates the FTP user, and
# bind-mounts the SD card at /home/<user>/sdcard. Starting the daemon on its own
# skips all of that and can leave a server with nothing to serve.
ftp_mode() {
  # Mirrors service_storageshare: anonymous off means the signed-in user,
  # otherwise read-write or read-only anonymous.
  a=$(uci get storageshare.property.ifanon 2>/dev/null)
  w=$(uci get storageshare.property.ifrw 2>/dev/null)
  if [ "$a" = "1" ]; then
    [ "$w" = "1" ] && echo anonrw || echo anonro
  else
    echo signed
  fi
}

ftp_on() {
  ftp_state | grep -q on && { touch "$FTP_MARK"; return; }
  # Stamp the configured port into the templates first: start_vsftpd rebuilds
  # the live conf from them, so anything written afterwards would be wiped.
  [ -x /usr/bin/ftp_port.sh ] && /usr/bin/ftp_port.sh 2>/dev/null
  setsid start_vsftpd "$(ftp_mode)" </dev/null >/dev/null 2>&1 &
  touch "$FTP_MARK" 2>/dev/null
}
ftp_off() { stop_vsftpd 2>/dev/null || pkill -x vsftpd 2>/dev/null; rm -f "$FTP_MARK" 2>/dev/null; }

# --- Telnet (busybox telnetd; often already listening on :23) --------------
tel_state() { pgrep -x telnetd >/dev/null 2>&1 && echo on || echo off; }
tel_on()  { tel_state | grep -q on || { setsid telnetd -l /bin/sh -p "$TELNET_PORT" </dev/null >/dev/null 2>&1 & } ; }
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
  # start_vsftpd is backgrounded and does real work (user setup, bind mount)
  # before the daemon appears, so reading the state straight after returns "off"
  # for a restart that is in fact fine. Wait for it rather than report a lie.
  ftp_restart)
    ftp_off; sleep 2; ftp_on
    i=0
    while [ "$i" -lt 12 ]; do
      ftp_state | grep -q on && break
      i=$((i + 1)); sleep 1
    done
    printf '{"ok":true,"ftp":"%s"}' "$(ftp_state)" ;;
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

  # ---- diagnostic logging to the SD card --------------------------------
  # Same marker-file pattern, so it survives a reboot and the daemon picks it
  # up without a restart. Turning it on with no card mounted is not an error:
  # sd_log.sh simply does nothing until a card appears, and it never falls back
  # to /tmp, because a log that dies with the device is the thing this exists
  # to avoid.
  sdlog_on)     touch /etc/signalmod_sdlog 2>/dev/null; printf '{"ok":true,"sdlog":"%s"}' "$(sdlog_state)" ;;
  sdlog_off)    rm -f /etc/signalmod_sdlog 2>/dev/null; printf '{"ok":true,"sdlog":"%s"}' "$(sdlog_state)" ;;
  sdlog_status) printf '{"sdlog":"%s"}' "$(sdlog_state)" ;;

  # Data roaming. A travel eSIM roams by definition -- its home network is not
  # the one it attaches to -- so with this off the modem registers, shows full
  # signal, and silently refuses to pass data. Both keys are set together
  # because the firmware consults them separately.
  roaming_on)
    uci set network_status.network_status_data.roam_switch=1
    uci set network_status.network_status_data.connect_when_roam=1
    uci commit network_status
    printf '{"ok":true,"roaming":"on"}'
    ;;
  roaming_off)
    uci set network_status.network_status_data.roam_switch=0
    uci set network_status.network_status_data.connect_when_roam=0
    uci commit network_status
    printf '{"ok":true,"roaming":"off"}'
    ;;
  roaming_status)
    printf '{"roaming":"%s"}' "$([ "$(uci get network_status.network_status_data.roam_switch 2>/dev/null)" = 1 ] && echo on || echo off)"
    ;;

  # Set the APN on the active profile. Body, not query string, so it stays out
  # of the web server log. Travel eSIMs need the provider's own APN; the one the
  # modem picks automatically is the underlying carrier's and often carries no data.
  setapn)
    len="${CONTENT_LENGTH:-0}"
    case "$len" in ''|*[!0-9]*) len=0 ;; esac
    if [ "$len" -lt 1 ] || [ "$len" -gt 100 ]; then
      printf '{"error":"no APN in request body"}'
    else
      NEW=$(dd bs=1 count="$len" 2>/dev/null | tr -d '\r\n ')
      if ! echo "$NEW" | grep -qE '^[A-Za-z0-9._-]{1,64}$'; then
        printf '{"error":"rejected: an APN is letters, digits, dot, dash, underscore"}'
      else
        IDX=$(uci get isp_profile.profile_isp_data.isp_index 2>/dev/null); [ -n "$IDX" ] || IDX=1
        OLD=$(uci get "isp_profile.profile_isp_data_$IDX.apn_name_v4" 2>/dev/null)
        uci set "isp_profile.profile_isp_data_$IDX.apn_name_v4=$NEW"
        uci commit isp_profile
        printf '{"ok":true,"apn":"%s","was":"%s","profile":"%s"}' "$NEW" "$OLD" "$IDX"
      fi
    fi
    ;;

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
