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

# nibble-swapped BCD, F is padding (ICCID)
bcd_swap(){ printf '%s' "$1" | sed 's/\(.\)\(.\)/\2\1/g' | tr -d 'Ff'; }

# EF_IMSI is not a plain BCD blob. Byte 0 is a LENGTH, and the low nibble of
# byte 1 is a parity flag, not a digit. Dropping two bytes and swapping the rest
# looks plausible and silently returns a wrong IMSI: on the card here it gave
# 08090222141697 for a real 208090222141697.
imsi_decode(){
  h=$(printf '%s' "$1" | cut -c3-)                       # drop the length byte
  sw=$(printf '%s' "$h" | sed 's/\(.\)\(.\)/\2\1/g')  # nibble-swap
  printf '%s' "$sw" | cut -c2- | tr -d 'Ff'              # drop the parity nibble
}

# A PLMN is three bytes holding six nibbles out of order:
#   byte0 = MCC2<<4 | MCC1 ,  byte1 = MNC3<<4 | MCC3 ,  byte2 = MNC2<<4 | MNC1
# MNC3 = F means a two-digit MNC. Swapping the whole thing and stripping F
# happens to give the right answer for a two-digit MNC and the wrong one for a
# three-digit MNC, which is the sort of bug that only shows up abroad.
plmn_one(){
  [ "${#1}" -eq 6 ] || return 1
  case "$1" in FFFFFF|ffffff|000000) return 1 ;; esac
  b0=$(printf '%s' "$1" | cut -c1-2); b1=$(printf '%s' "$1" | cut -c3-4); b2=$(printf '%s' "$1" | cut -c5-6)
  mcc="$(printf '%s' "$b0" | cut -c2)$(printf '%s' "$b0" | cut -c1)$(printf '%s' "$b1" | cut -c2)"
  mnc="$(printf '%s' "$b2" | cut -c2)$(printf '%s' "$b2" | cut -c1)"
  m3=$(printf '%s' "$b1" | cut -c1)
  case "$m3" in F|f) : ;; *) mnc="$mnc$m3" ;; esac
  # Name the ones that matter here; the number is still shown for the rest.
  nm=""
  case "$mcc-$mnc" in
    234-20) nm=" (Three)" ;; 234-30|234-33|234-34|234-86) nm=" (EE)" ;;
    234-15) nm=" (Vodafone)" ;; 234-10|234-11|234-02) nm=" (O2)" ;;
    208-*)  nm=" (France)" ;;
  esac
  printf '%s-%s%s' "$mcc" "$mnc" "$nm"
}

# EF_FPLMN is a run of BARE 3-byte PLMNs. The three *wAcT selectors are NOT:
# each record there is 5 bytes, a 3-byte PLMN followed by a 2-byte access
# technology mask. Reading those at a 3-byte stride walks straight off the
# record boundary and produces confident nonsense ("000-FF0, FFF-00, ...")
# rather than failing, which is exactly what it did on the card here.
# stride is in HEX CHARACTERS: 6 for FPLMN, 10 for the wAcT selectors.
plmn_list(){
  h="$1"; stride="${2:-6}"; out=""
  while [ "${#h}" -ge 6 ]; do
    one=$(plmn_one "$(printf '%s' "$h" | cut -c1-6)") && {
      [ -n "$out" ] && out="$out, "
      out="$out$one"
    }
    h=$(printf '%s' "$h" | cut -c$((stride + 1))-)
  done
  printf '%s' "$out"
}
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
PLMNwAcT:6F60:28512:32:plmnact
OPLMNwAcT:6F61:28513:32:plmnact
HPLMNwAcT:6F62:28514:32:plmnact
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
        imsi) val=$(imsi_decode "$raw") ;;
        spn)  val=$(hex_txt "$(printf '%s' "$raw" | cut -c3-)") ;;
        plmn)    val=$(plmn_list "$raw" 6) ;;
        plmnact) val=$(plmn_list "$raw" 10) ;;
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
