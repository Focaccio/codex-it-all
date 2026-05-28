#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODENAME="${CODENAME:-trixie}"
ARCH="${ARCH:-amd64}"
OUTPUT_NAME="${OUTPUT_NAME:-site2-standalone-disc-repository-$CODENAME-$ARCH}"
BUILD_ROOT="${BUILD_ROOT:-$ROOT_DIR/build/offline-package-management}"
REPO_DIR="${REPO_DIR:-$BUILD_ROOT/$OUTPUT_NAME}"
DISC_IMAGE="${DISC_IMAGE:-$BUILD_ROOT/$OUTPUT_NAME.iso}"
DISC_IMAGE_SHA256="${DISC_IMAGE_SHA256:-$DISC_IMAGE.sha256}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

script_name_for_package() {
  case "$1" in
    sysstat) printf '%s\n' "iostat" ;;
    tftp-hpa) printf '%s\n' "tftp" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

require_file() {
  [ -f "$1" ] || fail "missing file: $1"
}

require_dir() {
  [ -d "$1" ] || fail "missing directory: $1"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"
}

require_command apt-get
require_command sha256sum

require_dir "$REPO_DIR"
require_dir "$REPO_DIR/pool/main"
require_dir "$REPO_DIR/scripts"
require_dir "$REPO_DIR/manifest"
require_file "$REPO_DIR/Packages"
require_file "$REPO_DIR/Packages.gz"
require_file "$REPO_DIR/Release"
require_file "$REPO_DIR/SHA256SUMS"
require_file "$REPO_DIR/manifest/install-targets.txt"
require_file "$REPO_DIR/manifest/all-deb-packages.tsv"
require_file "$REPO_DIR/manifest/install-scripts.tsv"
require_file "$DISC_IMAGE"
require_file "$DISC_IMAGE_SHA256"

echo "Verifying disc image checksum..."
(cd "$(dirname "$DISC_IMAGE_SHA256")" && sha256sum -c "$(basename "$DISC_IMAGE_SHA256")")

echo "Checking repository metadata is portable..."
if grep -Eq '^Filename: /' "$REPO_DIR/Packages"; then
  fail "Packages index contains absolute Filename paths"
fi

deb_count="$(find "$REPO_DIR/pool/main" -type f -name '*.deb' | wc -l | awk '{print $1}')"
package_count="$(grep -c '^Package: ' "$REPO_DIR/Packages")"
manifest_count="$(wc -l <"$REPO_DIR/manifest/all-deb-packages.tsv" | awk '{print $1}')"

[ "$deb_count" = "$package_count" ] || fail "deb count ($deb_count) does not match Packages entries ($package_count)"
[ "$deb_count" = "$manifest_count" ] || fail "deb count ($deb_count) does not match manifest entries ($manifest_count)"

echo "Checking install targets and per-package scripts..."
while read -r package_name; do
  [ -n "$package_name" ] || continue
  script_name="$(script_name_for_package "$package_name")"
  require_file "$REPO_DIR/scripts/install-$script_name.sh"
  [ -x "$REPO_DIR/scripts/install-$script_name.sh" ] || fail "script is not executable: scripts/install-$script_name.sh"
  require_file "$REPO_DIR/manifest/package-dependencies/$script_name.txt"
done <"$REPO_DIR/manifest/install-targets.txt"

require_file "$REPO_DIR/scripts/install-all.sh"
[ -x "$REPO_DIR/scripts/install-all.sh" ] || fail "script is not executable: scripts/install-all.sh"

echo "Running no-install APT simulation from the standalone repository..."
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/lists/partial" "$tmp_dir/cache/partial"
: >"$tmp_dir/status"
printf 'deb [trusted=yes] file:%s ./\n' "$REPO_DIR" >"$tmp_dir/sources.list"

apt_opts=(
  -o "Dir::Etc::sourcelist=$tmp_dir/sources.list"
  -o "Dir::Etc::sourceparts=-"
  -o "Dir::State::lists=$tmp_dir/lists"
  -o "Dir::State::status=$tmp_dir/status"
  -o "Dir::Cache::archives=$tmp_dir/cache"
  -o "Dir::Cache::pkgcache=$tmp_dir/pkgcache.bin"
  -o "Dir::Cache::srcpkgcache=$tmp_dir/srcpkgcache.bin"
  -o "Debug::NoLocking=1"
)

apt-get "${apt_opts[@]}" update >/dev/null
apt-get "${apt_opts[@]}" --simulate --no-install-recommends install $(tr '\n' ' ' <"$REPO_DIR/manifest/install-targets.txt") >/dev/null

echo "Pre-burn verification passed."
echo "Repository: $REPO_DIR"
echo "Disc image: $DISC_IMAGE"
echo "Install targets: $(wc -l <"$REPO_DIR/manifest/install-targets.txt" | awk '{print $1}')"
echo "Bundled debs: $deb_count"
