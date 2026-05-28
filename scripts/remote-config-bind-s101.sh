#!/usr/bin/env bash
set -euo pipefail

hostnamectl set-hostname s101

cat >/etc/hosts <<'HOSTS'
127.0.0.1 localhost
127.0.1.1 s101.top.demosdnx.net s101
<SERVER_IP> s101.top.demosdnx.net s101 top.demosdnx.net demosdnx.net
<MGMT_IP> mgmt.s101.top.demosdnx.net s101-mgmt

::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
HOSTS

cat >/etc/systemd/network/10-enp0s25.network <<'NETWORK'
[Match]
Name=enp0s25

[Network]
Address=<SERVER_IP>/24
Gateway=<GATEWAY_IP>
DNS=127.0.0.1
DNS=<GATEWAY_IP>
Domains=top.demosdnx.net demosdnx.net
NETWORK

cat >/etc/resolv.conf <<'RESOLV'
search top.demosdnx.net demosdnx.net
nameserver 127.0.0.1
nameserver <GATEWAY_IP>
RESOLV

cat >/etc/bind/named.conf.options <<'BINDOPTS'
options {
        directory "/var/cache/bind";

        listen-on { 127.0.0.1; <SERVER_IP>; <MGMT_IP>; };
        listen-on-v6 { none; };

        recursion yes;
        allow-recursion { localhost; <LAN_CIDR>; };
        allow-query { localhost; <LAN_CIDR>; };
        allow-transfer { none; };

        forwarders { <GATEWAY_IP>; };
        dnssec-validation auto;
};
BINDOPTS

cat >/etc/bind/named.conf.local <<'BINDLOCAL'
zone "demosdnx.net" {
        type master;
        file "/etc/bind/zones/db.demosdnx.net";
};
BINDLOCAL

mkdir -p /etc/bind/zones
cat >/etc/bind/zones/db.demosdnx.net <<'ZONE'
$TTL 3600
@       IN SOA  s101.top.demosdnx.net. hostmaster.demosdnx.net. (
                2026052501 ; serial
                3600       ; refresh
                900        ; retry
                604800     ; expire
                3600 )     ; minimum

        IN NS   s101.top.demosdnx.net.

@               IN A     <SERVER_IP>
s101.top        IN A     <SERVER_IP>
mgmt.s101.top   IN A     <MGMT_IP>

top             IN A     <SERVER_IP>
xsl             IN A     <SERVER_IP>
gp8             IN A     <SERVER_IP>

observium.top   IN CNAME s101.top.demosdnx.net.
ZONE

named-checkconf
named-checkzone demosdnx.net /etc/bind/zones/db.demosdnx.net
systemctl restart systemd-networkd
systemctl enable named
systemctl restart named
