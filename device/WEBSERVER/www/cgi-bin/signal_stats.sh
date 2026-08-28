#!/bin/sh
printf 'Content-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\n\r\n'
cat /tmp/signal.json 2>/dev/null || printf '{"error":"no data yet"}'
