#!/bin/sh
# Web console backend for the M7350 mod. Runs a shell command sent in the POST
# body (as root -- lighttpd runs as root here) and returns stdout+stderr.
#
# AUTH (fail-closed): this is a root command endpoint, so it REQUIRES a password.
# Set one first (root-only, chmod 600, not in the repo):
#   printf '%s' 'yourpassword' > /etc/signalmod.pw && chmod 600 /etc/signalmod.pw
# The client must send it in the X-Auth header. With no password file, or a
# wrong password, the endpoint refuses. Never expose the web UI to the internet
# with this installed.
#
# Commands run under `timeout` so a hung command cannot wedge lighttpd.

PWFILE=/etc/signalmod.pw
if [ ! -s "$PWFILE" ] || [ "$HTTP_X_AUTH" != "$(cat "$PWFILE" 2>/dev/null)" ]; then
  printf 'Status: 403 Forbidden\r\nContent-Type: text/plain\r\nCache-Control: no-store\r\n\r\n'
  echo "auth required (set /etc/signalmod.pw and send X-Auth)"
  exit 0
fi

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
