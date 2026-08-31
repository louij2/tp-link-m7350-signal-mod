#!/bin/sh
# Dashboard tile order, stored on the device so the layout follows the router
# rather than whichever browser last touched it.
#
# GET  is open: the order is just a list of card names, nothing sensitive, and
#      the page needs it before the user has authenticated anything.
# POST requires the control password, on the same fail-closed terms as
#      control.sh, because it writes to the persistent filesystem. The body is
#      validated against the known tile names, so nothing else can be written.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
FILE=/etc/signalmod_tiles
PWFILE=/etc/signalmod.pw
J='Content-Type: application/json\r\nCache-Control: no-store\r\n'

if [ "$REQUEST_METHOD" = "POST" ]; then
  if [ ! -s "$PWFILE" ]; then
    printf "Status: 503 Service Unavailable\r\n${J}\r\n{\"error\":\"no control password set\"}"; exit 0
  fi
  supplied="$HTTP_X_AUTH"
  [ -z "$supplied" ] && supplied=$(printf '%s' "$QUERY_STRING" | sed -n 's/.*[?&]auth=\([^&]*\).*/\1/p')
  if [ "$supplied" != "$(cat "$PWFILE" 2>/dev/null)" ]; then
    printf "Status: 403 Forbidden\r\n${J}\r\n{\"error\":\"auth\"}"; exit 0
  fi
  len="${CONTENT_LENGTH:-0}"
  case "$len" in ''|*[!0-9]*) len=0 ;; esac
  if [ "$len" -lt 1 ] || [ "$len" -gt 400 ]; then
    printf "${J}\r\n{\"error\":\"bad length\"}"; exit 0
  fi
  BODY=$(dd bs=1 count="$len" 2>/dev/null | tr -d '\r\n ')
  # Only a comma-separated list of known tile names is accepted.
  # name[:width] where width is 1, 2 or full
  T='(conn|wifi|stats|system|ctl|sec|about|hw)(:[1-9])?(:[0-9]{2,4})?'
  if ! echo "$BODY" | grep -qE "^${T}(,${T})*$"; then
    printf "${J}\r\n{\"error\":\"rejected: unknown tile name\"}"; exit 0
  fi
  printf '%s' "$BODY" > "$FILE.new" && mv "$FILE.new" "$FILE" \
    && printf "${J}\r\n{\"ok\":1}" || printf "${J}\r\n{\"error\":\"write failed\"}"
  exit 0
fi

printf "${J}\r\n"
printf '{"order":"%s"}' "$(cat "$FILE" 2>/dev/null | tr -d '\r\n')"
