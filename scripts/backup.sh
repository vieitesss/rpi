#!/bin/bash
set -euo pipefail

# Load backup environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$PROJECT_DIR/backup.env" ]; then
    source "$PROJECT_DIR/backup.env"
else
    echo "Error: backup.env not found. Copy backup.env.example to backup.env and configure it."
    exit 1
fi

# Export B2 credentials for restic
export B2_ACCOUNT_ID
export B2_ACCOUNT_KEY
export RESTIC_REPOSITORY
export RESTIC_PASSWORD

LOG_FILE="$PROJECT_DIR/logs/backup-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$PROJECT_DIR/logs"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "=== Starting Docker Volumes Backup ==="

# Check if restic is installed
if ! command -v restic &> /dev/null; then
    log "Error: restic is not installed. Install it with: sudo apt install restic"
    exit 1
fi

# Initialize repository if it doesn't exist
log "Checking restic repository..."
if ! restic snapshots &> /dev/null; then
    log "Initializing new restic repository..."
    restic init
fi

# Create temporary backup directory in /tmp for clean paths
BACKUP_TEMP="/tmp/rpi-volumes-backup"
rm -rf "$BACKUP_TEMP"
mkdir -p "$BACKUP_TEMP"

# Get list of all docker volumes
log "Discovering Docker volumes..."
VOLUMES=$(docker volume ls -q)

if [ -z "$VOLUMES" ]; then
    log "Warning: No Docker volumes found"
    exit 1
else
    log "Found volumes: $VOLUMES"

    # Export each volume
    for volume in $VOLUMES; do
        log "Backing up volume: $volume"
        VOLUME_DIR="$BACKUP_TEMP/$volume"
        mkdir -p "$VOLUME_DIR"

        # Use a temporary container to copy volume data
        docker run --rm \
            -v "$volume:/source:ro" \
            -v "$VOLUME_DIR:/backup" \
            alpine \
            sh -c "cp -a /source/. /backup/" || {
                log "Warning: Failed to backup volume $volume"
                continue
            }
    done
fi

# Create backup with restic
log "Creating restic snapshot..."
restic backup "$BACKUP_TEMP" \
    --tag "rpi-services" \
    --tag "automated" \
    --host "raspberry-pi" | tee -a "$LOG_FILE"

# Clean up temporary backup
log "Cleaning up temporary files..."
rm -rf "$BACKUP_TEMP"

# Apply retention policy
log "Applying retention policy..."
restic forget \
    --keep-daily "${BACKUP_RETENTION_DAYS:-30}" \
    --keep-weekly "${BACKUP_RETENTION_WEEKS:-8}" \
    --keep-monthly "${BACKUP_RETENTION_MONTHS:-12}" \
    --prune | tee -a "$LOG_FILE"

# Verify backup integrity (occasionally)
if [ $(($(date +%d) % 7)) -eq 0 ]; then
    log "Running weekly backup verification..."
    restic check | tee -a "$LOG_FILE"
fi

log "=== Backup completed successfully ==="

# Clean up old log files (keep last 30 days)
find "$PROJECT_DIR/logs" -name "backup-*.log" -mtime +30 -delete

exit 0
