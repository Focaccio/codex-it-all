#!/usr/bin/env bash
set -euo pipefail

hostnamectl set-hostname s101

cat >/etc/hosts <<'HOSTS'
127.0.0.1 localhost
127.0.1.1 s101.top.demosdnx.net s101

::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
HOSTS

nmcli con mod "Wired connection 1" \
  connection.interface-name enp0s25 \
  connection.autoconnect yes \
  ipv4.method manual \
  ipv4.addresses <SERVER_IP>/24 \
  ipv4.gateway <GATEWAY_IP> \
  ipv4.dns <GATEWAY_IP> \
  ipv4.dns-search top.demosdnx.net

nmcli con up "Wired connection 1"
