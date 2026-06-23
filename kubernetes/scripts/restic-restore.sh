#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/lib/restic.sh"

# Restore PVCs from restic backup.
restic_cli_restore "$0" "$@"
