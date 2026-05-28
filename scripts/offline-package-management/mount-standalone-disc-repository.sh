#!/usr/bin/env bash
set -euo pipefail

DEVICE="${DEVICE:-/dev/sr0}"
MOUNT_POINT="${MOUNT_POINT:-/mnt/offline-package-repo}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo, for example: sudo DEVICE=/dev/sr0 $0" >&2
  exit 1
fi

mkdir -p "$MOUNT_POINT"

if mountpoint -q "$MOUNT_POINT"; then
  echo "Already mounted: $MOUNT_POINT"
  mount | grep " $MOUNT_POINT " || true
  exit 0
fi

try_mount() {
  mount -t iso9660 -o ro "$DEVICE" "$MOUNT_POINT"
}

if try_mount; then
  echo "Mounted standalone disc repository at: $MOUNT_POINT"
  exit 0
fi

echo "Initial mount failed. Refreshing optical media state for $DEVICE..."
eject "$DEVICE" || true
sleep 3
eject -t "$DEVICE" || true
sleep 8

if try_mount; then
  echo "Mounted standalone disc repository at: $MOUNT_POINT"
  exit 0
fi

echo "Mount failed after media refresh." >&2
echo "Diagnostic commands:" >&2
echo "  lsblk -f $DEVICE" >&2
echo "  blkid $DEVICE" >&2
echo "  file -s $DEVICE" >&2
echo "  dmesg | tail -80" >&2
exit 1
