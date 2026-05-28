#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODENAME="${CODENAME:-trixie}"
ARCH="${ARCH:-amd64}"
OUTPUT_NAME="${OUTPUT_NAME:-site2-standalone-disc-repository-$CODENAME-$ARCH}"
BUILD_ROOT="${BUILD_ROOT:-$ROOT_DIR/build/offline-package-management}"
DISC_IMAGE="${DISC_IMAGE:-$BUILD_ROOT/$OUTPUT_NAME.iso}"
BURN_DEVICE="${BURN_DEVICE:-/dev/sr0}"

if ! command -v xorriso >/dev/null 2>&1; then
  echo "xorriso is required. Install it with: sudo apt install xorriso" >&2
  exit 1
fi

if [ ! -f "$DISC_IMAGE" ]; then
  echo "Disc image not found: $DISC_IMAGE" >&2
  echo "Build it first with: ./scripts/offline-package-management/build-standalone-disc-repository.sh" >&2
  exit 1
fi

echo "About to burn standalone disc repository image:"
echo "  Image:  $DISC_IMAGE"
echo "  Device: $BURN_DEVICE"
echo
read -r -p "Continue? Type YES to burn: " answer

if [ "$answer" != "YES" ]; then
  echo "Burn cancelled."
  exit 1
fi

xorriso -as cdrecord \
  -v \
  dev="$BURN_DEVICE" \
  blank=as_needed \
  "$DISC_IMAGE"

echo "Burn complete."
