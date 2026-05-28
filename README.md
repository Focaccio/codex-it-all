# Server 101 Custom Debian ISO

This project builds a bootable Debian AMD64 installer ISO for **Server 101**.
The Simple-CDD profile is named `101`, and the installed Linux hostname defaults
to `s101`. The intended workflow is:

Known-good site 2 baseline:

```text
s101-offline-trixie-amd64-new_260527.iso
SHA256: dd42b68dd6e5147f85f2ec4ac7d15ce07c0ada489ec304a3072d6021e749ec8a
```

That ISO was tested successfully on site 2 hardware. It includes the explicit
boot/initramfs packages, GRUB UEFI packages, first-boot network detection, and
the offline service payload.

This public repository is a sanitized template. Replace placeholder values such
as `<SERVER_IP>`, `<GATEWAY_IP>`, `<LAN_CIDR>`, and `<CHANGE_ME_PASSWORD>` in a
private working copy before building an installer ISO.

1. Use a Debian build machine, VM, or container with internet access.
2. Put the packages and configuration you want into this project.
3. Build a self-contained custom installer ISO that carries those packages.
4. Boot a second bare-metal x86_64/AMD64 server from that ISO and install Debian
   with the same toolset, without needing internet access.

The recommended approach is to build a reproducible installer ISO, not to clone a
running server image. Cloning works for identical hardware, but it tends to carry
machine-specific state such as disk UUIDs, SSH host keys, network interface names,
logs, caches, and bootloader assumptions.

## Files

- `profiles/101.packages` - packages to include and install.
- `profiles/101.preseed` - Debian Installer answers and late configuration.
- `profiles/101.excludes` - packages to keep off the ISO/install.
- `scripts/build-iso.sh` - builds the bootable ISO with `simple-cdd`.
- `scripts/capture-packages-on-101.sh` - optional helper to run on an existing
  Debian 101 server if you want to turn its manually installed package list into
  the ISO package manifest.

## Build Requirements

Run the build from Debian, not macOS. A small Debian VM is fine. The build
machine needs internet access because it downloads Debian packages and places
them onto the ISO. The second bare-metal server does not need internet access.

```bash
sudo apt update
sudo apt install -y simple-cdd debian-cd xorriso isolinux syslinux-common \
  debian-archive-keyring
```

Then copy this project onto that Debian machine and build:

```bash
cd Custom-ISO
./scripts/build-iso.sh
```

By default the script targets Debian `stable`, architecture `amd64`, and the
official Debian mirror as the build-time package source. Override these when
needed:

```bash
CODENAME=trixie MIRROR=http://deb.debian.org/debian ./scripts/build-iso.sh
```

The generated ISO is written by `simple-cdd` under an `images/` directory.

## Offline Install Requirement

The second bare-metal server must be treated as offline. That means:

- Every package you want installed must be listed in `profiles/101.packages`
  before you build the ISO.
- The build machine downloads packages from the Debian mirror and embeds them in
  the ISO.
- The installer is configured with `apt-setup/use_mirror=false`, so it installs
  from the ISO rather than trying to contact an internet mirror.
- Any custom `.deb` files, scripts, certificates, keys, or config payloads must
  also be included in this project before the ISO is built.
- After install, `/etc/apt/sources.list` may only contain CD/DVD media unless
  you intentionally add an internal mirror later.

If the second server has local network access but no internet, you can still
configure its IP, hostname, DNS, SSH, and firewall normally. Just do not rely on
external package repositories during installation.

## Server 101 Network Identity

The current Server 101 reference settings are:

- Hostname: `s101`
- Domain: `top.demosdnx.net`
- FQDN: `s101.top.demosdnx.net`
- Interface: detected on first boot; the first linked physical NIC is preferred
- Address: `<SERVER_IP>/24`
- Default gateway: `<GATEWAY_IP>`
- DNS server: `127.0.0.1`, forwarding to `<GATEWAY_IP>`
- Admin user: `autoadmin`, configured for passwordless sudo through
  `/etc/sudoers.d/90-autoadmin`

## Customizations

### 1. Remove NetworkManager

Server 101 uses `systemd-networkd`. The installer no longer depends on a fixed
interface name. On first boot, `server101-firstboot.service` detects the first
linked physical NIC, writes `/etc/systemd/network/10-primary.network`, and then
starts the packaged services. NetworkManager is disabled, masked, and purged
from the reference server, and NetworkManager-related packages are listed in
`profiles/101.excludes` so the ISO build does not intentionally include them.

The first-boot generated network config is:

```ini
[Match]
Name=<detected-interface>

[Network]
Address=<SERVER_IP>/24
Gateway=<GATEWAY_IP>
DNS=127.0.0.1
DNS=<GATEWAY_IP>
Domains=top.demosdnx.net demosdnx.net
```

### 2. Networking Tools

Server 101 includes a networking/admin toolkit:

- `screen`
- `tmux`
- `curl`
- `expect`
- `iperf3`
- `tcpdump`
- `nmap`
- `bmon`
- `wireshark`
- `mtr`
- `vlan`
- `bridge-utils`
- `netcat-openbsd`
- `telnet`
- `traceroute`
- `net-tools`

Package-name notes:

- `netcat` is installed as Debian package `netcat-openbsd`.
- `vlan-bridge-utils` is represented by Debian packages `vlan` and
  `bridge-utils`.

The requested `ntop` package is not available from the current Debian `trixie`
repositories configured on Server 101. Add an approved repository or local
`.deb` payload before the ISO build if `ntop`/`ntopng` must be included for the
offline site.

Wireshark is configured so `autoadmin` belongs to the `wireshark` group and can
use the Debian `dumpcap` capture permission path.

### 3. Container Hosting

Server 101 includes Docker from Debian packages:

- `docker.io`
- `docker-compose`
- `docker-buildx`

The install enables `containerd`, `docker`, and `docker.socket`, and adds
`autoadmin` to the `docker` group.

For the offline site, Docker Engine being installed is only half the story.
Container images must also be carried to site 2. Export required images as
tarballs with `docker save` and keep them under `artifacts/docker-images/` or on
separate removable media, then import them with `docker load` after install.

After the offline install, first boot runs:

```text
/opt/server101-payload/scripts/install-server101-offline.sh
```

That bootstrap starts `containerd` and `docker`, loads the saved image tarballs,
and runs the Observium and Oxidized setup scripts:

```text
/opt/server101-payload/scripts/install-observium-offline.sh
/opt/server101-payload/scripts/install-oxidized-offline.sh
```

The public template requires site-specific secrets to be passed as environment
variables before running the bootstrap:

```bash
sudo SMB_PASSWORD='<site-smb-password>' \
  GITEA_ADMIN_PASSWORD='<site-gitea-admin-password>' \
  OBSERVIUM_DB_ROOT_PASSWORD='<site-observium-root-db-password>' \
  OBSERVIUM_DB_PASSWORD='<site-observium-db-password>' \
  /opt/server101-payload/scripts/install-server101-offline.sh
```

For automatic first boot, the systemd unit reads:

```text
/etc/server101/firstboot.env
```

Replace the placeholder values in `profiles/101.preseed` before building a
private ISO so this file is created with site-approved secrets.

Manual checks on the installed server:

```bash
sudo systemctl status containerd docker
docker images
docker ps
docker compose -f /opt/server101/services/observium/docker-compose.yml ps
docker compose -f /opt/server101/services/oxidized/docker-compose.yml ps
```

Manual rerun if only the container stacks need repair:

```bash
sudo OBSERVIUM_DB_ROOT_PASSWORD='<site-observium-root-db-password>' \
  OBSERVIUM_DB_PASSWORD='<site-observium-db-password>' \
  /opt/server101-payload/scripts/install-observium-offline.sh
sudo /opt/server101-payload/scripts/install-oxidized-offline.sh
```

### 4. Observium Container Service

Server 101 runs Observium as Docker containers under:

```text
/opt/server101/services/observium
```

The service uses:

- `uberchuckie/observium:12.0.0`
- `mariadb:11.4`

The original `uberchuckie/observium` image has an embedded MariaDB path, but it
was unreliable on this host. Server 101 now uses a cleaner two-container Compose
layout:

- `observium` for the web/app container
- `observium-db` for MariaDB

The local project includes the Compose files and overrides under
`services/observium/`. The offline image tarballs are stored under
`artifacts/docker-images/`:

```text
artifacts/docker-images/uberchuckie-observium-12.0.0.tar.gz
artifacts/docker-images/mariadb-11.4.tar.gz
```

After an offline install, load and start Observium with:

```bash
sudo ./scripts/install-observium-offline.sh
```

Observium is available at:

```text
http://<SERVER_IP>:8668/
```

Default login:

```text
observium / <CHANGE_ME_APP_PASSWORD>
```

### 5. BIND DNS Service

Server 101 is authoritative for:

```text
demosdnx.net
```

The server FQDN is:

```text
s101.top.demosdnx.net
```

Initial records:

```text
demosdnx.net              A      <SERVER_IP>
top.demosdnx.net          A      <SERVER_IP>
xsl.demosdnx.net          A      <SERVER_IP>
gp8.demosdnx.net          A      <SERVER_IP>
s101.top.demosdnx.net     A      <SERVER_IP>
mgmt.s101.top.demosdnx.net A     <MGMT_IP>
observium.top.demosdnx.net CNAME s101.top.demosdnx.net
```

BIND config files are stored under `services/bind/`. After an offline install,
apply them with:

```bash
sudo ./scripts/install-bind-offline.sh
```

### 6. SMB NAS Service

Server 101 is configured as a standalone Samba file server for Windows
non-domain laptops. It uses SMB2 minimum / SMB3 maximum, not SMB1.

Share:

```text
\\s101\server101
```

Direct IP path:

```text
\\<SERVER_IP>\server101
```

Local path:

```text
/srv/samba/server101
```

Access is for the local Samba user:

```text
autoadmin
```

The Samba password is set by `SMB_PASSWORD` when running the install script:

```bash
sudo SMB_PASSWORD='<site-smb-password>' ./scripts/install-samba-offline.sh
```

Samba config is stored at:

```text
services/samba/smb.conf
```

The configured Debian repositories on the reference Server 101 do not provide
`wsdd`, so Windows clients should connect by hostname or IP path.

### 7. Oxidized Config Backup Service

Server 101 can run Oxidized alongside Observium as a separate Docker Compose
service:

```text
/opt/server101/services/oxidized
```

Web/API:

```text
http://<SERVER_IP>:8888/
```

Device inventory file:

```text
/opt/server101/services/oxidized/config/router.db
```

Inventory format:

```text
hostname-or-ip:model:username:password:input:ssh-kex:ssh-host-key:ssh-encryption:ssh-hmac
```

The project includes a starter config under `services/oxidized/`. After an
offline install, load/start it with:

```bash
sudo ./scripts/install-oxidized-offline.sh
```

Before using it at site 2, pull and export the image while online:

```bash
docker pull oxidized/oxidized:latest
docker save oxidized/oxidized:latest | gzip -1 > artifacts/docker-images/oxidized-latest.tar.gz
```

### 8. Microsoft Remote Desktop Access

Server 101 includes XRDP with an XFCE desktop for lightweight Microsoft Remote
Desktop access.

Packages:

- `xrdp`
- `xorgxrdp`
- `xfce4`
- `xfce4-goodies`
- `dbus-x11`

The install profile writes `/home/autoadmin/.xsession` with `startxfce4`,
enables `xrdp`, and adds the `xrdp` service user to `ssl-cert`.

UFW is intentionally disabled and inactive on Server 101.

Connect with Microsoft Remote Desktop to:

```text
<SERVER_IP>:3389
```

Login:

```text
autoadmin / <CHANGE_ME_PASSWORD>
```

### 9. Gitea Git Service

Server 101 runs Gitea natively as a Debian systemd service, not as a container.
Gitea is not available in the configured Debian `trixie` repositories, so this
project carries the official Linux AMD64 binary under `artifacts/native-binaries/`.

Version:

```text
Gitea 1.26.2
```

Web UI:

```text
http://<SERVER_IP>:3000/
```

Default admin login:

```text
autoadmin / <CHANGE_ME_PASSWORD>
```

Native layout:

```text
/usr/local/bin/gitea
/etc/gitea/app.ini
/var/lib/gitea
/var/lib/gitea/data/gitea.db
/etc/systemd/system/gitea.service
```

The service runs as the `git` system user and uses SQLite, so no external
database service is required. After an offline install, install/start Gitea with:

```bash
sudo ./scripts/install-gitea-offline.sh
```

## Before Installing On Bare Metal

Edit `profiles/101.preseed` before building:

- Review the checked-in `autoadmin` and `root` passwords before sharing or
  publishing this project. They are stored in plain text because Debian preseed
  files are plain text.
- The installed hostname defaults to `s101`. Use this as the machine-safe
  hostname for the human-readable system name "Server 101".
- Review the partitioning section. This starter profile does not fully automate
  disk wiping. That is intentional. Once you know the target disk layout, you can
  add an explicit `partman-auto/disk` and recipe.

## Turning A Real Server 101 Into This ISO Profile

If you first build and configure an internet-connected Debian server named
Server 101, run this on that server:

```bash
./scripts/capture-packages-on-101.sh > profiles/101.packages
```

Or capture Server 101 remotely from this project machine:

```bash
./scripts/capture-s101.sh autoadmin@<SERVER_IP>
```

That creates a timestamped bundle under `captures/`, including package
inventory, service state, apt sources, network/storage facts, firewall state, and
a sanitized `/etc` archive for review. It also writes the captured manual package
list to `profiles/101.packages.captured`.

Then copy over only the configuration you intentionally want every future server
to share. Good candidates are files under `/etc`, systemd service overrides,
SSH server policy, firewall rules, monitoring config, and shell defaults.

Do not copy machine identity:

- `/etc/machine-id`
- `/etc/ssh/ssh_host_*`
- `/var/log/*`
- `/var/cache/apt/*`
- network leases
- host-specific secrets and private keys

For repeated installs, prefer expressing configuration in `profiles/101.preseed`
late commands, a post-install script, Ansible, or a small internal package.

For offline installs, the package capture step is only an inventory aid. After
capturing the list, rebuild the ISO from a Debian build machine with internet
access so all package files and dependencies are present on the ISO.

## Testing

Test the ISO in a VM before booting real hardware:

```bash
qemu-system-x86_64 -m 4096 -enable-kvm -cdrom images/debian-*.iso -boot d
```

On macOS, use UTM, VMware, VirtualBox, or another VM tool to smoke-test the ISO.
