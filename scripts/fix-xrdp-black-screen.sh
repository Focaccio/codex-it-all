#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${TARGET_USER:-${SUDO_USER:-autoadmin}}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
XSESSION_FILE="$TARGET_HOME/.xsession"
BACKUP_FILE="$TARGET_HOME/.xsession.bak.$(date +%Y%m%d%H%M%S)"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo, for example: sudo TARGET_USER=autoadmin $0" >&2
  exit 1
fi

if [ -z "$TARGET_HOME" ] || [ ! -d "$TARGET_HOME" ]; then
  echo "Could not find home directory for user: $TARGET_USER" >&2
  exit 1
fi

for command_name in dbus-run-session startxfce4 systemctl; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    echo "Install expected packages with: sudo apt install xrdp xorgxrdp xfce4 dbus-x11" >&2
    exit 1
  fi
done

if [ -f "$XSESSION_FILE" ]; then
  cp "$XSESSION_FILE" "$BACKUP_FILE"
  echo "Backed up existing .xsession to: $BACKUP_FILE"
fi

cat >"$XSESSION_FILE" <<'EOF'
#!/bin/sh
unset DBUS_SESSION_BUS_ADDRESS
unset SESSION_MANAGER
unset WAYLAND_DISPLAY
unset WAYLAND_SOCKET
unset KDE_FULL_SESSION
unset KDE_SESSION_VERSION
unset PLASMA_USE_QT_SCALING
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=XFCE
export DESKTOP_SESSION=xfce
export GDK_BACKEND=x11
export QT_QPA_PLATFORM=xcb
exec dbus-run-session -- startxfce4
EOF

chown "$TARGET_USER:$TARGET_USER" "$XSESSION_FILE"
chmod 0644 "$XSESSION_FILE"

echo "Wrote XRDP-safe XFCE startup file: $XSESSION_FILE"

if systemctl list-unit-files xrdp.service >/dev/null 2>&1; then
  systemctl restart xrdp
fi

if systemctl list-unit-files xrdp-sesman.service >/dev/null 2>&1; then
  systemctl restart xrdp-sesman
fi

echo "XRDP services restarted."
echo
echo "If an old black-screen RDP session is still connected, disconnect it and log in again."
echo "If needed, clear stale XRDP-only sessions with:"
echo "  sudo loginctl list-sessions"
echo "  sudo loginctl terminate-session <session-id>"
