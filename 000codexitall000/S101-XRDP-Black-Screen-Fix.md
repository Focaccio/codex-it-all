# S101 XRDP Black Screen Fix

## Symptom

RDP to Server 101 connects successfully, but the remote desktop shows a black
screen.

On the observed S101 system, `xrdp` and `xrdp-sesman` were both active. The RDP
login succeeded and `xfce4-session` started, but the XRDP session inherited
environment state from an existing local Plasma/Wayland login for `autoadmin`.
That mixed session state can leave the RDP client at a black screen.

## Fix Script

Run this on the affected S101 system:

```bash
cd /path/to/Custom-ISO
sudo TARGET_USER=autoadmin ./scripts/fix-xrdp-black-screen.sh
```

The script writes `/home/autoadmin/.xsession` so XRDP starts XFCE in a clean X11
environment:

```sh
exec dbus-run-session -- startxfce4
```

It also restarts:

```text
xrdp
xrdp-sesman
```

## Required Packages

The expected desktop/RDP packages are:

```bash
sudo apt install -y xrdp xorgxrdp xfce4 dbus-x11
```

These were already installed on the tested S101 system.

## Manual Verification

Check services:

```bash
systemctl is-active xrdp xrdp-sesman
```

Check the session file:

```bash
cat /home/autoadmin/.xsession
```

Check recent logs:

```bash
sudo tail -100 /var/log/xrdp.log
sudo tail -100 /var/log/xrdp-sesman.log
tail -100 /home/autoadmin/.xsession-errors
```

## Clearing Stale Sessions

After applying the fix, disconnect the old RDP client and log in again.

If an old XRDP session is still stuck:

```bash
loginctl list-sessions
sudo loginctl terminate-session <session-id>
sudo systemctl restart xrdp xrdp-sesman
```

Avoid terminating the local console session unless you intentionally want to log
out the physical desktop.
