#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

failures=0

pass() {
  printf 'PASS: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

require_file() {
  local path="$1"
  if [ -f "$path" ]; then
    pass "$path exists"
  else
    fail "$path missing"
  fi
}

require_dir() {
  local path="$1"
  if [ -d "$path" ]; then
    pass "$path exists"
  else
    fail "$path missing"
  fi
}

require_executable() {
  local path="$1"
  if [ -x "$path" ]; then
    pass "$path executable"
  else
    fail "$path missing or not executable"
  fi
}

require_package() {
  local pkg="$1"
  if grep -qx "$pkg" profiles/101.packages; then
    pass "package profile includes $pkg"
  else
    fail "package profile missing $pkg"
  fi
}

require_file profiles/101.packages
require_file profiles/101.preseed

for pkg in \
  simple-cdd debian-cd xorriso wodim dvd+rw-tools genisoimage isolinux syslinux-common \
  mtools dosfstools apt-utils udftools eject lsscsi sg3-utils cdck pv docker.io \
  docker-compose bind9 samba xrdp xfce4 sqlite3 initramfs-tools initramfs-tools-core \
  initramfs-tools-bin klibc-utils libklibc busybox cpio kmod udev linux-base linux-image-amd64 \
  grub-common grub2-common grub-efi-amd64 grub-efi-amd64-bin grub-efi-amd64-signed \
  shim-signed efibootmgr grub-pc grub-pc-bin
do
  require_package "$pkg"
done

for pattern in \
  "s101" "top.demosdnx.net" "<SERVER_IP>" "NetworkManager" "systemctl disable ufw" \
  "server101-firstboot.service" "server101-payload"
do
  if grep -q "$pattern" profiles/101.preseed; then
    pass "preseed contains $pattern"
  else
    fail "preseed missing $pattern"
  fi
done

for dir in services/bind services/samba services/observium services/oxidized services/gitea services/systemd artifacts/docker-images artifacts/native-binaries; do
  require_dir "$dir"
done

for script in \
  scripts/build-iso.sh \
  scripts/stage-server101-payload.sh \
  scripts/install-server101-offline.sh \
  scripts/install-bind-offline.sh \
  scripts/install-samba-offline.sh \
  scripts/install-observium-offline.sh \
  scripts/install-oxidized-offline.sh \
  scripts/install-gitea-offline.sh
do
  require_executable "$script"
  bash -n "$script" || fail "$script failed shell syntax check"
done

for artifact in \
  artifacts/docker-images/uberchuckie-observium-12.0.0.tar.gz \
  artifacts/docker-images/mariadb-11.4.tar.gz \
  artifacts/docker-images/oxidized-latest.tar.gz \
  artifacts/native-binaries/gitea-1.26.2-linux-amd64
do
  require_file "$artifact"
done

require_executable artifacts/native-binaries/gitea-1.26.2-linux-amd64
require_file services/systemd/server101-firstboot.service

"$ROOT_DIR/scripts/stage-server101-payload.sh" "$ROOT_DIR/build/server101-payload" >/tmp/server101-stage.log
cat /tmp/server101-stage.log

payload_size=$(du -sm "$ROOT_DIR/build/server101-payload" | awk '{print $1}')
if [ "$payload_size" -lt 7950 ]; then
  pass "payload size ${payload_size} MiB is under DVD+R DL capacity before Debian package pool"
else
  fail "payload size ${payload_size} MiB exceeds DVD+R DL capacity before Debian package pool"
fi

if [ "$failures" -ne 0 ]; then
  printf '\nPre-build validation failed with %s issue(s).\n' "$failures" >&2
  exit 1
fi

printf '\nPre-build validation passed.\n'
