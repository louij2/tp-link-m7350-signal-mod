#!/bin/sh
# Web console backend for the M7350 mod. Runs a shell command sent in the POST
# body (as root -- lighttpd runs as root here) and returns stdout+stderr.
#
# SECURITY: this is an UNAUTHENTICATED root command endpoint. It is intended
# for a device you physically control (USB-tethered, or on a trusted LAN). Do
# NOT expose the web UI to the internet with this installed. Remove exec.sh and
# console.html (or gate them behind auth) if the device is ever public-facing.
#
# The command runs under `timeout` so a hung command (e.g. reading a blocked
# device node) cannot wedge lighttpd -- the same failure mode that made a naive
# `cat /dev/smd7` CGI kill the web server.

printf 'Content-Type: text/plain\r\nAccess-Control-Allow-Origin: *\r\nCache-Control: no-store\r\n\r\n'

CMD=""
if [ "$REQUEST_METHOD" = "POST" ] && [ -n "$CONTENT_LENGTH" ]; then
  CMD=$(head -c "$CONTENT_LENGTH")
fi

if [ -z "$CMD" ]; then
  echo "(no command)"
  exit 0
fi

timeout 20 sh -c "$CMD" 2>&1
rc=$?
echo ""
if [ "$rc" = "124" ]; then
  echo "[timed out after 20s]"
else
  echo "[exit $rc]"
fi
