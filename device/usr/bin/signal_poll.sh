#!/bin/sh
# LTE signal-stats polling daemon for the TP-Link M7350 (Qualcomm MDM9625).
#
# Polls AT commands on a modem AT channel and caches the parsed result as JSON
# in /tmp/signal.json, which /cgi-bin/signal_stats.sh serves to the web UI.
# Launched by /etc/init.d/signal_poll.
#
# Design notes / traps (see the project README):
#  - Never `cat` an smd channel from a CGI context: it blocks and kills
#    lighttpd. This daemon owns the channel; the CGI only reads the cache.
#  - Detach stdio so backgrounding (init / adb) does not hang on a pipe.
#  - Keep the AT set small and standard, and poll every 5s. Aggressive or
#    exotic AT traffic can wedge an smd channel (EIO on open). If the current
#    channel stops responding, we auto-fail-over to the next candidate, so a
#    single wedged channel no longer takes the stats down.

exec </dev/null >/dev/null 2>&1

CANDIDATES="/dev/smd7 /dev/smd8 /dev/smd11"
SMD=""

# Return 0 if $1 answers an AT$QCRSRP probe with a QCRSRP line.
probe_channel() {
  ch=$1
  [ -e "$ch" ] || return 1
  rm -f /tmp/at_probe.txt
  ( cat "$ch" > /tmp/at_probe.txt 2>/dev/null ) &
  pp=$!
  sleep 0.2
  printf 'AT$QCRSRP?\r\n' > "$ch" 2>/dev/null
  sleep 0.8
  kill $pp 2>/dev/null; wait $pp 2>/dev/null
  grep -q 'QCRSRP:' /tmp/at_probe.txt 2>/dev/null
}

# Pick the first candidate that answers; sets $SMD (empty if none).
select_channel() {
  for c in $CANDIDATES; do
    [ -n "$BAD" ] && [ "$c" = "$BAD" ] && continue
    if probe_channel "$c"; then
      SMD="$c"
      chmod 666 "$c" 2>/dev/null
      return 0
    fi
  done
  # Nothing else answered. Drop the exclusion and try everything, so a channel
  # that has since recovered is not locked out for the life of the daemon.
  BAD=""
  for c in $CANDIDATES; do
    if probe_channel "$c"; then
      SMD="$c"
      chmod 666 "$c" 2>/dev/null
      return 0
    fi
  done
  SMD=""
  return 1
}

# Map an LTE DL EARFCN to its band number (common bands only).
earfcn_to_band() {
  e=$1
  [ -z "$e" ] && { echo ""; return; }
  if   [ "$e" -le 599 ];   then echo 1
  elif [ "$e" -le 1199 ];  then echo 2
  elif [ "$e" -le 1949 ];  then echo 3
  elif [ "$e" -le 2399 ];  then echo 4
  elif [ "$e" -le 2649 ];  then echo 5
  elif [ "$e" -le 3449 ];  then echo 7
  elif [ "$e" -le 3799 ];  then echo 8
  elif [ "$e" -ge 6150 ] && [ "$e" -le 6449 ]; then echo 20
  elif [ "$e" -ge 9210 ] && [ "$e" -le 9659 ]; then echo 28
  elif [ "$e" -ge 37750 ] && [ "$e" -le 38249 ]; then echo 38
  elif [ "$e" -ge 38650 ] && [ "$e" -le 39649 ]; then echo 40
  elif [ "$e" -ge 39650 ] && [ "$e" -le 41589 ]; then echo 41
  else echo ""
  fi
}

# WAN interface carrying the uplink (the default route's device).
wan_iface() {
  ip route 2>/dev/null | awk '/^default/{print $5; exit}'
}

# Echo "rx_bytes tx_bytes" for the given interface from /proc/net/dev.
iface_bytes() {
  line=$(grep "$1:" /proc/net/dev 2>/dev/null | head -1)
  [ -z "$line" ] && { echo "0 0"; return; }
  vals=${line#*:}
  set -- $vals
  echo "$1 ${9}"
}


# ---------------------------------------------------------------------------
# Serving-cell info (TAC / Cell ID) and the RSRP history ring.
#
# These run on a SLOW cadence (once a minute), not every poll: the modem's AT
# channels are easy to wedge with heavy probing, and none of this changes fast.
#
# Note the channel split on this hardware: +CEREG answers on smd7, while
# $QCRSRP? answers on smd8/smd11 and ERRORs on smd7. So the cell poll picks its
# own channel independently of the signal channel rather than assuming one
# channel does everything.
# ---------------------------------------------------------------------------
CELL_CH=""
CELL_FAILS=0
HIST=/tmp/signal_hist
HIST_MAX=240          # 240 samples at 60s = 4 hours of sparkline

cell_probe() { # cell_probe <dev> -> 0 if it answers +CEREG
  [ -c "$1" ] || return 1
  rm -f /tmp/cereg.txt
  ( cat "$1" > /tmp/cereg.txt 2>/dev/null ) & cp=$!
  sleep 0.2
  printf 'AT+CEREG=2\r\n' > "$1" 2>/dev/null
  sleep 0.4
  printf 'AT+CEREG?\r\n'  > "$1" 2>/dev/null
  sleep 0.8
  kill $cp 2>/dev/null; wait $cp 2>/dev/null
  grep -q '+CEREG:' /tmp/cereg.txt 2>/dev/null
}

poll_cell() {
  # Give up permanently after repeated failures rather than probing forever.
  [ "$CELL_FAILS" -ge 5 ] && return 0
  # Probe exactly ONCE per cycle and parse that same response. An earlier version
  # probed to pick the channel and then probed again to read it, and the second
  # back-to-back read on the same channel is unreliable -- it discarded a
  # perfectly good first response.
  got=1
  if [ -n "$CELL_CH" ] && cell_probe "$CELL_CH"; then
    got=0
  else
    CELL_CH=""
    for c in $CANDIDATES; do
      if cell_probe "$c"; then CELL_CH="$c"; got=0; break; fi
    done
  fi
  [ "$got" = 0 ] || { CELL_FAILS=$((CELL_FAILS + 1)); return 0; }
  CELL_FAILS=0
  # 3GPP documents +CEREG: <n>,<stat>[,"<tac>","<ci>"[,<AcT>]], but this modem
  # emits an extra quoted field:
  #     +CEREG: 2,1,"467","A","1A7901",7
  # Taking fixed column 4 as the cell ID therefore yielded "A". Parse by quoted
  # token instead: the TAC is always the first and the cell ID the last, which
  # is correct for both the two-field and three-field variants.
  line=$(tr -d '\r' < /tmp/cereg.txt | grep '+CEREG:' | tail -1)
  quoted=$(printf '%s' "$line" | tr ',' '\n' | grep '"' | tr -d '"' | grep -v '^$')
  TAC=$(printf '%s' "$quoted" | head -1)
  CELLID=$(printf '%s' "$quoted" | tail -1)
  case "$TAC" in    *[!0-9A-Fa-f]*|'') TAC="" ;; esac
  case "$CELLID" in *[!0-9A-Fa-f]*|'') CELLID="" ;; esac
}

hist_push() { # keep a small rolling RSRP ring in tmpfs for the UI sparkline
  [ -n "$1" ] || return 0
  printf '%s\n' "$1" >> "$HIST" 2>/dev/null
  n=$(wc -l < "$HIST" 2>/dev/null || echo 0)
  [ "$n" -gt "$HIST_MAX" ] && { tail -n "$HIST_MAX" "$HIST" > "$HIST.t" 2>/dev/null && mv "$HIST.t" "$HIST"; }
  return 0
}

PING_TARGET=1.1.1.1
BAD=""
TAC=""; CELLID=""; slow=0
select_channel
empty_streak=0
prev_rx=""; prev_tx=""; prev_t=""

while true; do
  if [ -z "$SMD" ]; then
    select_channel
    [ -z "$SMD" ] && { sleep 5; continue; }
  fi

  rm -f /tmp/at_raw.txt
  ( cat "$SMD" > /tmp/at_raw.txt 2>/dev/null ) &
  CATPID=$!
  sleep 0.1
  printf 'AT$QCRSRP?\r\n'   > "$SMD" 2>/dev/null
  printf 'AT$QCRSRQ?\r\n'   > "$SMD" 2>/dev/null
  printf 'AT+CSQ\r\n'       > "$SMD" 2>/dev/null
  printf 'AT$QCSYSMODE\r\n' > "$SMD" 2>/dev/null
  sleep 1.6
  kill $CATPID 2>/dev/null
  wait $CATPID 2>/dev/null
  RESP=$(cat /tmp/at_raw.txt 2>/dev/null)

  RSRP=$(printf '%s' "$RESP"   | grep -o 'QCRSRP: [0-9]*,[0-9]*,"[^"]*"' | head -1 | grep -o '"[^"]*"' | tr -d '"')
  RSRQ=$(printf '%s' "$RESP"   | grep -o 'QCRSRQ: [0-9]*,[0-9]*,"[^"]*"' | head -1 | grep -o '"[^"]*"' | tr -d '"')
  EARFCN=$(printf '%s' "$RESP" | grep -o 'QCRSRP: [0-9]*,[0-9]*' | head -1 | cut -d, -f2)
  CSQ=$(printf '%s' "$RESP"    | grep -o '+CSQ: [0-9]*' | head -1 | sed 's/+CSQ: //')
  MODE=$(printf '%s' "$RESP"   | grep -oE 'LTE|WCDMA|GSM' | head -1)
  BAND=$(earfcn_to_band "$EARFCN")

  if [ -n "$CSQ" ] && [ "$CSQ" != "99" ]; then
    RSSI=$(expr -113 + 2 \* $CSQ 2>/dev/null)
  else
    RSSI=''
  fi

  # A channel can answer AT and $QCSYSMODE perfectly while still rejecting
  # $QCRSRP? -- smd7 on this device does exactly that. Keying the health check
  # on "no response at all" therefore never fired, and the daemon sat happily on
  # a channel that could not produce the one number the mod exists to show.
  # Judge the channel on the value we actually need, not on whether it is alive.
  if [ -z "$RSRP" ]; then
    empty_streak=$((empty_streak + 1))
    if [ "$empty_streak" -ge 3 ]; then
      BAD="$SMD"          # skip this one on the way back round
      SMD=""
      empty_streak=0
    fi
  else
    empty_streak=0
  fi

  # ---- Non-AT telemetry (safe; never touches the modem channel) ----------
  WAN=$(wan_iface); [ -z "$WAN" ] && WAN=rmnet0
  set -- $(iface_bytes "$WAN"); RX=$1; TX=$2
  NOW=$(cut -d' ' -f1 /proc/uptime 2>/dev/null)
  UPTIME=$(cut -d. -f1 /proc/uptime 2>/dev/null)

  DL_KBPS=""; UL_KBPS=""
  if [ -n "$prev_t" ]; then
    DL_KBPS=$(awk -v a="$RX" -v b="$prev_rx" -v t0="$prev_t" -v t1="$NOW" 'BEGIN{dt=t1-t0; d=a-b; if(dt>0 && d>=0) printf "%.0f", d*8/1000/dt; else print ""}')
    UL_KBPS=$(awk -v a="$TX" -v b="$prev_tx" -v t0="$prev_t" -v t1="$NOW" 'BEGIN{dt=t1-t0; d=a-b; if(dt>0 && d>=0) printf "%.0f", d*8/1000/dt; else print ""}')
  fi
  prev_rx=$RX; prev_tx=$TX; prev_t=$NOW

  # Uplink latency (empty when the link is down).
  LAT=$(ping -c1 -W1 "$PING_TARGET" 2>/dev/null | grep -oE 'time=[0-9.]+' | head -1 | cut -d= -f2)

  # Roughly once a minute: serving-cell read and one sparkline sample.
  # An iteration takes about 7s, not the 5s of the sleep alone.
  slow=$((slow + 1))
  if [ "$slow" -ge 8 ]; then
    slow=0
    poll_cell
    hist_push "$RSRP"
  fi

  printf '{"rsrp":"%s","rsrq":"%s","rssi":"%s","earfcn":"%s","band":"%s","mode":"%s","dl_kbps":"%s","ul_kbps":"%s","latency_ms":"%s","uptime":"%s","rx_bytes":"%s","tx_bytes":"%s","tac":"%s","cellid":"%s"}' \
    "$RSRP" "$RSRQ" "$RSSI" "$EARFCN" "$BAND" "$MODE" "$DL_KBPS" "$UL_KBPS" "$LAT" "$UPTIME" "$RX" "$TX" "$TAC" "$CELLID" > /tmp/signal.json
  sleep 5
done
