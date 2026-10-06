#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source .env

if [[ -n "${NTFY:-}" ]]; then
  curl -fsS \
    -H "Title: 🛑 Raspberry Pi shutting down" \
    -H "Tags: warning" \
    -d "Shutdown requested on $(hostname)" \
    "https://ntfy.sh/${NTFY}" >/dev/null || true
fi

shutdown -h now
