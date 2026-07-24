#!/usr/bin/env bash
# Reload nginx after successful certificate renewal.
set -euo pipefail
systemctl reload nginx
