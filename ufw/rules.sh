#!/usr/bin/env bash
# Baseline UFW policy for server1.tsvdev.com.
# Idempotent: safe to re-run. Does not remove app-specific game ports.
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

ufw allow 80/tcp comment 'nginx HTTP / ACME'
ufw allow 443/tcp comment 'nginx HTTPS'
ufw allow 46789/tcp comment 'SSH'

# TradeShots game server (managed here as a known host port; app lives elsewhere)
ufw allow 7777/tcp comment 'TradeShots game server'

ufw --force enable
ufw status verbose
