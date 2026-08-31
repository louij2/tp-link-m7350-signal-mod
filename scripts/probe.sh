#!/usr/bin/env bash
# READ-ONLY compatibility probe. Changes NOTHING on the device.
#
# Run this if you have an M7350 (or similar TP-Link MiFi) and want to know
# whether this mod will work on your hardware revision -- or to help add support
# for it. It prints a report you can paste into a GitHub issue.
#
#   scripts/probe.sh                 # auto: ADB if plugged in, else SSH
#   M7350_SSH_TARGET=root@192.168.0.1 scripts/probe.sh
#
# It only reads. It does not write files, toggle services, or send any AT
# command that changes modem state. The AT reads are queries only; the one thing
# it deliberately never sends is AT+COPS=? (a full network scan), which is slow
# and can wedge a channel.
set -euo pipefail

ADB="${ADB:-adb}"
HOST="${M7350_HOST:-192.168.0.1}"
USER_="${M7350_USER-root}"
TARGET="${M7350_SSH_TARGET:-${USER_:+$USER_@}$HOST}"
SSH_OPTS="${M7350_SSH_OPTS:--o ConnectTimeout=8 -o BatchMode=yes}"

say(){ printf '\n\033[1;36m== %s\033[0m\n' "$1"; }
die(){ printf '\033[1;31m[!]\033[0m %s\n' "$1" >&2; exit 1; }

TRANSPORT="${M7350_TRANSPORT:-auto}"
if [ "$TRANSPORT" = auto ]; then
  if "$ADB" get-state >/dev/null 2>&1; then TRANSPORT=adb
  elif ssh $SSH_OPTS -T "$TARGET" true >/dev/null 2>&1; then TRANSPORT=ssh
  else die "No device. Plug it in over USB with ADB enabled, or set M7350_SSH_TARGET."; fi
fi
run(){ case "$TRANSPORT" in adb) "$ADB" shell "$1" ;; ssh) ssh $SSH_OPTS -T "$TARGET" "$1" ;; esac; }

echo "M7350 mod compatibility probe -- paste this whole output into an issue"
echo "https://github.com/louij2/tp-link-m7350-signal-mod/issues/new"
echo "transport: $TRANSPORT"

say "Identity"
run 'echo "  product : $(uci get product.info.product_name 2>/dev/null)"
     echo "  hardware: $(uci get product.info.hardware_ver 2>/dev/null)"
     echo "  region  : $(uci get product.info.product_region 2>/dev/null)"
     echo "  firmware: $(uci get product.info.software_ver 2>/dev/null)$(uci get product.info.firmware_ver 2>/dev/null)"
     echo "  soc     : $(cat /sys/devices/soc0/soc_id 2>/dev/null) $(cat /sys/devices/soc0/machine 2>/dev/null)"
     echo "  cpu     : $(sed -n "s/^Processor.*: //p" /proc/cpuinfo | head -1)"
     echo "  kernel  : $(uname -r)"' 2>/dev/null

say "Web UI layout (does the mod know where to inject?)"
run 'cd /WEBSERVER/www 2>/dev/null || { echo "  NO /WEBSERVER/www -- different firmware layout"; exit 0; }
     echo "  pages   : $(ls *.html 2>/dev/null | tr "\n" " ")"
     echo "  statusPage class present: $(grep -lc statusPage status.html 2>/dev/null >/dev/null && echo yes || echo NO)"
     echo "  statusContent wrapper  : $(grep -c statusContent status.html 2>/dev/null || echo 0)"
     echo "  section classes        : $(grep -oE "(connection|wifi|statistic|pin)Section" status.html 2>/dev/null | sort -u | tr "\n" " ")"' 2>/dev/null

say "AT channels (which one answers what)"
echo "  NOTE: if this mod is already installed, its daemon holds one channel and"
echo "        that channel may report 'nothing' here. On a stock device all"
echo "        present channels are probed cleanly."
run 'for S in /dev/smd7 /dev/smd8 /dev/smd11; do
       [ -c "$S" ] || { echo "  $S: absent"; continue; }
       : > /tmp/_probe.txt
       ( cat "$S" > /tmp/_probe.txt 2>/dev/null ) & P=$!
       sleep 0.2
       for c in "AT" "AT+CSQ" "AT\$QCRSRP?" "AT+CEREG?" "AT+COPS?" "AT+CRSM=176,12258,0,0,10" "AT+CSIM=?"; do
         printf "%s\r\n" "$c" > "$S" 2>/dev/null; sleep 0.5
       done
       sleep 0.6; kill $P 2>/dev/null; wait $P 2>/dev/null
       ok=""
       grep -q "OK"        /tmp/_probe.txt 2>/dev/null && ok="$ok AT"
       grep -q "+CSQ"      /tmp/_probe.txt 2>/dev/null && ok="$ok CSQ"
       grep -q "QCRSRP:"   /tmp/_probe.txt 2>/dev/null && ok="$ok QCRSRP"
       grep -q "+CEREG:"   /tmp/_probe.txt 2>/dev/null && ok="$ok CEREG"
       grep -q "+COPS:"    /tmp/_probe.txt 2>/dev/null && ok="$ok COPS"
       grep -q "+CRSM:"    /tmp/_probe.txt 2>/dev/null && ok="$ok CRSM"
       grep -q "+CSIM:"    /tmp/_probe.txt 2>/dev/null && ok="$ok CSIM(eSIM-capable!)"
       echo "  $S answers:${ok:- nothing}"
       rm -f /tmp/_probe.txt
     done' 2>/dev/null

say "Resources"
run 'awk "/MemTotal|MemFree/{printf \"  %-10s %s KB\n\", \$1, \$2}" /proc/meminfo
     df 2>/dev/null | awk "/root|mtdblock/{printf \"  %-16s %5s used, %8s KB free  %s\n\", \$1, \$5, \$4, \$6}"
     echo "  sd slot : $([ -d /sys/class/mmc_host/mmc0 ] && echo present || echo none)"' 2>/dev/null

say "Services the mod uses"
# busybox pgrep does not always support -c, so count from ps instead
run 'echo "  ubus qcmap : $(ubus list 2>/dev/null | grep -c qcmap)"
     echo "  lighttpd   : $(ps 2>/dev/null | grep -c "[l]ighttpd") process(es)"
     echo "  adbd       : $(ps 2>/dev/null | grep -c "[a]dbd")"
     echo "  signal_poll: $(ps 2>/dev/null | grep -c "[s]ignal_poll") (this mod, if already installed)"' 2>/dev/null

echo
echo "Done. Nothing was modified."
