# Offline Package Management Implementation Guide

## Purpose

This guide documents the Site 2 standalone disc repository workflow for adding
packages to an already-installed offline Server 101 system.

The repository is not a bootable OS installer. It is a portable APT repository
with package files, dependency metadata, install scripts, and manifests. The
repository can be delivered as a burned disc, mounted disc image, USB copy, or
other removable media.

## Naming Convention

- Standalone disc repository: the offline package repository and scripts.
- Disc image: the `.iso` file used to burn or mount the repository.
- Mounted repository: the path where the repository is available on the offline
  server, for example `/mnt/offline-package-repo`.
- Bootable ISO: reserved for OS installer media only.

## Current Site 2 Test Build

Build host:

```text
s101 / 192.168.86.101
```

Built repository:

```text
/home/autoadmin/Custom-ISO/build/offline-package-management/site2-standalone-disc-repository-trixie-amd64
```

Built disc image:

```text
/home/autoadmin/Custom-ISO/build/offline-package-management/site2-standalone-disc-repository-trixie-amd64.iso
```

Disc image SHA256:

```text
d41ab45045b801b2aa4c644498e6120fb0463212aab151c1660859b5b54607b9
```

Burn result:

```text
Device: /dev/sr0
Media: DVD+R/DL
Status: written and closed
Data written: 366 MB
```

## Requested Install Targets

The package set is maintained in:

```text
package-sets/site2-admin-tools.txt
```

Current install targets:

```text
apt-transport-https
atop
code
expect
fd-find
glances
glow
gpg
iotop
lldpd
nmap
plocate
screen
sysstat
tftp-hpa
tftpd-hpa
wget
```

Package-name notes:

- `iostat` is provided by Debian package `sysstat`.
- `tftp` client is provided by Debian package `tftp-hpa`.
- `code` is Microsoft Visual Studio Code from `packages.microsoft.com`.

## Repository Contents

Each built standalone disc repository contains:

```text
README.txt
Packages
Packages.gz
Release
SHA256SUMS
manifest/install-targets.txt
manifest/source-package-set.txt
manifest/all-deb-packages.tsv
manifest/install-scripts.tsv
manifest/package-dependencies/*.txt
pool/main/*.deb
scripts/install-all.sh
scripts/install-*.sh
scripts/install-one-package.sh
scripts/inventory-before-after.sh
```

The `.deb` files are stored once in `pool/main`. Individual package installers
use the shared repository instead of duplicating dependencies into separate
folders.

## Dependency Completeness

The builder resolves packages against an empty dpkg status file. This makes APT
download the full dependency closure as if the offline system had no packages
installed beyond the assumptions required to run APT itself.

This is intentionally conservative. If the offline Server 101 system already
has some dependencies installed, APT will skip them at install time. If it does
not have them, the required `.deb` files are already present in the standalone
disc repository.

The current verified build contains:

```text
Install targets: 17
Bundled .deb packages: 284
```

## Build Workflow

Run from a Debian host with internet access:

```bash
cd /home/autoadmin/Custom-ISO
./scripts/offline-package-management/build-standalone-disc-repository.sh
```

Default output:

```text
build/offline-package-management/site2-standalone-disc-repository-trixie-amd64/
build/offline-package-management/site2-standalone-disc-repository-trixie-amd64.iso
build/offline-package-management/site2-standalone-disc-repository-trixie-amd64.iso.sha256
```

Useful build overrides:

```bash
CODENAME=trixie ARCH=amd64 ./scripts/offline-package-management/build-standalone-disc-repository.sh
PACKAGE_SET=/path/to/package-list.txt ./scripts/offline-package-management/build-standalone-disc-repository.sh
OUTPUT_NAME=custom-disc-repository-name ./scripts/offline-package-management/build-standalone-disc-repository.sh
```

## Pre-Burn Verification

Always verify before burning:

```bash
cd /home/autoadmin/Custom-ISO
./scripts/offline-package-management/verify-standalone-disc-repository.sh
```

The verifier checks:

- Disc image checksum.
- Required repository files and directories.
- Portable APT metadata with relative `Filename:` paths.
- `.deb` count matches APT `Packages` entries.
- `.deb` count matches `manifest/all-deb-packages.tsv`.
- Every install target has an executable package-specific installer.
- Every install target has a per-package dependency manifest.
- A no-install APT simulation can resolve all install targets using only the
  standalone repository.

Expected success message:

```text
Pre-burn verification passed.
```

## Burn Workflow

Burn on the host with the optical drive:

```bash
cd /home/autoadmin/Custom-ISO
sudo BURN_DEVICE=/dev/sr0 ./scripts/offline-package-management/burn-standalone-disc-repository.sh
```

The script prompts for confirmation:

```text
Continue? Type YES to burn:
```

For the first Site 2 test, the burn completed successfully on `/dev/sr0`.

## Site 2 Offline Install Workflow

On the offline Server 101 system:

```bash
sudo mkdir -p /mnt/offline-package-repo
sudo mount /dev/sr0 /mnt/offline-package-repo
cd /mnt/offline-package-repo
sudo ./scripts/inventory-before-after.sh before
sudo ./scripts/install-all.sh
```

Install individual packages when needed:

```bash
sudo ./scripts/install-screen.sh
sudo ./scripts/install-expect.sh
sudo ./scripts/install-glow.sh
sudo ./scripts/install-iotop.sh
sudo ./scripts/install-iostat.sh
sudo ./scripts/install-atop.sh
sudo ./scripts/install-glances.sh
sudo ./scripts/install-lldpd.sh
sudo ./scripts/install-tftpd-hpa.sh
sudo ./scripts/install-tftp.sh
sudo ./scripts/install-plocate.sh
sudo ./scripts/install-fd-find.sh
sudo ./scripts/install-nmap.sh
sudo ./scripts/install-code.sh
```

The install scripts write logs and inventory snapshots to:

```text
/var/log/offline-package-management
```

## Troubleshooting

If `apt-get update` fails on Site 2, confirm the repository is mounted:

```bash
mount | grep offline-package-repo
ls /mnt/offline-package-repo/Packages
ls /mnt/offline-package-repo/pool/main
```

If a package install fails, collect:

```text
/var/log/offline-package-management/install-*.log
/var/log/offline-package-management/manual-before-*.txt
/var/log/offline-package-management/manual-after-*.txt
/var/log/offline-package-management/dpkg-before-*.txt
/var/log/offline-package-management/dpkg-after-*.txt
```

If the disc cannot be read, rebuild and rerun the pre-burn verifier before
burning new media.

## Maintenance

To add packages:

1. Edit `package-sets/site2-admin-tools.txt`.
2. Rebuild the standalone disc repository.
3. Run the pre-burn verifier.
4. Burn new media.
5. Test on the offline system.

Keep package aliases documented in the package set when user-facing command
names differ from Debian package names.
