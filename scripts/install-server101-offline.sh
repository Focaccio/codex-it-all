#!/usr/bin/env bash
set -euo pipefail

PAYLOAD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="/var/log/server101-firstboot.log"
MARKER="/var/lib/server101-firstboot.done"

exec > >(tee -a "$LOG_FILE") 2>&1

if [ -f "$MARKER" ]; then
  echo "Server 101 first-boot installation already completed."
  exit 0
fi

echo "Starting Server 101 offline service installation from $PAYLOAD_DIR"

: "${SMB_PASSWORD:?Set SMB_PASSWORD before running the offline bootstrap}"
: "${GITEA_ADMIN_PASSWORD:?Set GITEA_ADMIN_PASSWORD before running the offline bootstrap}"
: "${OBSERVIUM_DB_ROOT_PASSWORD:?Set OBSERVIUM_DB_ROOT_PASSWORD before running the offline bootstrap}"
: "${OBSERVIUM_DB_PASSWORD:?Set OBSERVIUM_DB_PASSWORD before running the offline bootstrap}"

configure_primary_network() {
  local primary_iface

  primary_iface="$(
    for carrier in /sys/class/net/*/carrier; do
      iface="$(basename "$(dirname "$carrier")")"
      [ "$iface" = "lo" ] && continue
      [ -e "/sys/class/net/$iface/device" ] || continue
      [ "$(cat "$carrier" 2>/dev/null || echo 0)" = "1" ] || continue
      printf '%s\n' "$iface"
      break
    done
  )"

  if [ -z "$primary_iface" ]; then
    primary_iface="$(
      for netdev in /sys/class/net/*; do
        iface="$(basename "$netdev")"
        [ "$iface" = "lo" ] && continue
        [ -e "/sys/class/net/$iface/device" ] || continue
        printf '%s\n' "$iface"
        break
      done
    )"
  fi

  if [ -z "$primary_iface" ]; then
    echo "No physical network interface detected; leaving network unconfigured."
    return 0
  fi

  echo "Configuring primary network interface: $primary_iface"
  install -d /etc/systemd/network
  rm -f /etc/systemd/network/10-enp0s25.network /etc/systemd/network/10-primary.network
  cat >/etc/systemd/network/10-primary.network <<EOF
[Match]
Name=$primary_iface

[Network]
Address=<SERVER_IP>/24
Gateway=<GATEWAY_IP>
DNS=127.0.0.1
DNS=<GATEWAY_IP>
Domains=top.demosdnx.net demosdnx.net
EOF

  printf "%s\n" \
    "search top.demosdnx.net demosdnx.net" \
    "nameserver 127.0.0.1" \
    "nameserver <GATEWAY_IP>" >/etc/resolv.conf

  printf "%s\n" \
    "127.0.0.1 localhost" \
    "127.0.1.1 s101.top.demosdnx.net s101" \
    "<SERVER_IP> s101.top.demosdnx.net s101 top.demosdnx.net demosdnx.net" \
    "<MGMT_IP> mgmt.s101.top.demosdnx.net s101-mgmt" \
    "" \
    "::1 localhost ip6-localhost ip6-loopback" \
    "ff02::1 ip6-allnodes" \
    "ff02::2 ip6-allrouters" >/etc/hosts

  printf "%s\n" "s101" >/etc/hostname
  hostnamectl set-hostname s101 || hostname s101 || true

  systemctl enable systemd-networkd
  systemctl restart systemd-networkd || true
}

install -d /etc/systemd/logind.conf.d
cat >/etc/systemd/logind.conf.d/99-server101-no-powersave.conf <<'EOF'
[Login]
IdleAction=ignore
IdleActionSec=0
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
HandlePowerKey=ignore
HandlePowerKeyLongPress=ignore
HandleSuspendKey=ignore
HandleSuspendKeyLongPress=ignore
HandleHibernateKey=ignore
HandleHibernateKeyLongPress=ignore
EOF

install -d /etc/systemd/system/getty@tty1.service.d
cat >/etc/systemd/system/getty@tty1.service.d/override.conf <<'EOF'
[Service]
ExecStartPre=/usr/bin/setterm --blank 0 --powerdown 0 --powersave off
EOF

install -d /etc/X11/xorg.conf.d
cat >/etc/X11/xorg.conf.d/10-server101-no-dpms.conf <<'EOF'
Section "ServerFlags"
    Option "BlankTime" "0"
    Option "StandbyTime" "0"
    Option "SuspendTime" "0"
    Option "OffTime" "0"
EndSection

Section "Monitor"
    Identifier "Monitor0"
    Option "DPMS" "false"
EndSection
EOF

install -d /etc/udev/rules.d
cat >/etc/udev/rules.d/99-server101-no-usb-autosuspend.rules <<'EOF'
ACTION=="add", SUBSYSTEM=="usb", TEST=="power/control", ATTR{power/control}="on"
EOF

systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
systemctl daemon-reload
systemctl restart systemd-logind || true
udevadm control --reload-rules || true
for power_control in /sys/bus/usb/devices/*/power/control; do
  [ -w "$power_control" ] && echo on >"$power_control" || true
done

configure_primary_network

systemctl start containerd || true
systemctl start docker || true

"$PAYLOAD_DIR/scripts/install-bind-offline.sh"
"$PAYLOAD_DIR/scripts/install-samba-offline.sh"
"$PAYLOAD_DIR/scripts/install-observium-offline.sh"
"$PAYLOAD_DIR/scripts/install-oxidized-offline.sh"
"$PAYLOAD_DIR/scripts/install-gitea-offline.sh"

systemctl enable named smbd nmbd gitea docker containerd
systemctl disable ufw || true

install -d /var/lib
date -Is >"$MARKER"

systemctl disable server101-firstboot.service || true

echo "Server 101 offline service installation completed successfully."
