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

shopt -s nullglob

# /etc/nginx/snippets is shared with the distribution and with certbot, so
# everything from this repo lands under a tsvdev- prefix.
for snippet in "$SRC_SNIPPETS"/*.conf; do
  base="$(basename "$snippet")"
  install -m 644 "$snippet" "$DST_SNIPPETS/tsvdev-$base"
  echo "snippet tsvdev-$base"
done

for conf in "$SRC_SITES"/*.conf; do
  base="$(basename "$conf")"
  install -m 644 "$conf" "$DST_SITES/$base"
  ln -sfn "$DST_SITES/$base" "$DST_ENABLED/$base"
  echo "enabled $base"
done

nginx -t
systemctl reload nginx
echo "nginx applied"
