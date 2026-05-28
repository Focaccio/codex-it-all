#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

install -d /etc/bind/zones
cp "$SRC_DIR/services/bind/named.conf.options" /etc/bind/named.conf.options
cp "$SRC_DIR/services/bind/named.conf.local" /etc/bind/named.conf.local
cp "$SRC_DIR/services/bind/zones/db.demosdnx.net" /etc/bind/zones/db.demosdnx.net

named-checkconf
named-checkzone demosdnx.net /etc/bind/zones/db.demosdnx.net
systemctl enable named
systemctl restart named
