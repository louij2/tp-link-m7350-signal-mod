#!/bin/sh
# M7350 mod: About Device info for the web UI.
# Reads product identifiers from UCI + the MAC from sysfs -- all device-side, so
# no per-device PII is ever hardcoded in the repo. IMSI / SIM number are only
# populated here if the daemon's optional AT cache (/tmp/deviceinfo.json with
# {"imsi":"...","sim":"..."}) exists; otherwise they come back empty.
#
# AUTH: IMEI / IMSI / SIM number are subscriber identifiers, not device trivia --
# an IMSI is enough to identify and track a subscriber. They are therefore
# returned ONLY to a caller that presents the control password (X-Auth, same
# gate as control.sh), and are redacted for everyone else, including when no
# password is configured. Everything else (model, firmware, MAC, operator, APN)
# stays open so the About card still renders without a prompt. When the fields
# are withheld the response carries "locked":"1" so the UI can offer to unlock.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

PWFILE=/etc/signalmod.pw
AUTHED=0
if [ -s "$PWFILE" ]; then
  supplied="$HTTP_X_AUTH"
  [ -z "$supplied" ] && supplied=$(printf '%s' "$QUERY_STRING" | sed -n 's/.*[?&]auth=\([^&]*\).*/\1/p')
  [ "$supplied" = "$(cat "$PWFILE" 2>/dev/null)" ] && AUTHED=1
fi

printf 'Content-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nCache-Control: no-store\r\n\r\n'

g() { uci get "$1" 2>/dev/null; }

# ---- Custom branding (edit these to rebrand the About page) --------------
BRAND_MODEL="M7350+"
BRAND_FW="Extreme 2.5.1 (base 1.1.3 Build 161226)"
# --------------------------------------------------------------------------

MODEL="$BRAND_MODEL"
FWV="$BRAND_FW"
FWB=""
HW=$(g product.info.hardware_ver)
REG=$(g product.info.product_region)
IMEI=$(g product.lte.imei)
MAC=$(cat /sys/class/net/br0/address 2>/dev/null | tr 'a-z' 'A-Z')

# IMSI / SIM number: the modem stack caches these in UCI (sim_msisdn) -- no AT
# query needed, and no PII lands in the repo (read live from the device).
IMSI=$(g sim_msisdn.msisdn.imsi); [ "$IMSI" = "0" ] && IMSI=""
SIM=$(g sim_msisdn.msisdn.simNumber); [ "$SIM" = "0" ] && SIM=""

# Operator / APN / radio config (all from UCI -- safe, no AT).
MCC=$(g isp_profile.profile_isp_data.mcc)
MNC=$(g isp_profile.profile_isp_data.mnc)
# Real operator by MCC/MNC (isp_name is repurposed for the OLED, so don't use it
# here). Falls back to isp_name for networks not in this small UK-focused map.
case "$MCC-$MNC" in
  234-20) OPER="Three (SMARTY)" ;;
  234-30|234-33|234-34|234-86) OPER="EE" ;;
  234-15) OPER="Vodafone" ;;
  234-10|234-11|234-02) OPER="O2" ;;
  234-50) OPER="JT" ;;
  *) OPER=$(g isp_profile.profile_isp_data.isp_name) ;;
esac
APN=$(g isp_profile.profile_isp_data_1.apn_name_v4)
PREF=$(g 4g_network.network_mode.preferred_network)
case "$PREF" in
  0) NETMODE="Auto" ;; 1) NETMODE="GSM only" ;; 2) NETMODE="WCDMA only" ;;
  3) NETMODE="LTE only" ;; 4) NETMODE="LTE/WCDMA" ;; *) NETMODE="$PREF" ;;
esac

BASE=$(g product.info.product_name); [ -z "$BASE" ] && BASE=M7350
# Withhold the subscriber identifiers unless the caller authenticated.
LOCKED=0
if [ "$AUTHED" != 1 ]; then
  IMEI=""; IMSI=""; SIM=""; LOCKED=1
fi

printf '{"model":"%s","firmware":"%s","hardware":"%s(%s) v%s","imei":"%s","imsi":"%s","sim":"%s","mac":"%s","operator":"%s","mccmnc":"%s%s","apn":"%s","netmode":"%s","locked":"%s"}' \
  "$MODEL" "$FWV" "$BASE" "$REG" "$HW" "$IMEI" "$IMSI" "$SIM" "$MAC" "$OPER" "$MCC" "$MNC" "$APN" "$NETMODE" "$LOCKED"
