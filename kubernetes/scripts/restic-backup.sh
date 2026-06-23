#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/lib/restic.sh"

# Manually trigger a backup job for a specific app.
restic_cli_backup "$0" "$@"
