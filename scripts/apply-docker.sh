#!/usr/bin/env bash
# Install /etc/docker/daemon.json from this repo and reload Docker if changed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/docker/daemon.json"
DST="/etc/docker/daemon.json"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

install -d -m 755 /etc/docker

if [[ -f "$DST" ]] && cmp -s "$SRC" "$DST"; then
  echo "daemon.json unchanged"
  exit 0
fi

install -m 644 "$SRC" "$DST"
systemctl reload docker || systemctl restart docker
echo "daemon.json applied"
