#!/bin/sh
# M7350 mod: SSH authorized_keys management for the web UI.
#
# AUTH: FAILS CLOSED. Unlike control.sh, this endpoint refuses to do anything at
# all unless /etc/signalmod.pw exists and the caller presents it. Adding a key
# here grants permanent root SSH, so there is no backwards-compatible
# unauthenticated mode -- that would be handing out root to the whole LAN.
#
#   ?action=list                 list installed keys (never returns key material)
#   ?action=add                  add a key; the key is read from the POST BODY,
#                                not the query string, so it stays out of logs
#   ?action=revoke&i=N           remove key number N as shown by list
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

AK=/home/root/.ssh/authorized_keys
PWFILE=/etc/signalmod.pw
J='Content-Type: application/json\r\nCache-Control: no-store\r\n'

fail(){ printf "Status: $1\r\n${J}\r\n{\"error\":\"$2\"}"; exit 0; }

# --- auth gate (before anything else) --------------------------------------
[ -s "$PWFILE" ] || fail "503 Service Unavailable" "no password set: create /etc/signalmod.pw first"
supplied="$HTTP_X_AUTH"
[ -z "$supplied" ] && supplied=$(printf '%s' "$QUERY_STRING" | sed -n 's/.*[?&]auth=\([^&]*\).*/\1/p')
[ "$supplied" = "$(cat "$PWFILE" 2>/dev/null)" ] || fail "403 Forbidden" "auth"

A=$(printf '%s' "$QUERY_STRING" | sed -n 's/.*action=\([a-zA-Z_]*\).*/\1/p')
mkdir -p /home/root/.ssh 2>/dev/null; chmod 700 /home/root/.ssh 2>/dev/null
[ -f "$AK" ] || { : > "$AK"; chmod 600 "$AK"; }

# MD5 fingerprint of the decoded key blob, colon-separated, as ssh-keygen shows.
fp(){ printf '%s' "$1" | base64 -d 2>/dev/null | md5sum 2>/dev/null \
        | cut -d' ' -f1 | sed 's/\(..\)/\1:/g; s/:$//'; }

list_json(){
  printf "${J}\r\n["
  i=0; first=1
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue ;; esac
    i=$((i+1))
    t=$(printf '%s' "$line" | awk '{print $1}')
    b=$(printf '%s' "$line" | awk '{print $2}')
    c=$(printf '%s' "$line" | awk '{$1="";$2="";print}' | sed 's/^ *//; s/"/\\"/g')
    [ "$first" = 1 ] || printf ','
    first=0
    printf '{"i":%d,"type":"%s","comment":"%s","fp":"%s"}' "$i" "$t" "$c" "$(fp "$b")"
  done < "$AK"
  printf ']'
}

case "$A" in
  list) list_json ;;

  add)
    # Body only. A key in the query string would land in the web server log.
    len="${CONTENT_LENGTH:-0}"
    case "$len" in ''|*[!0-9]*) len=0 ;; esac
    [ "$len" -gt 0 ] && [ "$len" -le 8192 ] || fail "400 Bad Request" "no key in request body"
    KEY=$(dd bs=1 count="$len" 2>/dev/null | tr -d '\r\n')

    # Validate hard. Anything that is not exactly "<type> <base64> [comment]" is
    # rejected: authorized_keys options (command=, from=, permitopen=) can turn a
    # key line into arbitrary root command execution, so they are never accepted.
    echo "$KEY" | grep -qE '^(ssh-rsa|ssh-ed25519|ssh-dss|ecdsa-sha2-nistp(256|384|521)) [A-Za-z0-9+/]+=*( [^\n]*)?$' \
      || fail "400 Bad Request" "not a plain public key (options and multi-line input are refused)"
    B=$(printf '%s' "$KEY" | awk '{print $2}')
    printf '%s' "$B" | base64 -d >/dev/null 2>&1 || fail "400 Bad Request" "key body is not valid base64"
    grep -qF "$B" "$AK" 2>/dev/null && fail "409 Conflict" "key already installed"

    cp "$AK" "$AK.bak" 2>/dev/null
    { cat "$AK"; echo "$KEY"; } > "$AK.new" && mv "$AK.new" "$AK" && chmod 600 "$AK" \
      || fail "500 Internal Server Error" "write failed"
    printf "${J}\r\n{\"ok\":\"1\",\"fp\":\"$(fp "$B")\"}"
    ;;

  revoke)
    N=$(printf '%s' "$QUERY_STRING" | sed -n 's/.*[?&]i=\([0-9]*\).*/\1/p')
    [ -n "$N" ] || fail "400 Bad Request" "missing key number"
    total=$(grep -cvE '^[[:space:]]*(#|$)' "$AK" 2>/dev/null || echo 0)
    [ "$total" -gt 1 ] || fail "409 Conflict" "refusing to remove the last key: that would lock you out of SSH"
    cp "$AK" "$AK.bak" 2>/dev/null
    awk -v n="$N" '/^[[:space:]]*(#|$)/{print;next} {c++; if(c!=n) print}' "$AK" > "$AK.new" \
      && mv "$AK.new" "$AK" && chmod 600 "$AK" || fail "500 Internal Server Error" "write failed"
    printf "${J}\r\n{\"ok\":\"1\"}"
    ;;

  *) fail "400 Bad Request" "unknown action" ;;
esac
