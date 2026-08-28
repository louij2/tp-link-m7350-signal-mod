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

select_channel
empty_streak=0

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

  # If reads keep coming back empty, the channel may have wedged -- re-select.
  if [ -z "$RSRP" ] && [ -z "$MODE" ]; then
    empty_streak=$((empty_streak + 1))
    if [ "$empty_streak" -ge 3 ]; then
      SMD=""
      empty_streak=0
    fi
  else
    empty_streak=0
  fi

  printf '{"rsrp":"%s","rsrq":"%s","rssi":"%s","earfcn":"%s","band":"%s","mode":"%s"}' \
    "$RSRP" "$RSRQ" "$RSSI" "$EARFCN" "$BAND" "$MODE" > /tmp/signal.json
  sleep 5
done
