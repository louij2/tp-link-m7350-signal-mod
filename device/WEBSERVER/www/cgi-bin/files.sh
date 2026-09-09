#!/bin/sh
# M7350 mod: read-only file browser for the web UI.
#
# AUTH: FAILS CLOSED, like keys.sh. This walks the router's whole filesystem, so
# there is no unauthenticated mode. Without /etc/signalmod.pw it refuses outright
# rather than falling back to open.
#
#   ?op=list&path=/media/card    directory listing as JSON
#   ?op=get&path=/media/card/x   file contents, as a download
#   ?op=roots                    the places worth starting from, and whether
#                                each currently exists
#
# READ ONLY, deliberately. No rename, no delete, no upload. A browser tab is a
# bad place to be one mis-click from removing a file on a device whose rootfs is
# 87% full and whose recovery path is a USB cable.
#
# NEVER reads an AT channel. A CGI that opens /dev/smd* blocks and takes lighttpd
# down with it, so the SIM side of the explorer is served from the daemon's
# cache by simfiles.sh instead.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

PWFILE=/etc/signalmod.pw
J='Content-Type: application/json\r\nCache-Control: no-store\r\n'
MAXBYTES=8388608          # 8 MB: enough for any history CSV, not a whole card

fail(){ printf "Status: $1\r\n${J}\r\n{\"error\":\"$2\"}"; exit 0; }

# --- auth gate, before anything touches the filesystem ----------------------
[ -s "$PWFILE" ] || fail "503 Service Unavailable" "no password set: create /etc/signalmod.pw first"
supplied="$HTTP_X_AUTH"
[ -z "$supplied" ] && supplied=$(printf '%s' "$QUERY_STRING" | sed -n 's/.*[?&]auth=\([^&]*\).*/\1/p')
[ "$supplied" = "$(cat "$PWFILE" 2>/dev/null)" ] || fail "403 Forbidden" "auth"

# --- query parsing ----------------------------------------------------------
urldec(){ printf '%b' "$(printf '%s' "$1" | sed 's/+/ /g; s/%\(..\)/\\x\1/g')"; }
qs_get(){ printf '%s' "$QUERY_STRING" | tr '&' '\n' | sed -n "s/^$1=//p" | head -1; }

OP=$(qs_get op)
RAWPATH=$(qs_get path)
P=$(urldec "$RAWPATH")
[ -n "$P" ] || P=/

# Reject NUL/newline injection and anything with a .. component. We allow the
# whole tree, so .. is not an escape as such, but refusing it keeps the path
# that gets displayed identical to the path that gets opened.
case "$P" in
  *..*) fail "400 Bad Request" "path may not contain .." ;;
  /*)   : ;;
  *)    fail "400 Bad Request" "path must be absolute" ;;
esac
printf '%s' "$P" | grep -q '[[:cntrl:]]' && fail "400 Bad Request" "bad path"

# --- secrets are listed but never served ------------------------------------
# The whole tree is browsable, which means the password file, the SSH host keys
# and authorized_keys are all reachable by path. Someone who already has the
# password can see they exist; handing back their CONTENTS would turn one leaked
# password into permanent root, so downloads of these are refused by name.
is_secret(){
  case "$1" in
    /etc/signalmod.pw|/etc/shadow|/etc/dropbear/*|*/.ssh/*|*authorized_keys*|*_host_key*)
      return 0 ;;
  esac
  return 1
}

esc(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

case "$OP" in
  roots)
    printf "${J}\r\n["
    first=1
    # label, path. /media/card first because it is the one people want.
    for r in "SD card:/media/card" "Web root:/WEBSERVER/www" "Config:/etc" "Logs:/var/log" "Tmp:/tmp" "Root:/"; do
      lbl=${r%%:*}; pth=${r#*:}
      [ "$first" = 1 ] || printf ','
      first=0
      ex=false; [ -d "$pth" ] && ex=true
      printf '{"label":"%s","path":"%s","exists":%s}' "$(esc "$lbl")" "$(esc "$pth")" "$ex"
    done
    printf ']'
    ;;

  list)
    [ -d "$P" ] || fail "404 Not Found" "not a directory"
    printf "${J}\r\n{\"path\":\"%s\",\"entries\":[" "$(esc "$P")"
    first=1
    # -A so dotfiles show; the interesting things on this device are dotfiles.
    # Read line by line rather than iterating $(ls): word splitting breaks any
    # name containing a space, which a card full of other people's files will
    # certainly have. The loop runs in a subshell, which is fine here because
    # "first" is only ever read inside it.
    ls -A "$P" 2>/dev/null | while IFS= read -r name; do
      full="$P/$name"; full=$(printf '%s' "$full" | sed 's#//*#/#g')
      if [ -d "$full" ]; then
        typ=dir; sz=0
      else
        typ=file
        sz=$(wc -c < "$full" 2>/dev/null | tr -dc '0-9')
        [ -n "$sz" ] || sz=0
      fi
      sec=false; is_secret "$full" && sec=true
      [ "$first" = 1 ] || printf ','
      first=0
      printf '{"name":"%s","type":"%s","size":%s,"secret":%s}' \
        "$(esc "$name")" "$typ" "$sz" "$sec"
    done
    printf ']}'
    ;;

  get)
    [ -f "$P" ] || fail "404 Not Found" "not a regular file"
    is_secret "$P" && fail "403 Forbidden" "this file holds credentials and is not served"
    SZ=$(wc -c < "$P" 2>/dev/null | tr -dc '0-9'); [ -n "$SZ" ] || SZ=0
    [ "$SZ" -gt "$MAXBYTES" ] && fail "413 Payload Too Large" "file is larger than 8 MB"
    BASE=$(basename "$P")
    printf 'Content-Type: application/octet-stream\r\n'
    printf 'Content-Disposition: attachment; filename="%s"\r\n' "$BASE"
    printf 'Cache-Control: no-store\r\n\r\n'
    cat "$P"
    ;;

  *)
    fail "400 Bad Request" "op must be roots, list or get"
    ;;
esac
