#!/bin/sh
# M7350 mod: alternate the OLED operator line between the custom model name and
# the real ISP every ~20s. oledd renders isp_profile.profile_isp_data.isp_name,
# so we flip that value and nudge oledd with a ubus event (NO oledd restart --
# a restart blanks the panel). We use `uci set` WITHOUT `uci commit` so the flip
# lives in the /tmp uci delta (tmpfs) and never wears the NAND flash.
exec </dev/null >/dev/null 2>&1

KEY=isp_profile.profile_isp_data.isp_name
MODEL="M7350+"
ISP="Three"
INTERVAL=20

refresh() {
  ubus send mobile_event '{"mobile_state":1}' 2>/dev/null
  ubus send oled_event '{}' 2>/dev/null
  ubus send network_mode_event '{}' 2>/dev/null
}

while true; do
  uci set "$KEY"="$MODEL" 2>/dev/null; refresh
  sleep "$INTERVAL"
  uci set "$KEY"="$ISP" 2>/dev/null; refresh
  sleep "$INTERVAL"
done
