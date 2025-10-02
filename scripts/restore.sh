#!/bin/bash
set -euo pipefail

# Load backup environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$PROJECT_DIR/backup.env" ]; then
    source "$PROJECT_DIR/backup.env"
else
    echo "Error: backup.env not found"
    exit 1
fi

export B2_ACCOUNT_ID
export B2_ACCOUNT_KEY
export RESTIC_REPOSITORY
export RESTIC_PASSWORD

echo "=== Restic Restore Tool ==="
echo ""
echo "Available snapshots:"
restic snapshots

echo ""
echo "Usage examples:"
echo "  1. List snapshots:        restic snapshots"
echo "  2. Restore latest:        restic restore latest --target /path/to/restore"
echo "  3. Restore specific:      restic restore SNAPSHOT_ID --target /path/to/restore"
echo ""
echo "To restore a Docker volume:"
echo "  1. Stop the container:    docker compose down SERVICE_NAME"
echo "  2. Restore snapshot:      restic restore latest --target /tmp/restore"
echo "  3. Copy to volume:        docker run --rm -v VOLUME_NAME:/target -v /tmp/restore/VOLUME_NAME:/source alpine sh -c 'rm -rf /target/* && cp -a /source/. /target/'"
echo "  4. Start container:       docker compose up -d SERVICE_NAME"
echo ""
