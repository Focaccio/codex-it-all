#!/usr/bin/env bash
set -euo pipefail

if ! command -v apt-mark >/dev/null 2>&1; then
  echo "apt-mark is required; run this on the Debian server you want to model." >&2
  exit 1
fi

apt-mark showmanual | sort
