#!/bin/sh
# Browse and download the long-term signal history kept on the SD card.
#
#   ?action=list          JSON list of available days
#   ?action=get&day=YYYY-MM-DD   that day's CSV
#
# AUTH: required. Signal history is a log of which cells this device camped on
# and when, which is a movement record. It is not served to the LAN unauthenticated.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
DIR=/media/card/signalmod/history
PWFILE=/etc/signalmod.pw

fail(){ printf "Status: $1\r\nContent-Type: application/json\r\nCache-Control: no-store\r\n\r\n{\"error\":\"$2\"}"; exit 0; }

[ -s "$PWFILE" ] || fail "503 Service Unavailable" "no control password set"
supplied="$HTTP_X_AUTH"
[ -z "$supplied" ] && supplied=$(printf '%s' "$QUERY_STRING" | sed -n 's/.*[?&]auth=\([^&]*\).*/\1/p')
[ "$supplied" = "$(cat "$PWFILE" 2>/dev/null)" ] || fail "403 Forbidden" "auth"

A=$(printf '%s' "$QUERY_STRING" | sed -n 's/.*action=\([a-zA-Z]*\).*/\1/p')
case "$A" in
  list)
    printf 'Content-Type: application/json\r\nCache-Control: no-store\r\n\r\n['
    first=1
    for f in "$DIR"/*.csv; do
      [ -f "$f" ] || continue
      d=$(basename "$f" .csv)
      n=$(( $(wc -l < "$f" 2>/dev/null) - 1 ))
      [ "$n" -lt 0 ] && n=0
      [ "$first" = 1 ] || printf ','
      first=0
      printf '{"day":"%s","samples":%d,"bytes":%d}' "$d" "$n" "$(wc -c < "$f" 2>/dev/null)"
    done
    printf ']'
    ;;
  get)
    DAY=$(printf '%s' "$QUERY_STRING" | sed -n 's/.*[?&]day=\([0-9-]*\).*/\1/p')
    case "$DAY" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) : ;;
      *) fail "400 Bad Request" "bad day" ;;
    esac
    F="$DIR/$DAY.csv"
    [ -f "$F" ] || fail "404 Not Found" "no history for that day"
    printf 'Content-Type: text/csv\r\nContent-Disposition: attachment; filename="m7350-%s.csv"\r\nCache-Control: no-store\r\n\r\n' "$DAY"
    cat "$F"
    ;;
  *) fail "400 Bad Request" "unknown action" ;;
esac
