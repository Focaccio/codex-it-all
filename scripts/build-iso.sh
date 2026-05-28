#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${PROFILE:-101}"
CODENAME="${CODENAME:-trixie}"
MIRROR="${MIRROR:-http://deb.debian.org/debian}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
PAYLOAD_DIR="${PAYLOAD_DIR:-$BUILD_DIR/server101-payload}"
PAYLOAD_ARCHIVE="${PAYLOAD_ARCHIVE:-$BUILD_DIR/server101-payload.tar.gz}"
ISO_BASENAME="${ISO_BASENAME:-s101-offline-trixie-amd64-new.iso}"
CUSTOM_INSTALLER_DIR="${CUSTOM_INSTALLER_DIR:-$BUILD_DIR/debian-installer}"
LOCAL_MIRROR_INSTALLER_DIR="${LOCAL_MIRROR_INSTALLER_DIR:-$ROOT_DIR/tmp/mirror/dists/$CODENAME/main/installer-amd64/current/images}"
LOCAL_MIRROR_I386_INSTALLER_DIR="${LOCAL_MIRROR_I386_INSTALLER_DIR:-$ROOT_DIR/tmp/mirror/dists/$CODENAME/main/installer-i386/current/images}"
SIMPLE_CDD_CONF="$BUILD_DIR/simple-cdd-$PROFILE.conf"

if ! command -v build-simple-cdd >/dev/null 2>&1; then
  echo "build-simple-cdd is required. Install it with: sudo apt install simple-cdd" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required to stage Debian installer boot files." >&2
  exit 1
fi

mkdir -p "$BUILD_DIR"
"$ROOT_DIR/scripts/stage-server101-payload.sh" "$PAYLOAD_DIR"
tar -C "$BUILD_DIR" -czf "$PAYLOAD_ARCHIVE" "$(basename "$PAYLOAD_DIR")"

install -d "$CUSTOM_INSTALLER_DIR/installer-amd64/current/images/cdrom"
install -d "$LOCAL_MIRROR_INSTALLER_DIR/cdrom"
install -d "$LOCAL_MIRROR_INSTALLER_DIR/cdrom/gtk"
install -d "$LOCAL_MIRROR_I386_INSTALLER_DIR/cdrom"
install -d "$LOCAL_MIRROR_I386_INSTALLER_DIR/cdrom/gtk"
for installer_file in SHA256SUMS cdrom/vmlinuz cdrom/initrd.gz cdrom/debian-cd_info.tar.gz; do
  curl -fsSL \
    "$MIRROR/dists/$CODENAME/main/installer-amd64/current/images/$installer_file" \
    -o "$CUSTOM_INSTALLER_DIR/installer-amd64/current/images/$installer_file"
  cp "$CUSTOM_INSTALLER_DIR/installer-amd64/current/images/$installer_file" \
    "$LOCAL_MIRROR_INSTALLER_DIR/$installer_file"
  cp "$CUSTOM_INSTALLER_DIR/installer-amd64/current/images/$installer_file" \
    "$LOCAL_MIRROR_I386_INSTALLER_DIR/$installer_file"
done

for installer_file in vmlinuz initrd.gz; do
  cp "$CUSTOM_INSTALLER_DIR/installer-amd64/current/images/cdrom/$installer_file" \
    "$LOCAL_MIRROR_INSTALLER_DIR/cdrom/gtk/$installer_file"
  cp "$CUSTOM_INSTALLER_DIR/installer-amd64/current/images/cdrom/$installer_file" \
    "$LOCAL_MIRROR_I386_INSTALLER_DIR/cdrom/gtk/$installer_file"
done

cat >"$SIMPLE_CDD_CONF" <<EOF
profiles="$PROFILE"
auto_profiles="$PROFILE"
all_extras="$PAYLOAD_ARCHIVE"
custom_installer="$CUSTOM_INSTALLER_DIR"
NORECOMMENDS=1
EOF

set +e
NORECOMMENDS=1 build-simple-cdd \
  --conf "$SIMPLE_CDD_CONF" \
  --profiles "$PROFILE" \
  --debian-mirror "$MIRROR" \
  --dist "$CODENAME" \
  --dvd \
  --locale en_US \
  --keyboard us
simple_cdd_status=$?
set -e

if [ "$simple_cdd_status" -ne 0 ] && [ ! -d "$ROOT_DIR/tmp/cd-build/$CODENAME/CD1" ]; then
  echo "build-simple-cdd failed before creating a CD tree." >&2
  exit "$simple_cdd_status"
fi

if [ -d "$ROOT_DIR/tmp/cd-build/$CODENAME/CD1" ]; then
  mkdir -p "$ROOT_DIR/images"
  xorriso -as mkisofs \
    -r \
    -V S101_OFFLINE_NEW \
    -J \
    -joliet-long \
    -e boot/grub/efi.img \
    -no-emul-boot \
    -o "$ROOT_DIR/images/$ISO_BASENAME" \
    "$ROOT_DIR/tmp/cd-build/$CODENAME/CD1"
fi
