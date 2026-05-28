#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAYLOAD_DIR="${1:-$ROOT_DIR/build/server101-payload}"

required_paths=(
  "$ROOT_DIR/services/bind"
  "$ROOT_DIR/services/gitea"
  "$ROOT_DIR/services/observium"
  "$ROOT_DIR/services/oxidized"
  "$ROOT_DIR/services/samba"
  "$ROOT_DIR/services/systemd/server101-firstboot.service"
  "$ROOT_DIR/scripts/install-bind-offline.sh"
  "$ROOT_DIR/scripts/install-gitea-offline.sh"
  "$ROOT_DIR/scripts/install-observium-offline.sh"
  "$ROOT_DIR/scripts/install-oxidized-offline.sh"
  "$ROOT_DIR/scripts/install-samba-offline.sh"
  "$ROOT_DIR/scripts/install-server101-offline.sh"
  "$ROOT_DIR/artifacts/docker-images/uberchuckie-observium-12.0.0.tar.gz"
  "$ROOT_DIR/artifacts/docker-images/mariadb-11.4.tar.gz"
  "$ROOT_DIR/artifacts/docker-images/oxidized-latest.tar.gz"
  "$ROOT_DIR/artifacts/native-binaries/gitea-1.26.2-linux-amd64"
)

missing=0
for path in "${required_paths[@]}"; do
  if [ ! -e "$path" ]; then
    echo "Missing required payload path: $path" >&2
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  exit 1
fi

rm -rf "$PAYLOAD_DIR"
install -d "$PAYLOAD_DIR/services" "$PAYLOAD_DIR/scripts" "$PAYLOAD_DIR/artifacts/docker-images" "$PAYLOAD_DIR/artifacts/native-binaries"

cp -a "$ROOT_DIR/services/bind" "$PAYLOAD_DIR/services/"
cp -a "$ROOT_DIR/services/gitea" "$PAYLOAD_DIR/services/"
cp -a "$ROOT_DIR/services/observium" "$PAYLOAD_DIR/services/"
cp -a "$ROOT_DIR/services/oxidized" "$PAYLOAD_DIR/services/"
cp -a "$ROOT_DIR/services/samba" "$PAYLOAD_DIR/services/"
cp -a "$ROOT_DIR/services/systemd" "$PAYLOAD_DIR/services/"

cp "$ROOT_DIR/scripts/install-bind-offline.sh" "$PAYLOAD_DIR/scripts/"
cp "$ROOT_DIR/scripts/install-gitea-offline.sh" "$PAYLOAD_DIR/scripts/"
cp "$ROOT_DIR/scripts/install-observium-offline.sh" "$PAYLOAD_DIR/scripts/"
cp "$ROOT_DIR/scripts/install-oxidized-offline.sh" "$PAYLOAD_DIR/scripts/"
cp "$ROOT_DIR/scripts/install-samba-offline.sh" "$PAYLOAD_DIR/scripts/"
cp "$ROOT_DIR/scripts/install-server101-offline.sh" "$PAYLOAD_DIR/scripts/"
chmod 0755 "$PAYLOAD_DIR"/scripts/*.sh

cp "$ROOT_DIR/artifacts/docker-images/uberchuckie-observium-12.0.0.tar.gz" "$PAYLOAD_DIR/artifacts/docker-images/"
cp "$ROOT_DIR/artifacts/docker-images/mariadb-11.4.tar.gz" "$PAYLOAD_DIR/artifacts/docker-images/"
cp "$ROOT_DIR/artifacts/docker-images/oxidized-latest.tar.gz" "$PAYLOAD_DIR/artifacts/docker-images/"
cp "$ROOT_DIR/artifacts/native-binaries/gitea-1.26.2-linux-amd64" "$PAYLOAD_DIR/artifacts/native-binaries/"
chmod 0755 "$PAYLOAD_DIR/artifacts/native-binaries/gitea-1.26.2-linux-amd64"

echo "Staged Server 101 payload at: $PAYLOAD_DIR"
du -sh "$PAYLOAD_DIR"
