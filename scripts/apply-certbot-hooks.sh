#!/usr/bin/env bash
# Install certbot deploy hook to reload nginx after renewals.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/certbot/renewal-hooks/deploy/reload-nginx.sh"
DST_DIR="/etc/letsencrypt/renewal-hooks/deploy"
DST="$DST_DIR/reload-nginx.sh"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

install -d -m 755 "$DST_DIR"
install -m 755 "$SRC" "$DST"
echo "Installed $DST"
