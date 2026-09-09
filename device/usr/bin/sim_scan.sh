#!/bin/sh
# M7350 mod: read the standard elementary files off the SIM and cache them as
# JSON for the web UI's SIM explorer.
#
#   sim_scan.sh /dev/smd7 [outfile]     default outfile /tmp/sim_files.json
#
# RUN THIS FROM THE DAEMON, NEVER FROM A CGI. It opens an AT channel, and a CGI
# that opens /dev/smd* blocks and takes lighttpd down with it. signal_poll.sh
# already owns channel selection, so it passes the channel it settled on.
#
# WHAT THIS CANNOT DO, and why the UI says so rather than pretending:
# listing or switching eUICC profiles is not reachable from here. That needs
# APDUs to the ISD-R applet (SGP.22 ES10c), which means AT+CSIM / AT+CCHO +
# AT+CGLA. This firmware's AT interface errors on all three, so there is no
# path to the profile list, the EID, or a profile enable/disable. AT+CRSM works,
# which is why the standard EFs below are readable: CRSM is a restricted command
# the modem executes on your behalf, not a channel you can send arbitrary APDUs
# down. The capability probe result is recorded in the output so the UI can
# state the reason instead of guessing.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

DEV="$1"
OUT="${2:-/tmp/sim_files.json}"
[ -c "$DEV" ] || { echo "usage: sim_scan.sh /dev/smdN [outfile]" >&2; exit 1; }

TMP=/tmp/.simscan.$$
cleanup(){ rm -f "$TMP"; }
trap cleanup EXIT INT TERM

# Same shape as signal_poll.sh's sim_read: background the reader, write, reap.
# That pattern is safe inside the daemon; it is the adb-shell foreground case
# that hangs on it.
at_raw() { # at_raw <cmd> -> whole reply
  : > "$TMP"
  ( cat "$DEV" > "$TMP" 2>/dev/null ) & sp=$!
  sleep 0.2
  printf '%s\r\n' "$1" > "$DEV" 2>/dev/null
  sleep 1.2
  kill $sp 2>/dev/null; wait $sp 2>/dev/null
  tr -d '\r' < "$TMP"
}

crsm() { # crsm <fileid-decimal> <len> -> hex payload, empty if the SIM refused
  at_raw "AT+CRSM=176,$1,0,0,$2" | sed -n 's/.*+CRSM: 144,0,"\([0-9A-Fa-f]*\)".*/\1/p' | head -1
}

# nibble-swapped BCD, F is padding (ICCID, IMSI, PLMN ids)
bcd_swap(){ printf '%s' "$1" | sed 's/\(.\)\(.\)/\2\1/g' | tr -d 'Ff'; }
# hex -> ascii, stopping at FF padding
hex_txt(){
  h=$(printf '%s' "$1" | sed 's/[Ff][Ff].*//')
  [ -n "$h" ] || return 0
  printf "$(printf '%s' "$h" | sed 's/\(..\)/\\x\1/g')" 2>/dev/null
}
esc(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# --- eUICC capability probe -------------------------------------------------
# Ask whether the APDU commands exist at all. A test command (=?) is harmless:
# it reports supported parameter ranges and changes nothing on the card.
APDU="no"
for c in "AT+CSIM=?" "AT+CGLA=?" "AT+CCHO=?"; do
  case "$(at_raw "$c")" in
    *OK*) APDU="yes"; break ;;
  esac
done

# --- the files ---------------------------------------------------------------
# name, hex id (for display), decimal id (for CRSM), length, kind
FILES="
ICCID:2FE2:12258:10:bcd
IMSI:6F07:28423:9:imsi
SPN:6F46:28486:17:spn
AD:6FAD:28589:4:hex
FPLMN:6F7B:28539:12:plmn
HPPLMN:6F31:28465:1:hex
UST:6F38:28472:12:hex
PLMNwAcT:6F60:28512:32:plmn
OPLMNwAcT:6F61:28513:32:plmn
HPLMNwAcT:6F62:28514:32:plmn
GID1:6F3E:28478:8:hex
GID2:6F3F:28479:8:hex
"

{
  printf '{"apdu_access":"%s","channel":"%s","scanned":"%s","files":[' \
    "$APDU" "$(esc "$DEV")" "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
  first=1
  echo "$FILES" | while IFS=: read -r name hexid decid len kind; do
    [ -n "$name" ] || continue
    raw=$(crsm "$decid" "$len")
    val=""
    if [ -n "$raw" ]; then
      case "$kind" in
        bcd)  val=$(bcd_swap "$raw") ;;
        imsi) val=$(bcd_swap "$(printf '%s' "$raw" | cut -c5-)") ;;
        spn)  val=$(hex_txt "$(printf '%s' "$raw" | cut -c3-)") ;;
        plmn) val=$(bcd_swap "$raw") ;;
        *)    val="$raw" ;;
      esac
    fi
    [ "$first" = 1 ] || printf ','
    first=0
    st=ok; [ -n "$raw" ] || st=unreadable
    printf '{"name":"%s","id":"%s","status":"%s","hex":"%s","value":"%s"}' \
      "$(esc "$name")" "$(esc "$hexid")" "$st" "$(esc "$raw")" "$(esc "$val")"
  done
  printf ']}'
} > "$OUT.new" 2>/dev/null

# Swap in atomically so a reader never sees a half-written file.
mv "$OUT.new" "$OUT" 2>/dev/null
