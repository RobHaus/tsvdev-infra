#!/usr/bin/env bash
# Install nginx site configs and snippets from this repo.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_SITES="$ROOT/nginx/sites-available"
SRC_SNIPPETS="$ROOT/nginx/snippets"
DST_SITES="/etc/nginx/sites-available"
DST_ENABLED="/etc/nginx/sites-enabled"
DST_SNIPPETS="/etc/nginx/snippets"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

install -d -m 755 "$DST_SITES" "$DST_ENABLED" "$DST_SNIPPETS"

if [[ -f "$SRC_SNIPPETS/proxy-params.conf" ]]; then
  install -m 644 "$SRC_SNIPPETS/proxy-params.conf" "$DST_SNIPPETS/tsvdev-proxy-params.conf"
fi

shopt -s nullglob
for conf in "$SRC_SITES"/*.conf; do
  base="$(basename "$conf")"
  install -m 644 "$conf" "$DST_SITES/$base"
  ln -sfn "$DST_SITES/$base" "$DST_ENABLED/$base"
  echo "enabled $base"
done

nginx -t
systemctl reload nginx
echo "nginx applied"
