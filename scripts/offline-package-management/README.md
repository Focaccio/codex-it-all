# Offline Package Management

This workflow builds a **standalone disc repository** for adding packages to an
already-installed offline Server 101 system. The repository can be delivered as
a burned disc, mounted disc image, USB copy, or other removable media.

Use "disc image" or `.iso` only for the optional file used to burn or mount the
repository. The mounted payload itself is the standalone disc repository.

## First Site 2 Test Set

The first package set is:

- `screen`
- `expect`
- `glow`
- `iotop`
- `sysstat` for `iostat`
- `atop`
- `glances`
- `lldpd`
- `tftpd-hpa`
- `tftp-hpa` for `tftp`
- `plocate`
- `fd-find`
- `nmap`
- `code`
- `wget`
- `gpg`
- `apt-transport-https`

## Build

Run this on a Debian build host with internet access:

```bash
./scripts/offline-package-management/build-standalone-disc-repository.sh
```

The default output is:

```text
build/offline-package-management/site2-standalone-disc-repository-trixie-amd64/
build/offline-package-management/site2-standalone-disc-repository-trixie-amd64.iso
```

The built repository includes:

```text
manifest/install-targets.txt
manifest/all-deb-packages.tsv
manifest/install-scripts.tsv
manifest/package-dependencies/*.txt
scripts/install-all.sh
scripts/install-*.sh
pool/main/*.deb
```

`install-targets.txt` lists the requested packages. `all-deb-packages.tsv`
lists every bundled `.deb`, including dependencies. The per-package files under
`manifest/package-dependencies/` show the dependency closure calculated against
an empty dpkg status file, while the actual `.deb` files are kept once in the
shared `pool/main` repository.

The generated package install scripts do not rely on APT's `Filename:` handling
for flat `file:` repositories. Each script reads its dependency manifest,
resolves the matching absolute `.deb` paths from `all-deb-packages.tsv`, and
passes those local files directly to `apt-get install`.

## Burn

Before burning, run:

```bash
./scripts/offline-package-management/verify-standalone-disc-repository.sh
```

On the Debian host with the optical burner:

```bash
sudo BURN_DEVICE=/dev/sr0 ./scripts/offline-package-management/burn-standalone-disc-repository.sh
```

## Site 2 Install

After burning or mounting the disc repository on the offline server:

```bash
sudo mkdir -p /mnt/offline-package-repo
sudo mount /dev/sr0 /mnt/offline-package-repo
cd /mnt/offline-package-repo
sudo ./scripts/inventory-before-after.sh before
sudo ./scripts/install-all.sh
```

If the direct mount reports `wrong fs type` immediately after burning, refresh
the optical drive state and mount with:

```bash
sudo ./scripts/offline-package-management/mount-standalone-disc-repository.sh
```

Or install packages individually:

```bash
sudo ./scripts/install-screen.sh
sudo ./scripts/install-iostat.sh
sudo ./scripts/install-code.sh
```

Logs and package inventories are written to:

```text
/var/log/offline-package-management
```
