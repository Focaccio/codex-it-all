#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITEA_VERSION="${GITEA_VERSION:-1.26.2}"
GITEA_BINARY_SRC="$SRC_DIR/artifacts/native-binaries/gitea-${GITEA_VERSION}-linux-amd64"
GITEA_ADMIN_PASSWORD="${GITEA_ADMIN_PASSWORD:?Set GITEA_ADMIN_PASSWORD before installing Gitea}"

if [ ! -x "$GITEA_BINARY_SRC" ]; then
  echo "Missing executable Gitea binary: $GITEA_BINARY_SRC" >&2
  exit 1
fi

if ! id git >/dev/null 2>&1; then
  useradd --system --create-home --home-dir /var/lib/gitea --shell /bin/bash git
fi

install -o root -g root -m 0755 "$GITEA_BINARY_SRC" /usr/local/bin/gitea
install -d -o git -g git -m 0750 /var/lib/gitea
install -d -o git -g git -m 0750 /var/lib/gitea/custom
install -d -o git -g git -m 0750 /var/lib/gitea/data
install -d -o git -g git -m 0750 /var/lib/gitea/log
install -d -o root -g git -m 0750 /etc/gitea

SECRET_KEY="$(/usr/local/bin/gitea generate secret SECRET_KEY)"
INTERNAL_TOKEN="$(/usr/local/bin/gitea generate secret INTERNAL_TOKEN)"
LFS_JWT_SECRET="$(/usr/local/bin/gitea generate secret JWT_SECRET)"
OAUTH2_JWT_SECRET="$(/usr/local/bin/gitea generate secret JWT_SECRET)"

sed \
  -e "s#__GITEA_SECRET_KEY__#$SECRET_KEY#g" \
  -e "s#__GITEA_INTERNAL_TOKEN__#$INTERNAL_TOKEN#g" \
  -e "s#__GITEA_LFS_JWT_SECRET__#$LFS_JWT_SECRET#g" \
  -e "s#__GITEA_OAUTH2_JWT_SECRET__#$OAUTH2_JWT_SECRET#g" \
  "$SRC_DIR/services/gitea/app.ini" >/etc/gitea/app.ini

chown root:git /etc/gitea/app.ini
chmod 0640 /etc/gitea/app.ini

install -o root -g root -m 0644 "$SRC_DIR/services/gitea/gitea.service" /etc/systemd/system/gitea.service
systemctl daemon-reload
systemctl enable gitea
systemctl restart gitea

sleep 5
systemctl stop gitea

if ! sudo -u git /usr/local/bin/gitea admin user list --config /etc/gitea/app.ini | awk '{print $2}' | grep -qx autoadmin; then
  sudo -u git /usr/local/bin/gitea admin user create \
    --admin \
    --username autoadmin \
    --password "$GITEA_ADMIN_PASSWORD" \
    --email autoadmin@s101.top.demosdnx.net \
    --must-change-password=false \
    --config /etc/gitea/app.ini
fi

systemctl start gitea
