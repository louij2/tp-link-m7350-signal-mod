#!/usr/bin/env bash
# Fast redeploy of the web-UI mod to the device.
#
# Works over either transport, picked automatically:
#   ADB  - when the router is plugged into this machine over USB (preferred:
#          it does not ride the LTE link, so it cannot cut itself off).
#   SSH  - when it is not. Uses the static dropbear installed by
#          scripts/build-ssh.sh (key-only root). Handy when the device is
#          remote, e.g. behind a GL.iNet over Tailscale.
#
# Pushes the JS + CGIs and AUTO-BUMPS the ?v= cache-buster on the injected
# <script> so browsers always fetch the latest edit (no manual version bump).
# Does NOT restart the signal daemon (use scripts/install.sh for a full install).
#
#   scripts/deploy.sh                    # auto: ADB if present, else SSH
#   M7350_HOST=192.168.2.1 scripts/deploy.sh
#   M7350_TRANSPORT=ssh scripts/deploy.sh    # force one or the other
#
# Typical loop: edit device/WEBSERVER/www/sigmod.js -> save -> scripts/deploy.sh
# (or let the git post-merge hook run it for you).
set -euo pipefail

ADB="${ADB:-adb}"
HOST="${M7350_HOST:-192.168.2.1}"
USER_="${M7350_USER-root}"
# The scp/ssh target. Set M7350_SSH_TARGET to a bare ~/.ssh/config alias (or
# M7350_USER= to an empty string) when the host entry already supplies the user
# and identity -- forcing "root@alias" would otherwise bypass that config.
TARGET="${M7350_SSH_TARGET:-${USER_:+$USER_@}$HOST}"
# -T because an interactive PTY to this dropbear is flaky; keepalives so a dead
# LTE link fails fast instead of hanging the deploy.
SSH_OPTS="${M7350_SSH_OPTS:--o ConnectTimeout=8 -o ServerAliveInterval=5 -o ServerAliveCountMax=3 -o BatchMode=yes}"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEV="$HERE/device"
# Overridable only so the SSH transport can be exercised against a throwaway
# directory on any box; the device always uses the default.
WWW="${M7350_WWW:-/WEBSERVER/www}"
say(){ printf '\033[1;36m[*]\033[0m %s\n' "$1"; }
die(){ printf '\033[1;31m[!]\033[0m %s\n' "$1" >&2; exit 1; }

# ---- pick a transport ------------------------------------------------------
TRANSPORT="${M7350_TRANSPORT:-auto}"
if [ "$TRANSPORT" = auto ]; then
  if "$ADB" get-state >/dev/null 2>&1; then
    TRANSPORT=adb
  elif ssh $SSH_OPTS -T "$TARGET" true >/dev/null 2>&1; then
    TRANSPORT=ssh
  else
    die "No device: ADB is not connected and SSH to $TARGET did not answer.
    Plug the router in over USB, or check the LAN/Tailscale path to $HOST."
  fi
fi

case "$TRANSPORT" in
  adb) "$ADB" get-state >/dev/null 2>&1 || die "M7350_TRANSPORT=adb but no ADB device is connected." ;;
  ssh) ssh $SSH_OPTS -T "$TARGET" true >/dev/null 2>&1 || die "M7350_TRANSPORT=ssh but $TARGET did not answer." ;;
  *)   die "Unknown M7350_TRANSPORT '$TRANSPORT' (use adb, ssh or auto)." ;;
esac
if [ "$TRANSPORT" = ssh ]; then say "Transport: ssh ($TARGET)"; else say "Transport: adb (USB)"; fi

# ---- transport-agnostic primitives ----------------------------------------
push(){ # push <local> <remote>
  case "$TRANSPORT" in
    adb) "$ADB" push "$1" "$2" >/dev/null ;;
    ssh) scp $SSH_OPTS -q "$1" "$TARGET:$2" ;;
  esac
}
run(){  # run <shell command>
  case "$TRANSPORT" in
    adb) "$ADB" shell "$1" ;;
    ssh) ssh $SSH_OPTS -T "$TARGET" "$1" ;;
  esac
}

# ---- deploy ---------------------------------------------------------------
say "Pushing web assets..."
for f in sigmod.js; do
  push "$DEV/WEBSERVER/www/$f" "$WWW/$f" && run "chmod 644 $WWW/$f"
done
for c in signal_stats.sh sysinfo.sh control.sh deviceinfo.sh metrics.sh; do
  [ -f "$DEV/WEBSERVER/www/cgi-bin/$c" ] || continue
  push "$DEV/WEBSERVER/www/cgi-bin/$c" "$WWW/cgi-bin/$c" && run "chmod 755 $WWW/cgi-bin/$c"
done

# Bump the cache-buster to a value that always changes, so edits show without a
# hard-refresh. Device uptime + a local random keeps it monotonic-ish and unique.
V="$(run 'cut -d. -f1 /proc/uptime' | tr -d '\r\n')$RANDOM"
say "Cache-busting sigmod.js?v=$V ..."
for p in login.html settings.html; do
  # Not every firmware build has both pages -- skip the ones that are absent
  # instead of spraying sed errors.
  run "[ -f $WWW/$p ] && sed -i 's#sigmod.js?v=[0-9]*#sigmod.js?v=$V#g; s#src=\"sigmod.js\"#src=\"sigmod.js?v=$V\"#g' $WWW/$p" >/dev/null 2>&1 || true
done

say "Deployed over $TRANSPORT. Refresh the page (http://$HOST/)."
