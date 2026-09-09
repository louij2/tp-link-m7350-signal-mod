#!/bin/sh
# Print the operator name, from one place, for both the OLED and the web UI.
#
# WHY NOT JUST READ isp_profile.profile_isp_data.isp_name:
#   * oled_brand.sh repurposes that key to flash the model name on the panel, so
#     at any instant it may hold "M7350+" rather than an operator at all;
#   * the firmware never refreshes it on a SIM swap. After moving from a Three
#     SIM to a Nomad eSIM it still read "Three" while the mcc/mnc stored right
#     beside it had correctly changed to 234/15, Vodafone.
# So the MCC/MNC is the source of truth and that key is not.
#
# /etc/signalmod_isp overrides the name ON THE OLED ONLY. A travel eSIM has no
# identity of its own on the network: it roams on a host operator, so the modem
# reports the host (Vodafone), never the reseller you bought it from (Nomad,
# Airalo). The override is there if you want the panel to name the reseller.
#
#   isp_name.sh             honour the override, then fall back to the network
#   isp_name.sh --network   what the network says, always, ignoring the override
#
# The web UI uses --network so a reported operator is never a label someone
# typed. A field that says "Nomad" next to an mcc/mnc of 23415 invites exactly
# the wrong conclusion when you are trying to work out why data will not flow.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

WANT_NETWORK=0
[ "$1" = "--network" ] && WANT_NETWORK=1

OVERRIDE=/etc/signalmod_isp
if [ "$WANT_NETWORK" = 0 ] && [ -s "$OVERRIDE" ]; then
  # Single line, safe characters only, short enough for the OLED line.
  # NOT [:print:] -- this busybox build does not support POSIX character
  # classes in tr and silently deletes every character instead of erroring,
  # which blanks the panel rather than failing loudly. Explicit range only.
  NAME=$(head -1 "$OVERRIDE" | tr -dc 'A-Za-z0-9 .()+&_-' | cut -c1-16)
  if [ -n "$NAME" ]; then printf '%s\n' "$NAME"; exit 0; fi
  # An override that survives none of that is treated as absent, so a bad file
  # falls through to the real operator rather than emptying the line.
fi

MCC=$(uci get isp_profile.profile_isp_data.mcc 2>/dev/null)
MNC=$(uci get isp_profile.profile_isp_data.mnc 2>/dev/null)

case "$MCC-$MNC" in
  234-20)                   echo "Three (SMARTY)" ;;
  234-30|234-33|234-34|234-86) echo "EE" ;;
  234-15)                   echo "Vodafone" ;;
  234-10|234-11|234-02)     echo "O2" ;;
  234-50)                   echo "JT" ;;
  -|"")                     echo "No SIM" ;;
  # Deliberately NOT falling back to isp_name: oled_brand.sh may have just
  # written the model name into it, which would make the OLED alternate between
  # the model name and the model name.
  *)                        echo "$MCC-$MNC" ;;
esac
