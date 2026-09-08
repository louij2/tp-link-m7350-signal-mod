#!/bin/sh
# Inspect and change the data settings that decide whether a SIM actually gets
# online: the APN, and whether data is allowed while roaming.
#
#   apn.sh                        show everything, change nothing
#   apn.sh --roaming on|off       allow or forbid data while roaming
#   apn.sh --apn <name> [--profile N]   set the APN on profile N (default: active)
#
# WHY ROAMING MATTERS: a travel eSIM (Nomad, Airalo and friends) is roaming by
# definition -- its home network is not the one it attaches to. With roaming off
# the modem registers, shows full signal, and refuses to pass data. That looks
# exactly like a wrong APN, so check this first.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
say() { printf '%s\n' "$*"; }
g()   { uci get "$1" 2>/dev/null; }

ACTIVE=$(g isp_profile.profile_isp_data.isp_index)
[ -n "$ACTIVE" ] || ACTIVE=$(g isp_profile.profile_isp_data.index)
[ -n "$ACTIVE" ] || ACTIVE=1

show() {
  say "Data roaming"
  R=$(g network_status.network_status_data.roam_switch)
  C=$(g network_status.network_status_data.connect_when_roam)
  S=$(g network_status.network_status_data.roam_status)
  say "  roam_switch        ${R:-?}   $([ "$R" = 1 ] && echo 'ON (data allowed while roaming)' || echo 'OFF (no data while roaming)')"
  say "  connect_when_roam  ${C:-?}"
  say "  roam_status        ${S:-?}   $([ "$S" = 1 ] && echo '(currently roaming)' || echo '(not roaming)')"
  say ""
  say "Operator / SIM"
  say "  ISP name    $(g isp_profile.profile_isp_data.isp_name)"
  say "  MCC/MNC     $(g isp_profile.profile_isp_data.mcc)$(g isp_profile.profile_isp_data.mnc)"
  say "  active idx  $ACTIVE"
  say ""
  say "APN profiles"
  i=1
  while [ "$i" -le 8 ]; do
    n=$(g "isp_profile.profile_isp_data_$i.profile_name")
    a=$(g "isp_profile.profile_isp_data_$i.apn_name_v4")
    u=$(g "isp_profile.profile_isp_data_$i.user_name_v4")
    t=$(g "isp_profile.profile_isp_data_$i.auth_type_v4")
    if [ -n "$n" ] || [ -n "$a" ]; then
      mark=" "; [ "$i" = "$ACTIVE" ] && mark="*"
      say "  $mark $i  name='${n:-}'  apn='${a:-}'  user='${u:-}'  auth='${t:-}'"
    fi
    i=$((i + 1))
  done
  say ""
  say "Link"
  say "  rmnet0  $(ip -4 addr show rmnet0 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -1 || echo 'no address')"
  say "  route   $(ip route 2>/dev/null | grep '^default' | head -1 || echo 'no default route')"
}

[ $# -eq 0 ] && { show; say ""; say "Nothing changed. Use --roaming or --apn to make changes."; exit 0; }

PROFILE="$ACTIVE"; NEWAPN=""; ROAM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --roaming) ROAM="$2"; shift 2 ;;
    --apn)     NEWAPN="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    *) say "unknown option: $1"; exit 1 ;;
  esac
done

CHANGED=0
if [ -n "$ROAM" ]; then
  case "$ROAM" in
    on)  V=1 ;;
    off) V=0 ;;
    *) say "--roaming takes on or off"; exit 1 ;;
  esac
  uci set network_status.network_status_data.roam_switch="$V"
  uci set network_status.network_status_data.connect_when_roam="$V"
  uci commit network_status
  say "data roaming -> $ROAM"
  CHANGED=1
fi

if [ -n "$NEWAPN" ]; then
  case "$PROFILE" in [1-8]) : ;; *) say "--profile must be 1..8"; exit 1 ;; esac
  OLD=$(g "isp_profile.profile_isp_data_$PROFILE.apn_name_v4")
  uci set "isp_profile.profile_isp_data_$PROFILE.apn_name_v4=$NEWAPN"
  uci commit isp_profile
  say "profile $PROFILE APN: '${OLD:-unset}' -> '$NEWAPN'"
  CHANGED=1
fi

if [ "$CHANGED" = 1 ]; then
  say ""
  say "Roaming changes take effect on the next data reconnect."
  if [ -n "$NEWAPN" ]; then
    say ""
    say "WARNING: the APN written above almost certainly will NOT reach the modem."
    say "QCMAP is what actually dials, and /etc/mobileap_cfg.xml points it at"
    say "  <V4_UMTS_PROFILE_INDEX>0</V4_UMTS_PROFILE_INDEX>"
    say "which is a profile held in the modem, not this uci list. The uci entries"
    say "are only what the web UI displays. Setting one here changes the display"
    say "and nothing else."
    say ""
    say "To change the APN for real, use the stock UI:"
    say "  Advanced -> Dial-up Settings -> add a profile"
    say "That posts to qcmap_web_cgi, which does reach the modem."
    say ""
    say "For a travel eSIM (Nomad, Airalo) set APN type to Dynamic and auth to"
    say "None. Those SIMs roam by definition, and the firmware otherwise picks"
    say "the VISITED network operator by MCC/MNC and applies that operator's own"
    say "subscriber APN, which the network will reject for a roamer."
  fi
  say ""
  say "Then re-run apn.sh with no arguments and confirm rmnet0 has an address."
fi
