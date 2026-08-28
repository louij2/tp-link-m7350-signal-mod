#!/usr/bin/env bash
# Build a STATIC musl dropbear (SSH server) for the M7350 (armv7l) from source
# and install it over ADB with key-only root login, bound to the LAN.
#
# Why build from source: the device is EGLIBC 2.13 / armv7l / Linux 3.4. A static
# musl binary has no libc dependency, so it runs regardless of the device libc.
# We never download a prebuilt SSH binary -- only the official dropbear SOURCE,
# compiled here.
#
# Requirements on your Mac: Docker running (Little Snitch must allow Docker's
# network so it can pull alpine + fetch the dropbear source), and `adb`.
#
# Usage:  scripts/build-ssh.sh [path-to-your-ssh-pubkey]
#   default pubkey: ~/.ssh/id_ed25519.pub
set -euo pipefail

ADB="${ADB:-adb}"
PUBKEY="${1:-$HOME/.ssh/id_ed25519.pub}"
DROPBEAR_VER=2022.83
LAN_IP=192.168.0.1
HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$HERE/build/ssh"; mkdir -p "$OUT"

say(){ printf '\033[1;36m[*]\033[0m %s\n' "$1"; }

[ -f "$PUBKEY" ] || { echo "No pubkey at $PUBKEY (pass one as arg 1)"; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker isn't running. Start Docker Desktop (and allow it in Little Snitch), then re-run."; exit 1; }
"$ADB" get-state >/dev/null 2>&1 || { echo "No ADB device. Enable ADB + connect USB."; exit 1; }

say "Cross-compiling static dropbear $DROPBEAR_VER (armv7 musl, via QEMU)..."
docker run --rm --platform linux/arm/v7 -v "$OUT":/out alpine:3.19 sh -c "
set -e
apk add --no-cache build-base wget bzip2 >/dev/null 2>&1
cd /tmp
wget -q https://matt.ucc.asn.au/dropbear/releases/dropbear-$DROPBEAR_VER.tar.bz2
tar xjf dropbear-$DROPBEAR_VER.tar.bz2
cd dropbear-$DROPBEAR_VER
./configure --disable-zlib --disable-lastlog --disable-utmp --disable-wtmp \
            CFLAGS='-Os' LDFLAGS='-static' >/dev/null 2>&1
make -j2 PROGRAMS='dropbear dropbearkey scp' >/dev/null 2>&1
cp dropbear dropbearkey scp /out/
strip /out/* 2>/dev/null || true
"
file "$OUT/dropbear" | grep -q 'statically linked' || { echo "Build did not produce a static binary"; exit 1; }
say "Built: $(ls -la "$OUT" | awk '/dropbear$/{print $5" bytes"}')"

say "Installing to the device..."
"$ADB" push "$OUT/dropbear"    /usr/sbin/dropbear
"$ADB" push "$OUT/dropbearkey" /usr/sbin/dropbearkey
"$ADB" push "$OUT/scp"         /usr/bin/scp
"$ADB" shell "chmod 755 /usr/sbin/dropbear /usr/sbin/dropbearkey /usr/bin/scp"

say "Generating host keys (once) + installing your public key..."
"$ADB" shell "mkdir -p /etc/dropbear
  [ -f /etc/dropbear/dropbear_ed25519_host_key ] || /usr/sbin/dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key >/dev/null 2>&1
  [ -f /etc/dropbear/dropbear_rsa_host_key ]     || /usr/sbin/dropbearkey -t rsa -s 2048 -f /etc/dropbear/dropbear_rsa_host_key >/dev/null 2>&1
  mkdir -p /root/.ssh; chmod 700 /root/.ssh"
"$ADB" shell "cat > /root/.ssh/authorized_keys" < "$PUBKEY"
"$ADB" shell "chmod 600 /root/.ssh/authorized_keys"

say "Starting dropbear on $LAN_IP:22 (key-only, no password, LAN only)..."
# -s: disable password logins  -g: disable password logins for root  -p bind LAN only
"$ADB" shell "pkill dropbear 2>/dev/null; sleep 1; setsid /usr/sbin/dropbear -s -g -p $LAN_IP:22 </dev/null >/dev/null 2>&1 &"
sleep 2
"$ADB" shell "netstat -ltn 2>/dev/null | grep ':22 ' && echo 'dropbear listening'" || echo "not listening yet"

# Boot persistence: append to the signal_poll init start hook.
say "Adding boot persistence..."
"$ADB" shell "grep -q dropbear /etc/init.d/signal_poll 2>/dev/null || sed -i 's#^    echo \"done\"#    [ -x /usr/sbin/dropbear ] \\&\\& ! netstat -ltn 2>/dev/null | grep -q \":22 \" \\&\\& setsid /usr/sbin/dropbear -s -g -p $LAN_IP:22 </dev/null >/dev/null 2>\\&1 \\&\n    echo \"done\"#' /etc/init.d/signal_poll"

say "Done. Connect with:  ssh root@$LAN_IP"
say "(Key-only, root, LAN-bound. To stop: adb shell pkill dropbear)"
