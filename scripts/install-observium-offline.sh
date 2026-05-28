#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_DIR="/opt/server101/services/observium"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required before installing Observium." >&2
  exit 1
fi

: "${OBSERVIUM_DB_ROOT_PASSWORD:?Set OBSERVIUM_DB_ROOT_PASSWORD before installing Observium}"
: "${OBSERVIUM_DB_PASSWORD:?Set OBSERVIUM_DB_PASSWORD before installing Observium}"

install -d "$DEST_DIR"
cp -a "$SRC_DIR/services/observium/." "$DEST_DIR/"
chmod 0755 "$DEST_DIR/init-observium.sh" "$DEST_DIR"/overrides/*

install -d "$DEST_DIR/config" "$DEST_DIR/logs" "$DEST_DIR/rrd" "$DEST_DIR/db"
chown -R 99:100 "$DEST_DIR/config" "$DEST_DIR/logs" "$DEST_DIR/rrd"

if [ -f "$SRC_DIR/artifacts/docker-images/uberchuckie-observium-12.0.0.tar.gz" ]; then
  gzip -dc "$SRC_DIR/artifacts/docker-images/uberchuckie-observium-12.0.0.tar.gz" | docker load
fi

if [ -f "$SRC_DIR/artifacts/docker-images/mariadb-11.4.tar.gz" ]; then
  gzip -dc "$SRC_DIR/artifacts/docker-images/mariadb-11.4.tar.gz" | docker load
fi

"$DEST_DIR/init-observium.sh"
