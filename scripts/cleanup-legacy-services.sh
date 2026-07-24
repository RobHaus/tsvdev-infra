#!/usr/bin/env bash
# Remove retired services from the host: apk-portal, wartime, bbiw*.
# Project directories under /home/rob should already be deleted by the operator.
# Requires root.
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

SITES=(
  tsvdev.com.conf
  wartime.tsvdev.com.conf
  bbiw.tsvdev.com.conf
  bbiw_dev.tsvdev.com.conf
  bbiw.com.au.conf
)

echo "==> Disabling nginx sites"
for s in "${SITES[@]}"; do
  rm -f "/etc/nginx/sites-enabled/$s"
  rm -f "/etc/nginx/sites-available/$s"
  rm -f "/etc/nginx/sites-available/${s}.backup" \
        "/etc/nginx/sites-available/${s}.backup."* 2>/dev/null || true
done
# Extra backups with dated names
rm -f /etc/nginx/sites-available/bbiw.tsvdev.com.conf.backup*
rm -f /etc/nginx/sites-available/_test_write

if [[ -d /etc/nginx ]]; then
  nginx -t
  systemctl reload nginx
fi

echo "==> Deleting Let's Encrypt lineages (if present)"
for lineage in tsvdev.com wartime.tsvdev.com bbiw.tsvdev.com bbiwdev.tsvdev.com bbiw.com.au; do
  if [[ -e "/etc/letsencrypt/live/$lineage" || -e "/etc/letsencrypt/renewal/${lineage}.conf" ]]; then
    certbot delete --cert-name "$lineage" --non-interactive || true
  fi
done

echo "==> Dropping UFW rules for retired game/web ports (best-effort)"
# Delete by matching comment or port; ignore failures if rule absent
ufw status numbered | sed -n 's/^\[\s*\([0-9]\+\)\].*\(8090\|8110\|5432\|5433\).*/\1/p' | sort -rn | while read -r n; do
  ufw --force delete "$n" || true
done
# Explicit deletes commonly used forms
ufw delete allow 8090/tcp 2>/dev/null || true
ufw delete allow 8090/udp 2>/dev/null || true

echo "==> Remaining nginx sites-enabled:"
ls -la /etc/nginx/sites-enabled/ || true
echo "==> Remaining certbot renewals:"
ls /etc/letsencrypt/renewal/ 2>/dev/null || true
ufw status verbose || true
echo "Legacy nginx/certs/UFW cleanup complete."
