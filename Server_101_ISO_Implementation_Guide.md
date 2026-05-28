# Server 101 Offline ISO Implementation Guide

## Purpose

This guide explains how to use the Server 101 bootable offline installer ISO/DVD to install `s101` at site 2 where there is no internet access.

The ISO contains:

- Debian AMD64 installer media
- Server 101 package set
- Offline service payload
- Docker images for Observium and Oxidized
- Native Gitea installer/configuration payload
- BIND DNS configuration for `demosdnx.net`
- Samba SMB share configuration
- XRDP/XFCE remote desktop support
- Power-saving disabled for server use

This guide is sanitized for source control. Before using it to build a private
site installer, replace placeholders such as `<SERVER_IP>`, `<GATEWAY_IP>`,
`<LAN_CIDR>`, and `<CHANGE_ME_PASSWORD>` with site-approved values.

The new ISO/DVD volume label is:

```text
S101_OFFLINE_NEW
```

## Target Server Requirements

- x86_64 / AMD64 bare-metal server
- UEFI boot support recommended
- DVD drive capable of reading the burned disc
- Local disk available for Debian install
- Network is configured after install by first-boot NIC detection
- Intended IP configuration:

```text
Hostname:       s101
FQDN:           s101.top.demosdnx.net
IP address:     <SERVER_IP>/24
Gateway:        <GATEWAY_IP>
DNS:            127.0.0.1, <GATEWAY_IP>
Domain search:  top.demosdnx.net demosdnx.net
```

Default credentials:

```text
User:      autoadmin
Password:  <CHANGE_ME_PASSWORD>

Root:      root
Password:  <CHANGE_ME_PASSWORD>
```

Change these passwords after installation.

## Before Going Onsite

Confirm the DVD was burned and verified. The disc should contain:

```text
/simple-cdd/101.packages
/simple-cdd/101.preseed
/simple-cdd/server101-payload.tar.gz
```

The ISO used to burn the disc was:

```text
/home/autoadmin/Custom-ISO/images/s101-offline-trixie-amd64-new_260527.iso
```

Expected SHA256:

```text
dd42b68dd6e5147f85f2ec4ac7d15ce07c0ada489ec304a3072d6021e749ec8a
```

The disc was verified to include an El Torito UEFI boot catalog, the explicit boot/initramfs and GRUB packages required by the Debian installer, and the Server 101 offline payload.

## Installation Steps

1. Insert the Server 101 DVD into the site 2 bare-metal server.

2. Power on the server and enter the boot menu.

3. Choose the DVD drive in UEFI mode if the firmware offers both legacy and UEFI choices.

4. Start the Debian installer from the DVD.

5. Proceed through disk partitioning carefully.

   The installer profile intentionally leaves disk partitioning interactive so the wrong disk is not wiped automatically.

6. When prompted, select the target disk and partitioning layout.

   A simple guided layout using the whole target disk is usually fine unless the site requires a custom partition plan.

7. Continue installation.

   The installer should not need internet access. Packages are installed from the DVD.

   Network detection/configuration is intentionally handled after the installed system boots. This avoids installer-time failures on hardware whose NIC names or link state differ from the original build server.

8. Allow the installer to finish and reboot.

9. Remove the DVD when the system reboots, unless the firmware asks you to press a key to boot from DVD and you can simply avoid pressing it.

## First Boot Behavior

On first boot, the installer enables a one-time service:

```text
server101-firstboot.service
```

That service unpacks/configures the offline payload and starts the Server 101 services.

It configures:

- Docker and containerd
- Observium container stack
- Oxidized container
- BIND/named
- Samba SMB service
- Native Gitea
- XRDP/XFCE
- Power-saving disablement
- UFW disabled
- NetworkManager removed/disabled

The first-boot log is:

```text
/var/log/server101-firstboot.log
```

The completion marker is:

```text
/var/lib/server101-firstboot.done
```

Site-specific first-boot secrets are read from:

```text
/etc/server101/firstboot.env
```

For a private build, replace the placeholder values in `profiles/101.preseed`
before building the ISO so this file is created with site-approved secrets.

## Docker and Container Startup

Docker is installed from Debian packages during the offline OS install. The first-boot service starts `containerd` and `docker`, loads the saved Docker image tarballs from the offline payload, then starts the Observium and Oxidized Compose stacks.

Check Docker after the first boot:

```bash
sudo systemctl status containerd docker
sudo systemctl enable containerd docker
sudo systemctl start containerd docker
docker version
docker images
```

The offline Docker image tarballs are stored here on the installed server:

```text
/opt/server101-payload/artifacts/docker-images
```

Expected image tarballs:

```text
uberchuckie-observium-12.0.0.tar.gz
mariadb-11.4.tar.gz
oxidized-latest.tar.gz
```

If first boot did not complete, rerun the full offline service bootstrap:

```bash
sudo SMB_PASSWORD='<site-smb-password>' \
  GITEA_ADMIN_PASSWORD='<site-gitea-admin-password>' \
  OBSERVIUM_DB_ROOT_PASSWORD='<site-observium-root-db-password>' \
  OBSERVIUM_DB_PASSWORD='<site-observium-db-password>' \
  /opt/server101-payload/scripts/install-server101-offline.sh
```

Alternatively, place those values in `/etc/server101/firstboot.env` and run the
script with `sudo`.

If only the container services need to be rebuilt, run the individual scripts:

```bash
sudo OBSERVIUM_DB_ROOT_PASSWORD='<site-observium-root-db-password>' \
  OBSERVIUM_DB_PASSWORD='<site-observium-db-password>' \
  /opt/server101-payload/scripts/install-observium-offline.sh
sudo /opt/server101-payload/scripts/install-oxidized-offline.sh
```

Observium is installed under:

```text
/opt/server101/services/observium
```

Useful Observium commands:

```bash
cd /opt/server101/services/observium
sudo docker compose ps
sudo docker compose up -d
sudo docker compose logs --tail 100
```

Oxidized is installed under:

```text
/opt/server101/services/oxidized
```

Useful Oxidized commands:

```bash
cd /opt/server101/services/oxidized
sudo docker compose ps
sudo docker compose up -d
sudo docker compose logs --tail 100
```

Oxidized device inventory is:

```text
/opt/server101/services/oxidized/config/router.db
```

Add devices using this format:

```text
hostname-or-ip:model:username:password:input:ssh-kex:ssh-host-key:ssh-encryption:ssh-hmac
```

Then restart Oxidized:

```bash
cd /opt/server101/services/oxidized
sudo docker compose restart
```

## Post-Install Validation

Log in locally or by SSH:

```bash
ssh autoadmin@<SERVER_IP>
```

Check core services:

```bash
systemctl status docker containerd
systemctl status named
systemctl status smbd nmbd
systemctl status gitea
systemctl status xrdp
```

Check containers:

```bash
docker ps
docker compose -f /opt/server101/services/observium/docker-compose.yml ps
docker compose -f /opt/server101/services/oxidized/docker-compose.yml ps
```

Expected container services:

- Observium
- Observium database/MariaDB
- Oxidized

Check first-boot log:

```bash
sudo tail -100 /var/log/server101-firstboot.log
```

Check no power-saving targets are enabled:

```bash
systemctl is-enabled sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
```

Expected result:

```text
masked
masked
masked
masked
masked
```

## Service URLs

From a machine that can reach `<SERVER_IP>`:

```text
Observium:  http://<SERVER_IP>:8668/
Oxidized:   http://<SERVER_IP>:8888/
Gitea:      http://<SERVER_IP>:3000/
XRDP:       <SERVER_IP> using Microsoft Remote Desktop
```

Known Observium login:

```text
Username: observium
Password: <CHANGE_ME_APP_PASSWORD>
```

Change application passwords after install.

## DNS Validation

Run:

```bash
dig @127.0.0.1 s101.top.demosdnx.net
dig @127.0.0.1 top.demosdnx.net
dig @127.0.0.1 xsl.demosdnx.net
dig @127.0.0.1 gp8.demosdnx.net
```

Also check:

```bash
systemctl status named
named-checkconf
```

## SMB Validation

From the server:

```bash
smbclient -L localhost -U autoadmin
```

Expected share:

```text
server101
```

From a Windows non-domain laptop, connect to:

```text
\\<SERVER_IP>\server101
```

Use the `autoadmin` credentials unless separate SMB users are later created.

## XRDP Validation

From a Windows laptop:

1. Open Microsoft Remote Desktop.
2. Connect to:

```text
<SERVER_IP>
```

3. Log in as:

```text
autoadmin
<CHANGE_ME_PASSWORD>
```

The desktop environment should be XFCE.

## Troubleshooting

### Server does not boot from DVD

- Confirm the DVD drive is selected in UEFI mode.
- Confirm Secure Boot is disabled if the firmware blocks the installer.
- Try another DVD reader if the drive has trouble reading dual-layer media.

### Installer fails while installing GRUB

- Confirm the server was booted in UEFI mode and the target disk has an EFI System Partition.
- Use the current `S101_OFFLINE_NEW` rebuild that explicitly includes the GRUB UEFI packages.
- If the original `S101_OFFLINE_NEW` disc fails with `grub_efi_amd64 package failed to install to /target/`, rebuild/burn the corrected ISO profile before retrying.

### Network is not reachable

Check detected interface name:

```bash
ip link
```

The first-boot script writes:

```text
/etc/systemd/network/10-primary.network
```

If the wrong interface was selected, edit:

```text
/etc/systemd/network/10-primary.network
```

Then restart networking:

```bash
sudo systemctl restart systemd-networkd
```

### Services did not finish configuring

Check:

```bash
sudo systemctl status server101-firstboot.service
sudo tail -200 /var/log/server101-firstboot.log
```

If the first-boot service failed after a correctable issue, rerun:

```bash
sudo /opt/server101-payload/scripts/install-server101-offline.sh
```

### Docker containers are missing

Check Docker:

```bash
sudo systemctl status docker
docker images
docker ps -a
```

The offline image tarballs are stored under:

```text
/opt/server101-payload/artifacts/docker-images
```

Restart Docker if needed:

```bash
sudo systemctl restart containerd docker
```

Rerun the container install scripts:

```bash
sudo OBSERVIUM_DB_ROOT_PASSWORD='<site-observium-root-db-password>' \
  OBSERVIUM_DB_PASSWORD='<site-observium-db-password>' \
  /opt/server101-payload/scripts/install-observium-offline.sh
sudo /opt/server101-payload/scripts/install-oxidized-offline.sh
```

Then check:

```bash
docker ps
```

### Gitea is not reachable

Check:

```bash
systemctl status gitea
ss -lntp | grep 3000
```

### Observium or Oxidized is not reachable

Check:

```bash
docker ps
docker logs observium --tail 100
docker logs oxidized --tail 100
```

## After Installation

Perform these hardening and site-specific steps:

1. Change the `root`, `autoadmin`, Observium, Gitea, and any SMB passwords.
2. Confirm the final static IP plan for site 2.
3. Add real DNS records/devices as needed.
4. Add network devices to Oxidized.
5. Add monitored devices to Observium.
6. Confirm Windows users can access the SMB share.
7. Confirm Microsoft RDP access works.
8. Store the DVD in a labeled case as the Server 101 offline recovery/install disc.
