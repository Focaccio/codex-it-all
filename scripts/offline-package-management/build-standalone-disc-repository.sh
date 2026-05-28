#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGE_SET="${PACKAGE_SET:-$ROOT_DIR/package-sets/site2-admin-tools.txt}"
CODENAME="${CODENAME:-trixie}"
ARCH="${ARCH:-amd64}"
DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
DEBIAN_SECURITY_MIRROR="${DEBIAN_SECURITY_MIRROR:-http://security.debian.org/debian-security}"
DEBIAN_KEYRING="${DEBIAN_KEYRING:-/usr/share/keyrings/debian-archive-keyring.gpg}"
INCLUDE_MICROSOFT_CODE="${INCLUDE_MICROSOFT_CODE:-1}"
OUTPUT_NAME="${OUTPUT_NAME:-site2-standalone-disc-repository-$CODENAME-$ARCH}"
BUILD_ROOT="${BUILD_ROOT:-$ROOT_DIR/build/offline-package-management}"
WORK_DIR="$BUILD_ROOT/work"
APT_ROOT="$WORK_DIR/apt-root"
REPO_DIR="$BUILD_ROOT/$OUTPUT_NAME"
DEB_DIR="$REPO_DIR/pool/main"
SCRIPTS_DIR="$REPO_DIR/scripts"
LOG_DIR="$BUILD_ROOT/logs"
DISC_IMAGE="$BUILD_ROOT/$OUTPUT_NAME.iso"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    echo "Install build prerequisites with: sudo apt install apt-utils xorriso curl ca-certificates gpg" >&2
    exit 1
  fi
}

clean_package_list() {
  sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$PACKAGE_SET" | awk '{$1=$1; print}' | sort -u
}

package_to_script_name() {
  case "$1" in
    sysstat) printf '%s\n' "iostat" ;;
    tftp-hpa) printf '%s\n' "tftp" ;;
    code) printf '%s\n' "code" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

script_to_package_name() {
  case "$1" in
    iostat) printf '%s\n' "sysstat" ;;
    tftp) printf '%s\n' "tftp-hpa" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

write_install_one_script() {
  local script_path="$1"
  cat >"$script_path" <<'INSTALL_ONE_EOF'
#!/usr/bin/env bash
set -euo pipefail

PACKAGE_NAME="${1:?package name required}"
DEPENDENCY_SET="${2:-$PACKAGE_NAME}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${LOG_DIR:-/var/log/offline-package-management}"
LOG_FILE="$LOG_DIR/install-$PACKAGE_NAME-$(date +%Y%m%dT%H%M%S).log"
TMP_APT_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_APT_DIR"
}
trap cleanup EXIT

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo: sudo $0 $PACKAGE_NAME" >&2
  exit 1
fi

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Offline Package Management"
echo "Repository: $REPO_ROOT"
echo "Package: $PACKAGE_NAME"
echo "Dependency set: $DEPENDENCY_SET"
echo "Started: $(date -Is)"

apt-mark showmanual | sort >"$LOG_DIR/manual-before-$PACKAGE_NAME.txt" || true
dpkg-query -W -f='${Package}\t${Version}\t${Status}\n' | sort >"$LOG_DIR/dpkg-before-$PACKAGE_NAME.txt" || true

DEPENDENCY_FILE="$REPO_ROOT/manifest/package-dependencies/$DEPENDENCY_SET.txt"
PACKAGE_MANIFEST="$REPO_ROOT/manifest/all-deb-packages.tsv"

if [ ! -f "$DEPENDENCY_FILE" ]; then
  echo "Missing dependency manifest: $DEPENDENCY_FILE" >&2
  exit 1
fi

if [ ! -f "$PACKAGE_MANIFEST" ]; then
  echo "Missing package manifest: $PACKAGE_MANIFEST" >&2
  exit 1
fi

mapfile -t DEB_PATHS < <(
  awk -F '\t' '
    NR == FNR {
      wanted[$1] = 1
      next
    }
    $1 in wanted {
      print repo "/" $3
    }
  ' repo="$REPO_ROOT" "$DEPENDENCY_FILE" "$PACKAGE_MANIFEST"
)

if [ "${#DEB_PATHS[@]}" -eq 0 ]; then
  echo "No local .deb paths resolved for package: $PACKAGE_NAME" >&2
  exit 1
fi

missing=0
for deb_path in "${DEB_PATHS[@]}"; do
  if [ ! -f "$deb_path" ]; then
    echo "Missing bundled package file: $deb_path" >&2
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  exit 1
fi

install -d "$TMP_APT_DIR/lists/partial" "$TMP_APT_DIR/cache/partial"
: >"$TMP_APT_DIR/sources.list"

APT_OPTS=(
  -o "Dir::Etc::sourcelist=$TMP_APT_DIR/sources.list"
  -o "Dir::Etc::sourceparts=-"
  -o "Dir::State::lists=$TMP_APT_DIR/lists"
  -o "Dir::Cache::archives=$TMP_APT_DIR/cache"
  -o "Dir::Cache::pkgcache=$TMP_APT_DIR/pkgcache.bin"
  -o "Dir::Cache::srcpkgcache=$TMP_APT_DIR/srcpkgcache.bin"
  -o "Debug::NoLocking=1"
)

apt-get "${APT_OPTS[@]}" install -y --no-install-recommends "${DEB_PATHS[@]}"

apt-mark showmanual | sort >"$LOG_DIR/manual-after-$PACKAGE_NAME.txt" || true
dpkg-query -W -f='${Package}\t${Version}\t${Status}\n' | sort >"$LOG_DIR/dpkg-after-$PACKAGE_NAME.txt" || true

echo "Completed: $(date -Is)"
echo "Log: $LOG_FILE"
INSTALL_ONE_EOF
  chmod 0755 "$script_path"
}

write_repo_install_scripts() {
  local packages_file="$1"

  install -d "$SCRIPTS_DIR"
  write_install_one_script "$SCRIPTS_DIR/install-one-package.sh"

  while read -r package_name; do
    [ -n "$package_name" ] || continue
    script_name="$(package_to_script_name "$package_name")"
    cat >"$SCRIPTS_DIR/install-$script_name.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
"\$SCRIPT_DIR/install-one-package.sh" "$(script_to_package_name "$script_name")" "$script_name"
EOF
    chmod 0755 "$SCRIPTS_DIR/install-$script_name.sh"
  done <"$packages_file"

  cat >"$SCRIPTS_DIR/install-all.sh" <<'INSTALL_ALL_EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_LIST="$SCRIPT_DIR/../manifest/packages.txt"

while read -r package_name; do
  [ -n "$package_name" ] || continue
  case "$package_name" in
    sysstat) "$SCRIPT_DIR/install-iostat.sh" ;;
    tftp-hpa) "$SCRIPT_DIR/install-tftp.sh" ;;
    *) "$SCRIPT_DIR/install-$package_name.sh" ;;
  esac
done <"$PACKAGE_LIST"
INSTALL_ALL_EOF
  chmod 0755 "$SCRIPTS_DIR/install-all.sh"

  cat >"$SCRIPTS_DIR/inventory-before-after.sh" <<'INVENTORY_EOF'
#!/usr/bin/env bash
set -euo pipefail

LABEL="${1:-inventory}"
LOG_DIR="${LOG_DIR:-/var/log/offline-package-management}"

mkdir -p "$LOG_DIR"
apt-mark showmanual | sort >"$LOG_DIR/manual-$LABEL.txt" || true
dpkg-query -W -f='${Package}\t${Version}\t${Status}\n' | sort >"$LOG_DIR/dpkg-$LABEL.txt" || true

echo "Wrote inventory files to $LOG_DIR using label: $LABEL"
INVENTORY_EOF
  chmod 0755 "$SCRIPTS_DIR/inventory-before-after.sh"
}

write_manifests() {
  local packages_file="$1"
  local package_name
  local script_name

  cp "$packages_file" "$REPO_DIR/manifest/install-targets.txt"

  awk '
    /^Package: / { package=$2 }
    /^Version: / { version=$2 }
    /^Filename: / { filename=$2 }
    /^SHA256: / {
      sha256=$2
      if (package != "") {
        printf "%s\t%s\t%s\t%s\n", package, version, filename, sha256
      }
    }
  ' "$REPO_DIR/Packages" | sort >"$REPO_DIR/manifest/all-deb-packages.tsv"

  {
    printf "script\tpackage\n"
    while read -r package_name; do
      [ -n "$package_name" ] || continue
      script_name="$(package_to_script_name "$package_name")"
      printf "scripts/install-%s.sh\t%s\n" "$script_name" "$package_name"
    done <"$packages_file"
    printf "scripts/install-all.sh\t%s\n" "all install targets"
  } >"$REPO_DIR/manifest/install-scripts.tsv"

  install -d "$REPO_DIR/manifest/package-dependencies"
  while read -r package_name; do
    [ -n "$package_name" ] || continue
    script_name="$(package_to_script_name "$package_name")"
    apt-get "${APT_OPTS[@]}" --simulate --no-install-recommends install "$package_name" \
      | awk '/^Inst / {print $2}' \
      | sort -u >"$REPO_DIR/manifest/package-dependencies/$script_name.txt"
  done <"$packages_file"
}

write_readme() {
  cat >"$REPO_DIR/README.txt" <<EOF
Offline Package Management - Site 2 Standalone Disc Repository

This is not a bootable OS installer. It is a standalone disc repository for
adding packages to the offline Site 2 Server 101 system.

Recommended Site 2 workflow:

  sudo mkdir -p /mnt/offline-package-repo
  sudo mount /dev/sr0 /mnt/offline-package-repo
  cd /mnt/offline-package-repo
  sudo ./scripts/inventory-before-after.sh before
  sudo ./scripts/install-all.sh

Individual package installers are in:

  scripts/install-*.sh

Manifests are in:

  manifest/install-targets.txt
    Human-requested install targets. These are what install-all.sh installs.

  manifest/all-deb-packages.tsv
    Every .deb package bundled in this standalone disc repository, including
    dependencies, with version, repository filename, and SHA256.

  manifest/install-scripts.tsv
    Script-to-package mapping.

  manifest/package-dependencies/
    Per-install-script dependency closure calculated against an empty dpkg
    status file. The actual .deb files live in the shared pool/main directory.

Package-name notes:

  iostat is installed by scripts/install-iostat.sh, which installs sysstat.
  tftp is installed by scripts/install-tftp.sh, which installs tftp-hpa.
  code installs Microsoft Visual Studio Code from the staged packages.

Logs and package inventories are written to:

  /var/log/offline-package-management
EOF
}

require_command apt-get
require_command apt-ftparchive
require_command curl
require_command gpg
require_command xorriso

if [ ! -f "$PACKAGE_SET" ]; then
  echo "Package set not found: $PACKAGE_SET" >&2
  exit 1
fi

if [ ! -f "$DEBIAN_KEYRING" ]; then
  echo "Debian archive keyring not found: $DEBIAN_KEYRING" >&2
  echo "Install it with: sudo apt install debian-archive-keyring" >&2
  exit 1
fi

rm -rf "$WORK_DIR" "$REPO_DIR" "$DISC_IMAGE"
install -d "$APT_ROOT/etc/apt/sources.list.d" \
  "$APT_ROOT/etc/apt/preferences.d" \
  "$APT_ROOT/etc/apt/trusted.gpg.d" \
  "$APT_ROOT/var/lib/apt/lists/partial" \
  "$APT_ROOT/var/cache/apt/archives/partial" \
  "$DEB_DIR" \
  "$REPO_DIR/manifest" \
  "$LOG_DIR"

PACKAGES_FILE="$WORK_DIR/packages.txt"
clean_package_list >"$PACKAGES_FILE"
cp "$PACKAGES_FILE" "$REPO_DIR/manifest/packages.txt"
cp "$PACKAGE_SET" "$REPO_DIR/manifest/source-package-set.txt"

cat >"$APT_ROOT/etc/apt/sources.list" <<EOF
deb [arch=$ARCH signed-by=$DEBIAN_KEYRING] $DEBIAN_MIRROR $CODENAME main contrib non-free non-free-firmware
deb [arch=$ARCH signed-by=$DEBIAN_KEYRING] $DEBIAN_MIRROR $CODENAME-updates main contrib non-free non-free-firmware
deb [arch=$ARCH signed-by=$DEBIAN_KEYRING] $DEBIAN_SECURITY_MIRROR $CODENAME-security main contrib non-free non-free-firmware
EOF

if [ "$INCLUDE_MICROSOFT_CODE" = "1" ]; then
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor >"$APT_ROOT/etc/apt/trusted.gpg.d/packages.microsoft.gpg"
  cat >"$APT_ROOT/etc/apt/sources.list.d/vscode.list" <<EOF
deb [arch=$ARCH signed-by=$APT_ROOT/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main
EOF
fi

APT_OPTS=(
  -o "Dir=$APT_ROOT"
  -o "Dir::Etc::sourcelist=$APT_ROOT/etc/apt/sources.list"
  -o "Dir::Etc::sourceparts=$APT_ROOT/etc/apt/sources.list.d"
  -o "Dir::Etc::trustedparts=$APT_ROOT/etc/apt/trusted.gpg.d"
  -o "Dir::State::status=$WORK_DIR/empty-status"
  -o "Dir::Cache::archives=$DEB_DIR"
  -o "APT::Architecture=$ARCH"
  -o "Debug::NoLocking=1"
)

: >"$WORK_DIR/empty-status"

apt-get "${APT_OPTS[@]}" update
apt-get "${APT_OPTS[@]}" --download-only --yes --no-install-recommends install $(tr '\n' ' ' <"$PACKAGES_FILE")

(cd "$REPO_DIR" && apt-ftparchive packages pool/main >Packages)
gzip -k "$REPO_DIR/Packages"
apt-ftparchive release "$REPO_DIR" >"$REPO_DIR/Release"

write_manifests "$PACKAGES_FILE"
write_repo_install_scripts "$PACKAGES_FILE"
write_readme

find "$REPO_DIR" -type f -print0 | sort -z | xargs -0 sha256sum >"$REPO_DIR/SHA256SUMS"

xorriso -as mkisofs \
  -r \
  -J \
  -joliet-long \
  -V "SITE2_PKG_REPO" \
  -o "$DISC_IMAGE" \
  "$REPO_DIR"

sha256sum "$DISC_IMAGE" >"$DISC_IMAGE.sha256"

echo "Standalone disc repository staged at: $REPO_DIR"
echo "Disc image created at: $DISC_IMAGE"
echo "Checksum: $DISC_IMAGE.sha256"
