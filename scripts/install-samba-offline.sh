#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMB_PASSWORD="${SMB_PASSWORD:?Set SMB_PASSWORD before installing Samba}"

groupadd -f smbusers
usermod -aG smbusers autoadmin

install -d -m 2770 -o autoadmin -g smbusers /srv/samba/server101
setfacl -m g:smbusers:rwx /srv/samba/server101
setfacl -d -m g:smbusers:rwx /srv/samba/server101

cp "$SRC_DIR/services/samba/smb.conf" /etc/samba/smb.conf
testparm -s /etc/samba/smb.conf >/dev/null

printf '%s\n%s\n' "$SMB_PASSWORD" "$SMB_PASSWORD" | smbpasswd -a -s autoadmin
smbpasswd -e autoadmin

systemctl disable --now samba-ad-dc 2>/dev/null || true
systemctl enable --now smbd
systemctl enable --now nmbd
