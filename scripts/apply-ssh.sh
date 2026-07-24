#!/usr/bin/env bash
# Install SSH config fragment. Does not restart sshd automatically (avoid lockout).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/ssh/sshd_config.d/99-tsvdev.conf"
DST="/etc/ssh/sshd_config.d/99-tsvdev.conf"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

install -d -m 755 /etc/ssh/sshd_config.d
install -m 644 "$SRC" "$DST"

if sshd -t; then
  echo "Installed $DST — reload when ready: systemctl reload ssh"
else
  echo "WARNING: sshd -t failed; fix $DST before reloading" >&2
  exit 1
fi
