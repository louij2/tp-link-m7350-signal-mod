#!/bin/sh
# M7350 mod: apply the configured FTP port to vsftpd's configuration.
#
#   ftp_port.sh            stamp the configured port into the templates and conf
#   ftp_port.sh --show     print what is currently set, change nothing
#
# WHY THE TEMPLATES AND NOT JUST THE LIVE CONF: the firmware's own
# /usr/bin/start_vsftpd regenerates /etc/config/vsftpd/vsftpd.conf with
#   cat <template> > <conf>
# every single time FTP starts. Anything written only to the live conf is wiped
# on the next start, so the port has to live in the templates it is built from.
#
# The originals are backed up once, to *.sigmod-orig, so this is reversible:
#   for f in /etc/config/vsftpd/*.sigmod-orig; do cp "$f" "${f%.sigmod-orig}"; done
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

CONFDIR=/etc/config/vsftpd
LIVE="$CONFDIR/vsftpd.conf"
SETTINGS=/etc/signalmod.conf

PORT=$(sed -n 's/^ftp_port=//p' "$SETTINGS" 2>/dev/null | tail -1)
case "$PORT" in ''|*[!0-9]*) PORT=21 ;; esac
[ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || PORT=21

if [ "$1" = "--show" ]; then
  printf 'configured: %s\n' "$PORT"
  for f in "$CONFDIR"/vsftpd*.conf; do
    [ -f "$f" ] || continue
    printf '  %-40s %s\n' "$f" "$(sed -n 's/^listen_port=//p' "$f" | tail -1 | sed 's/^$/(default 21)/')"
  done
  exit 0
fi

stamp() {
  f="$1"
  [ -f "$f" ] || return 0
  # Back up the untouched original exactly once, so a revert is always possible
  # even after this has been run many times.
  [ -f "$f.sigmod-orig" ] || cp "$f" "$f.sigmod-orig" 2>/dev/null
  tmp="$f.sigmod-tmp"
  # Drop any port line we (or anyone) previously set, then set ours. Port 21 is
  # vsftpd's default, so write nothing for it and leave the file as shipped.
  sed '/^listen_port=/d' "$f" > "$tmp" 2>/dev/null || return 1
  [ "$PORT" = 21 ] || printf 'listen_port=%s\n' "$PORT" >> "$tmp"
  mv "$tmp" "$f" 2>/dev/null
}

# Templates first: these are what start_vsftpd copies from. The live conf is
# stamped too so a port change applies without waiting for a restart cycle.
for f in "$CONFDIR"/vsftpd_anon_ro.conf "$CONFDIR"/vsftpd_anon_rw.conf \
         "$CONFDIR"/vsftpd_signed_rw.conf "$LIVE"; do
  stamp "$f"
done
sync
