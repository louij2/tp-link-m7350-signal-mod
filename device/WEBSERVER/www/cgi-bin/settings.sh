#!/bin/sh
# M7350 mod: the settings behind the Status page's toggles.
#
# AUTH: FAILS CLOSED on writes. Reads are gated too, because the FTP and Telnet
# ports tell an attacker exactly where to knock.
#
#   ?op=get                       every setting, with its default and bounds
#   ?op=set  (POST body k=v&k=v)  change settings; unknown keys are refused
#
# Settings live in /etc/signalmod.conf as plain key=value on the persistent
# rootfs, so they survive a reboot. control.sh sources it, so a changed port
# takes effect the next time the service is started rather than needing a
# restart of anything else.
#
# EVERY VALUE IS RANGE-CHECKED HERE, not in the browser. The UI is the
# convenient path, not the only one, and a port of "0; rm -rf /" reaching a
# shell would be the whole game.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

PWFILE=/etc/signalmod.pw
CONF=/etc/signalmod.conf
J='Content-Type: application/json\r\nCache-Control: no-store\r\n'

fail(){ printf "Status: $1\r\n${J}\r\n{\"error\":\"$2\"}"; exit 0; }

[ -s "$PWFILE" ] || fail "503 Service Unavailable" "no password set: create /etc/signalmod.pw first"
supplied="$HTTP_X_AUTH"
[ -z "$supplied" ] && supplied=$(printf '%s' "$QUERY_STRING" | sed -n 's/.*[?&]auth=\([^&]*\).*/\1/p')
[ "$supplied" = "$(cat "$PWFILE" 2>/dev/null)" ] || fail "403 Forbidden" "auth"

# key:default:min:max  (min/max empty means "not a number, see validate())
SPEC="telnet_port:23:1:65535
ttl_value:65:1:255
sdlog_max_mb:20:1:2048
sdlog_keep_days:14:1:365
poll_secs:5:2:60
saver_poll_secs:30:5:600"

get_one(){ sed -n "s/^$1=//p" "$CONF" 2>/dev/null | tail -1; }
default_of(){ printf '%s\n' "$SPEC" | sed -n "s/^$1:\([^:]*\):.*/\1/p"; }
min_of(){ printf '%s\n' "$SPEC" | sed -n "s/^$1:[^:]*:\([^:]*\):.*/\1/p"; }
max_of(){ printf '%s\n' "$SPEC" | sed -n "s/^$1:[^:]*:[^:]*:\(.*\)/\1/p"; }
known(){ printf '%s\n' "$SPEC" | grep -q "^$1:"; }

value_of(){ v=$(get_one "$1"); [ -n "$v" ] || v=$(default_of "$1"); printf '%s' "$v"; }

case "$(printf '%s' "$QUERY_STRING" | sed -n 's/.*op=\([a-z]*\).*/\1/p')" in
  get)
    printf "${J}\r\n{"
    first=1
    printf '%s\n' "$SPEC" | while IFS=: read -r k d mn mx; do
      [ -n "$k" ] || continue
      [ "$first" = 1 ] || printf ','
      first=0
      printf '"%s":{"value":"%s","default":"%s","min":%s,"max":%s}' \
        "$k" "$(value_of "$k")" "$d" "$mn" "$mx"
    done
    printf '}'
    ;;

  set)
    # Body only. A port in the query string would be written to the web
    # server's log, and so would anything else pushed through this endpoint.
    LEN=${CONTENT_LENGTH:-0}
    case "$LEN" in ''|*[!0-9]*) LEN=0 ;; esac
    [ "$LEN" -gt 4096 ] && fail "413 Payload Too Large" "body too large"
    BODY=$(dd bs=1 count="$LEN" 2>/dev/null)
    [ -n "$BODY" ] || fail "400 Bad Request" "empty body"

    TMP=/tmp/.sigmod_conf.$$
    cp "$CONF" "$TMP" 2>/dev/null || : > "$TMP"

    CHANGED=""
    for pair in $(printf '%s' "$BODY" | tr '&' ' '); do
      k=${pair%%=*}; v=${pair#*=}
      known "$k" || { rm -f "$TMP"; fail "400 Bad Request" "unknown setting '$k'"; }
      # Digits only. Every setting here is numeric, so this is the whole
      # validation surface and it stays that way deliberately.
      case "$v" in ''|*[!0-9]*) rm -f "$TMP"; fail "400 Bad Request" "'$k' must be a number" ;; esac
      mn=$(min_of "$k"); mx=$(max_of "$k")
      if [ "$v" -lt "$mn" ] || [ "$v" -gt "$mx" ]; then
        rm -f "$TMP"; fail "400 Bad Request" "'$k' must be between $mn and $mx"
      fi
      sed -i "/^$k=/d" "$TMP" 2>/dev/null
      printf '%s=%s\n' "$k" "$v" >> "$TMP"
      CHANGED="$CHANGED $k"
    done

    # Swap in atomically, so a reader never sees a half-written config.
    mv "$TMP" "$CONF" 2>/dev/null || { rm -f "$TMP"; fail "500 Internal Server Error" "could not write $CONF"; }
    chmod 600 "$CONF" 2>/dev/null
    sync
    printf "${J}\r\n{\"ok\":true,\"changed\":\"%s\"}" "$(printf '%s' "$CHANGED" | sed 's/^ //')"
    ;;

  *) fail "400 Bad Request" "op must be get or set" ;;
esac
