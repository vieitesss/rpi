#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/lib/restic.sh"

# List all available restic snapshots for an app.
restic_cli_list "$0" "$@"
