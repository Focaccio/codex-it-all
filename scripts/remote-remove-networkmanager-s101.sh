#!/usr/bin/env bash
set -euo pipefail

cat >/etc/systemd/network/10-enp0s25.network <<'NETWORK'
[Match]
Name=enp0s25

[Network]
Address=<SERVER_IP>/24
Gateway=<GATEWAY_IP>
DNS=<GATEWAY_IP>
Domains=top.demosdnx.net demosdnx.net
NETWORK

cat >/etc/resolv.conf <<'RESOLV'
search top.demosdnx.net demosdnx.net
nameserver <GATEWAY_IP>
RESOLV

systemctl enable systemd-networkd
systemctl restart systemd-networkd

systemctl disable --now NetworkManager 2>/dev/null || true
systemctl mask NetworkManager 2>/dev/null || true

DEBIAN_FRONTEND=noninteractive apt-get purge -y network-manager || true
DEBIAN_FRONTEND=noninteractive apt-get autoremove -y || true

systemctl restart systemd-networkd
