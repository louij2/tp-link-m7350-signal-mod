# Shared guard: confirm the ADB device on the other end is actually an M7350.
#
# adb attaches to ANY Android device. Without this, a phone or tablet plugged in
# for an unrelated reason gets treated as the router, and scripts here push to
# /WEBSERVER/www, /usr/bin and /etc/init.d. This was not hypothetical: a Galaxy
# Tab left plugged in was picked up by the post-merge hook and had web assets
# pushed at it. It only failed because Android's rootfs is read-only.
#
# Usage:  . "$(dirname "$0")/lib/assert-device.sh"; assert_is_m7350
assert_is_m7350() {
  _adb="${ADB:-adb}"
  _probe=$("$_adb" shell '[ -d /WEBSERVER/www ] && uci get product.info.product_name 2>/dev/null || echo UNRECOGNISED_DEVICE' 2>/dev/null | tr -d '\r\n')
  case "$_probe" in
    *M7350*) return 0 ;;
  esac
  echo "" >&2
  echo "Refusing to continue: the connected ADB device does not look like an M7350." >&2
  echo "  it reported: '${_probe:-nothing}', and has no /WEBSERVER/www" >&2
  echo "" >&2
  "$_adb" devices 2>/dev/null | sed 's/^/  /' >&2
  echo "" >&2
  echo "If a phone or tablet is plugged in, unplug it and try again." >&2
  exit 1
}
