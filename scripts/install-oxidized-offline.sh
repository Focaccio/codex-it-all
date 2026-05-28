#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_DIR="/opt/server101/services/oxidized"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required before installing Oxidized." >&2
  exit 1
fi

install -d "$DEST_DIR/config" "$DEST_DIR/output"
cp "$SRC_DIR/services/oxidized/docker-compose.yml" "$DEST_DIR/docker-compose.yml"
cp "$SRC_DIR/services/oxidized/config" "$DEST_DIR/config/config"

if [ ! -f "$DEST_DIR/config/router.db" ]; then
  cp "$SRC_DIR/services/oxidized/router.db" "$DEST_DIR/config/router.db"
fi

if [ -f "$SRC_DIR/artifacts/docker-images/oxidized-latest.tar.gz" ]; then
  gzip -dc "$SRC_DIR/artifacts/docker-images/oxidized-latest.tar.gz" | docker load
fi

chown -R 30000:30000 "$DEST_DIR/config" "$DEST_DIR/output" 2>/dev/null || true

cd "$DEST_DIR"
docker compose up -d
