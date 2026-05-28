#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-autoadmin@<SERVER_IP>}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="captures/s101-${STAMP}"
REMOTE_DIR="/tmp/s101-capture-${STAMP}"
SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=8
  -o StrictHostKeyChecking=accept-new
)

mkdir -p "$OUT_DIR"

echo "Capturing Server 101 from ${TARGET}"
echo "Local output: ${OUT_DIR}"

ssh "${SSH_OPTS[@]}" "$TARGET" "mkdir -p '$REMOTE_DIR'"

ssh "${SSH_OPTS[@]}" "$TARGET" "REMOTE_DIR='$REMOTE_DIR' bash -s" <<'REMOTE'
set -euo pipefail

SUDO=""
if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
  SUDO="sudo -n"
fi

mkdir -p "$REMOTE_DIR"

run() {
  local name="$1"
  shift
  {
    echo "# $*"
    "$@"
  } >"${REMOTE_DIR}/${name}" 2>&1 || true
}

run_sudo() {
  local name="$1"
  shift
  {
    echo "# ${SUDO:-no-sudo} $*"
    if [ -n "$SUDO" ]; then
      $SUDO "$@"
    else
      "$@"
    fi
  } >"${REMOTE_DIR}/${name}" 2>&1 || true
}

run system-summary.txt sh -c '
  echo "hostname=$(hostname)"
  echo "fqdn=$(hostname -f 2>/dev/null || true)"
  echo "kernel=$(uname -a)"
  echo
  cat /etc/os-release 2>/dev/null || true
'

run package-manual.txt apt-mark showmanual
run package-selections.txt dpkg --get-selections
run package-versions.txt dpkg-query -W -f='${binary:Package}\t${Version}\n'
run apt-policy.txt apt-cache policy

mkdir -p "${REMOTE_DIR}/apt"
cp -a /etc/apt/sources.list "${REMOTE_DIR}/apt/" 2>/dev/null || true
cp -a /etc/apt/sources.list.d "${REMOTE_DIR}/apt/" 2>/dev/null || true
cp -a /etc/apt/preferences "${REMOTE_DIR}/apt/" 2>/dev/null || true
cp -a /etc/apt/preferences.d "${REMOTE_DIR}/apt/" 2>/dev/null || true

run enabled-services.txt systemctl list-unit-files --state=enabled
run running-services.txt systemctl list-units --type=service --state=running
run timers.txt systemctl list-timers --all
run failed-units.txt systemctl --failed

run network-addresses.txt ip address show
run network-routes.txt ip route show table all
run network-links.txt ip link show
run resolv-conf.txt sh -c 'cat /etc/resolv.conf 2>/dev/null || true'

run storage-lsblk.txt lsblk -a -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINTS,MODEL,SERIAL
run_sudo storage-blkid.txt blkid
run fstab.txt sh -c 'cat /etc/fstab 2>/dev/null || true'

run ufw-status.txt sh -c 'command -v ufw >/dev/null 2>&1 && ufw status verbose || true'
run_sudo nft-ruleset.txt nft list ruleset
run_sudo iptables-rules.txt iptables-save

run users-passwd.txt sh -c 'getent passwd'
run groups.txt sh -c 'getent group'
run sudoers-listing.txt sh -c 'ls -la /etc/sudoers /etc/sudoers.d 2>/dev/null || true'
run crontab-user.txt sh -c 'crontab -l 2>/dev/null || true'
run cron-listing.txt sh -c 'find /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.monthly /etc/cron.weekly -maxdepth 2 -type f -print 2>/dev/null || true'

run custom-units.txt sh -c 'find /etc/systemd/system -maxdepth 3 -type f -print 2>/dev/null || true'
run modified-etc-files.txt sh -c 'find /etc -xdev -type f -printf "%TY-%Tm-%Td %TH:%TM %p\n" 2>/dev/null | sort || true'

TAR_EXCLUDES=(
  --exclude=/etc/machine-id
  --exclude=/etc/ssh/ssh_host_*
  --exclude=/etc/shadow
  --exclude=/etc/shadow-
  --exclude=/etc/gshadow
  --exclude=/etc/gshadow-
  --exclude=/etc/security/opasswd
  --exclude=/etc/ssl/private
  --exclude=/etc/wireguard
  --exclude=/etc/NetworkManager/system-connections
  --exclude=/etc/letsencrypt
)

if [ -n "$SUDO" ]; then
  $SUDO tar "${TAR_EXCLUDES[@]}" -czf "${REMOTE_DIR}/etc-sanitized.tar.gz" /etc 2>"${REMOTE_DIR}/etc-sanitized-tar.log" || true
else
  tar "${TAR_EXCLUDES[@]}" -czf "${REMOTE_DIR}/etc-sanitized.tar.gz" /etc 2>"${REMOTE_DIR}/etc-sanitized-tar.log" || true
fi

cat >"${REMOTE_DIR}/README.txt" <<EOF
Server 101 capture bundle
Captured at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Source host: $(hostname)

Purpose:
- Record package inventory and reusable configuration for the offline Server 101 ISO.

Important:
- etc-sanitized.tar.gz intentionally excludes obvious machine identity and secret paths.
- Review the bundle before copying any configuration into the ISO profile.
- Do not reuse /etc/machine-id or /etc/ssh/ssh_host_* on installed machines.
EOF
REMOTE

scp "${SSH_OPTS[@]}" -r "$TARGET:$REMOTE_DIR/." "$OUT_DIR/"
ssh "${SSH_OPTS[@]}" "$TARGET" "rm -rf '$REMOTE_DIR'"

cp "$OUT_DIR/package-manual.txt" profiles/101.packages.captured
ln -sfn "$(basename "$OUT_DIR")" captures/s101-latest

echo "Capture complete."
echo "Package manifest copied to profiles/101.packages.captured"
echo "Latest bundle: captures/s101-latest"
