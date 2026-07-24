#!/usr/bin/env bash
# Idempotent apply of all tsvdev-infra managed host configs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

echo "==> Docker daemon.json"
"$ROOT/scripts/apply-docker.sh"

echo "==> nginx sites + snippets"
"$ROOT/scripts/apply-nginx.sh"

echo "==> certbot renew hooks"
"$ROOT/scripts/apply-certbot-hooks.sh"

echo "==> SSH fragment"
"$ROOT/scripts/apply-ssh.sh"

echo "==> UFW baseline"
"$ROOT/ufw/rules.sh"

echo "==> Done. Review: nginx -t; ufw status; ss -tlnp | head"
