# M7350+ Extreme login banner. Dropped into /etc/profile.d, which the stock
# /etc/profile already sources, so nothing upstream needs patching and removing
# the file removes the feature.
#
# Guarded to interactive TTY sessions only. This matters: `ssh host 'sha256sum
# file'` must return ONLY the digest, and deploy.sh verifies every file that
# way. A banner leaking into non-interactive output would silently break it.
case "$-" in *i*) ;; *) return 0 ;; esac
[ -t 1 ] || return 0

_sm_j(){ sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p" "$2" 2>/dev/null | head -1; }
_sm_dur(){ s=${1%%.*}; [ -n "$s" ] || return; printf '%dd %dh %dm' $((s/86400)) $((s%86400/3600)) $((s%3600/60)); }

_SM_S=/tmp/signal.json
_SM_C='\033[36m'; _SM_D='\033[90m'; _SM_G='\033[32m'; _SM_W='\033[97m'; _SM_R='\033[0m'

_sm_rsrp=$(_sm_j rsrp $_SM_S); _sm_rsrq=$(_sm_j rsrq $_SM_S)
_sm_rssi=$(_sm_j rssi $_SM_S); _sm_band=$(_sm_j band $_SM_S)
_sm_mode=$(_sm_j mode $_SM_S)
_sm_temp=$(awk '{ if ($1 > 1000) printf "%d", $1/1000; else printf "%d", $1 }' /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
_sm_up=$(_sm_dur "$(cut -d' ' -f1 /proc/uptime 2>/dev/null)")
_sm_load=$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)
_sm_batt=$(uci get battery.battery_mgr.power_level 2>/dev/null)
_sm_lan=$(ip -4 addr show br0 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -1)
_sm_wan=$(ip -4 addr show rmnet0 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -1)
_sm_mem=$(awk '/MemAvailable|MemFree/{m=$2} END{printf "%d MB", m/1024}' /proc/meminfo 2>/dev/null)

printf "\n${_SM_C}  M7350+ ${_SM_W}EXTREME${_SM_R}   ${_SM_D}$(uname -sr)${_SM_R}\n"
printf "${_SM_D}  ------------------------------------------------${_SM_R}\n"
[ -n "$_sm_rsrp" ] && printf "  ${_SM_D}LTE     ${_SM_R}${_SM_G}%s${_SM_R} dBm / %s dB   %s %s\n" \
  "$_sm_rsrp" "${_sm_rsrq:-?}" "${_sm_mode:-?}" "${_sm_band:+Band $_sm_band}"
[ -z "$_sm_rsrp" ] && [ -n "$_sm_rssi" ] && printf "  ${_SM_D}LTE     ${_SM_R}RSSI %s dBm   %s\n" "$_sm_rssi" "${_sm_mode:-?}"
printf "  ${_SM_D}Network ${_SM_R}lan %s   wan %s\n" "${_sm_lan:-none}" "${_sm_wan:-down}"
printf "  ${_SM_D}Health  ${_SM_R}%s   load %s   mem %s   batt %s\n" "${_sm_temp:+${_sm_temp} C}" "${_sm_load:-?}" "${_sm_mem:-?}" "${_sm_batt:+${_sm_batt}%}"
printf "  ${_SM_D}Uptime  ${_SM_R}%s\n\n" "${_sm_up:-?}"

unset _sm_rsrp _sm_rsrq _sm_rssi _sm_band _sm_mode _sm_temp _sm_up _sm_load _sm_lan _sm_wan _sm_mem _sm_batt
unset _SM_S _SM_C _SM_D _SM_G _SM_W _SM_R
