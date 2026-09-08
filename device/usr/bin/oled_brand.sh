#!/bin/sh
# M7350 mod: alternate the OLED operator line between the custom model name and
# the real ISP every ~20s. oledd renders isp_profile.profile_isp_data.isp_name,
# so we flip that value and nudge oledd with a ubus event (NO oledd restart --
# a restart blanks the panel). We use `uci set` WITHOUT `uci commit` so the flip
# lives in the /tmp uci delta (tmpfs) and never wears the NAND flash.
exec </dev/null >/dev/null 2>&1

KEY=isp_profile.profile_isp_data.isp_name
MODEL="M7350+"
INTERVAL=20

# The operator was hardcoded to "Three" here, so the panel named the SIM that
# happened to be fitted when this was written and kept naming it after a swap.
# Ask each cycle instead: a SIM change, or an eSIM profile switch, is picked up
# without a restart. Falls back to the last good value so a transient uci read
# failure cannot blank the line.
ISP="$(/usr/bin/isp_name.sh 2>/dev/null)"
[ -n "$ISP" ] || ISP="$MODEL"

refresh() {
  ubus send mobile_event '{"mobile_state":1}' 2>/dev/null
  ubus send oled_event '{}' 2>/dev/null
  ubus send network_mode_event '{}' 2>/dev/null
}

while true; do
  uci set "$KEY"="$MODEL" 2>/dev/null; refresh
  sleep "$INTERVAL"
  NEW="$(/usr/bin/isp_name.sh 2>/dev/null)"
  [ -n "$NEW" ] && ISP="$NEW"
  uci set "$KEY"="$ISP" 2>/dev/null; refresh
  sleep "$INTERVAL"
done
