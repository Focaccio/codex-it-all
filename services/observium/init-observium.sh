#!/usr/bin/env bash
set -euo pipefail

cd /opt/server101/services/observium

docker compose up -d

echo "Waiting for Observium web container..."
for _ in $(seq 1 60); do
  if docker exec observium test -f /config/config.php >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

echo "Initializing Observium database schema and default admin user..."
docker exec observium sh -lc 'cd /opt/observium && ./discovery.php -u'
docker exec observium sh -lc 'cd /opt/observium && php adduser.php observium observium 10 || true'

echo "Observium is available at http://<SERVER_IP>:8668/"
echo "Default login: observium / <CHANGE_ME_APP_PASSWORD>"
