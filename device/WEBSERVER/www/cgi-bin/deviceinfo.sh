#!/bin/sh
# M7350 mod: About Device info for the web UI.
# Reads product identifiers from UCI + the MAC from sysfs -- all device-side, so
# no per-device PII is ever hardcoded in the repo. IMSI / SIM number are only
# populated here if the daemon's optional AT cache (/tmp/deviceinfo.json with
# {"imsi":"...","sim":"..."}) exists; otherwise they come back empty.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
printf 'Content-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nCache-Control: no-store\r\n\r\n'

g() { uci get "$1" 2>/dev/null; }
MODEL=$(g product.info.product_name); [ -z "$MODEL" ] && MODEL=M7350
FWV=$(g product.info.firmware_ver)
FWB=$(g product.info.firmware_ver_build)
HW=$(g product.info.hardware_ver)
REG=$(g product.info.product_region)
IMEI=$(g product.lte.imei)
IMSI=$(g product.lte.imsi); [ "$IMSI" = "0" ] && IMSI=""
SIM=$(g product.lte.simNumber); [ "$SIM" = "0" ] && SIM=""
MAC=$(cat /sys/class/net/br0/address 2>/dev/null | tr 'a-z' 'A-Z')

# Optional AT-derived values (IMSI / SIM number) cached by the daemon.
if [ -f /tmp/deviceinfo.json ]; then
  ai=$(sed -n 's/.*"imsi":"\([^"]*\)".*/\1/p' /tmp/deviceinfo.json 2>/dev/null)
  as=$(sed -n 's/.*"sim":"\([^"]*\)".*/\1/p'  /tmp/deviceinfo.json 2>/dev/null)
  [ -n "$ai" ] && IMSI=$ai
  [ -n "$as" ] && SIM=$as
fi

printf '{"model":"%s","firmware":"%s %s","hardware":"%s(%s) v%s","imei":"%s","imsi":"%s","sim":"%s","mac":"%s"}' \
  "$MODEL" "$FWV" "$FWB" "$MODEL" "$REG" "$HW" "$IMEI" "$IMSI" "$SIM" "$MAC"
