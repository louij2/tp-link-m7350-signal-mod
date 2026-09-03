#!/bin/sh
# Prepare a microSD card for the mod: inspect, optionally format, mount, and
# make the mount persist across reboots.
#
#   sd_setup.sh              inspect only, changes NOTHING
#   sd_setup.sh --mount      mount an existing filesystem and persist it
#   CONFIRM=yes sd_setup.sh --format   ERASES THE CARD, then mounts and persists
#
# The format path is deliberately awkward. It refuses without CONFIRM=yes, and it
# refuses to touch anything that is not a removable mmcblk device, because the
# router's own firmware lives on mtd and a mistake here would be unrecoverable.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

MNT=/media/card
MARK=/etc/signalmod_sd
say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---- find the card --------------------------------------------------------
DISK=$(awk '$4 ~ /^mmcblk[0-9]+$/ {print $4; exit}' /proc/partitions 2>/dev/null)
[ -n "$DISK" ] || {
  say "No SD card found."
  say "  /sys/class/mmc_host/mmc0 exists: $([ -d /sys/class/mmc_host/mmc0 ] && echo yes || echo no)"
  say "  If the card is inserted, it may need a reboot to enumerate."
  exit 1
}
PART=$(awk -v d="$DISK" '$4 ~ ("^" d "p[0-9]+$") {print $4; exit}' /proc/partitions 2>/dev/null)
TARGET="/dev/${PART:-$DISK}"

# ---- refuse anything that is not removable flash ---------------------------
case "$TARGET" in
  /dev/mmcblk*) : ;;
  *) die "refusing to operate on '$TARGET': only /dev/mmcblk* is allowed" ;;
esac

SIZE_KB=$(awk -v d="${PART:-$DISK}" '$4 == d {print $3; exit}' /proc/partitions)

say "SD card"
say "  disk        /dev/$DISK"
say "  target      $TARGET"
say "  size        $(awk -v k="$SIZE_KB" 'BEGIN{printf "%.1f GB", k/1048576}')"
say "  partitions  $(awk -v d="$DISK" '$4 ~ ("^" d) {printf "%s ", $4}' /proc/partitions)"

# ---- what is already on it -------------------------------------------------
CURFS=""
if command -v blkid >/dev/null 2>&1; then CURFS=$(blkid "$TARGET" 2>/dev/null); fi
say "  filesystem  ${CURFS:-unknown (no blkid, or unformatted)}"

if mount | grep -q "^$TARGET "; then
  say "  currently mounted at $(mount | awk -v t="$TARGET" '$1==t{print $3; exit}')"
else
  mkdir -p /tmp/_sdpeek 2>/dev/null
  if mount -o ro "$TARGET" /tmp/_sdpeek 2>/dev/null; then
    say "  contents (read-only peek):"
    ls -A /tmp/_sdpeek 2>/dev/null | head -20 | sed 's/^/      /'
    n=$(ls -A /tmp/_sdpeek 2>/dev/null | wc -l)
    say "      ($n entries)"
    umount /tmp/_sdpeek 2>/dev/null
  else
    say "  contents    could not mount (unformatted, or an unsupported filesystem)"
  fi
  rmdir /tmp/_sdpeek 2>/dev/null
fi

[ "$1" = "--format" ] || [ "$1" = "--mount" ] || { say; say "Inspection only. Nothing was changed."; exit 0; }

# ---- format ----------------------------------------------------------------
if [ "$1" = "--format" ]; then
  [ "$CONFIRM" = "yes" ] || die "refusing to format without CONFIRM=yes. Everything above would be erased."
  MKFS=""
  for c in mkfs.ext4 mkfs.ext3 mkfs.ext2 mkfs.vfat mkdosfs; do
    command -v "$c" >/dev/null 2>&1 && { MKFS="$c"; break; }
  done
  [ -n "$MKFS" ] || die "no mkfs tool on the device (looked for ext4/3/2, vfat)"
  say
  say "Formatting $TARGET with $MKFS ..."
  umount "$TARGET" 2>/dev/null
  case "$MKFS" in
    mkfs.ext*) "$MKFS" -F -L SIGMOD "$TARGET" >/dev/null 2>&1 || die "$MKFS failed" ;;
    *)         "$MKFS" -n SIGMOD "$TARGET" >/dev/null 2>&1 || die "$MKFS failed" ;;
  esac
  say "  formatted."
fi

# ---- mount and persist -----------------------------------------------------
mkdir -p "$MNT" 2>/dev/null
mount | grep -q " $MNT " || mount "$TARGET" "$MNT" 2>/dev/null || die "could not mount $TARGET at $MNT"
mkdir -p "$MNT/signalmod/history" "$MNT/signalmod/logs" 2>/dev/null
printf '%s\n' "$TARGET" > "$MARK"
say
say "Mounted $TARGET at $MNT"
say "  free   $(df -h "$MNT" 2>/dev/null | awk 'NR==2{print $4}')"
say "  marker $MARK written, so the init script remounts it at boot"
say "  the mod will now keep signal history on the card instead of tmpfs"
