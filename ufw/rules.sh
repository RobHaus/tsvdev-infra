#!/usr/bin/env bash
# Baseline UFW policy for server1.tsvdev.com.
# Idempotent: safe to re-run. Does not remove app-specific game ports.
#
# Web traffic is restricted to Cloudflare. Every name this host serves sits
# behind Cloudflare, so a connection arriving on 80 or 443 from anywhere else
# is one that skipped it, and everything Cloudflare provides (WAF, bot
# handling, rate limiting, absorbing a flood) was optional from the caller's
# point of view. The origin address is not secret and cannot be made secret:
# it is published by every name that is not proxied.
#
# The ranges come from ufw/cloudflare-ranges.txt, regenerated alongside the
# nginx snippet by scripts/update-cloudflare-ips.sh so the firewall and nginx
# cannot disagree about who Cloudflare is.
#
# Two things to know before running this:
#
#   * A name that is not proxied by Cloudflare stops answering. Check the
#     orange cloud in the Cloudflare dashboard first.
#   * If Cloudflare itself is the problem and the site has to be reached
#     directly, ALLOW_DIRECT_WEB=1 opens 80 and 443 to everyone:
#         sudo ALLOW_DIRECT_WEB=1 ./ufw/rules.sh
#     Put it back afterwards by running this again without it.
#
# SSH is on 46789 and is never restricted here, so a mistake in this file
# locks out the web, not the operator.
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RANGES="$ROOT/ufw/cloudflare-ranges.txt"
ALLOW_DIRECT_WEB="${ALLOW_DIRECT_WEB:-0}"

# Read first, change nothing yet. A missing or truncated list must not become
# a firewall that either shuts the site off or opens it up by accident.
web_sources=()
if [[ "$ALLOW_DIRECT_WEB" != "1" ]]; then
  [[ -s "$RANGES" ]] || {
    echo "Missing $RANGES. Run scripts/update-cloudflare-ips.sh, or pass ALLOW_DIRECT_WEB=1." >&2
    exit 1
  }
  while read -r line; do
    line="${line%%#*}"
    line="$(echo "$line" | tr -d '[:space:]')"
    [[ -n "$line" ]] && web_sources+=("$line")
  done < "$RANGES"

  if [[ "${#web_sources[@]}" -lt 15 ]]; then
    echo "Only ${#web_sources[@]} ranges in $RANGES, which is too few to be Cloudflare's list." >&2
    exit 1
  fi
fi

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

if [[ "$ALLOW_DIRECT_WEB" == "1" ]]; then
  echo "ALLOW_DIRECT_WEB=1: opening 80 and 443 to the internet."
  ufw allow 80/tcp comment 'nginx HTTP / ACME (direct, temporary)'
  ufw allow 443/tcp comment 'nginx HTTPS (direct, temporary)'
else
  # ACME renewals are reached through Cloudflare like everything else, which
  # is how diaryiq.com has renewed since it was proxied.
  for cidr in "${web_sources[@]}"; do
    ufw allow proto tcp from "$cidr" to any port 80 comment 'nginx HTTP / ACME (Cloudflare)'
    ufw allow proto tcp from "$cidr" to any port 443 comment 'nginx HTTPS (Cloudflare)'
  done
  echo "Restricted 80 and 443 to ${#web_sources[@]} Cloudflare ranges."
fi

ufw allow 46789/tcp comment 'SSH'

# TradeShots game server (managed here as a known host port; app lives elsewhere)
ufw allow 7777/tcp comment 'TradeShots game server'

ufw --force enable
ufw status verbose
