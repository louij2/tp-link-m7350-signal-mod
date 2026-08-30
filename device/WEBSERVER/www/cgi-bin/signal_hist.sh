#!/bin/sh
# Rolling RSRP history for the UI sparkline. Reads the daemon's ring only, so
# it never touches an AT channel. Served as a bare comma-separated list to keep
# it small: the UI polls this once a minute, not on every signal refresh.
printf 'Content-Type: text/plain\r\nAccess-Control-Allow-Origin: *\r\nCache-Control: no-store\r\n\r\n'
tr '\n' ',' < /tmp/signal_hist 2>/dev/null | sed 's/,$//'
