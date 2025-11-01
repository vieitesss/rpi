#!/bin/bash
set -euo pipefail

# Load backup environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$PROJECT_DIR/.backup.env" ]; then
    source "$PROJECT_DIR/.backup.env"
else
    echo "Error: .backup.env not found. Copy .backup.env.example to .backup.env and configure it."
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

log "=== Starting Full Backup (Docker Volumes + Media + Database) ==="

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
BACKUP_TEMP="/tmp/rpi-full-backup"
rm -rf "$BACKUP_TEMP"
mkdir -p "$BACKUP_TEMP"

# ===========================
# 1. Backup Docker Volumes
# ===========================
log "Discovering Docker volumes..."
VOLUMES=$(docker volume ls -q)

if [ -z "$VOLUMES" ]; then
    log "Warning: No Docker volumes found"
else
    log "Found volumes: $VOLUMES"
    mkdir -p "$BACKUP_TEMP/docker-volumes"

    # Export each volume
    for volume in $VOLUMES; do
        log "Backing up Docker volume: $volume"
        VOLUME_DIR="$BACKUP_TEMP/docker-volumes/$volume"
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

# ===========================
# 2. Backup Media Folder
# ===========================
MEDIA_SOURCE="/media/vieitesrpi/vieitesss/filebrowser"
if [ -d "$MEDIA_SOURCE" ]; then
    log "Backing up media folder: $MEDIA_SOURCE"
    MEDIA_DEST="$BACKUP_TEMP/media-filebrowser"
    mkdir -p "$MEDIA_DEST"

    # Copy with rsync for efficiency
    if command -v rsync &> /dev/null; then
        rsync -a "$MEDIA_SOURCE/" "$MEDIA_DEST/" 2>&1 | tee -a "$LOG_FILE"
    else
        cp -a "$MEDIA_SOURCE/." "$MEDIA_DEST/" 2>&1 | tee -a "$LOG_FILE"
    fi

    SIZE=$(du -sh "$MEDIA_DEST" | cut -f1)
    log "Media folder size: $SIZE"
else
    log "Warning: Media folder not found at $MEDIA_SOURCE"
fi

# ===========================
# 3. Backup Database
# ===========================
DB_SOURCE="$PROJECT_DIR/filebrowser/database.db"
if [ -f "$DB_SOURCE" ]; then
    log "Backing up database: $DB_SOURCE"
    mkdir -p "$BACKUP_TEMP/filebrowser-db"
    cp "$DB_SOURCE" "$BACKUP_TEMP/filebrowser-db/database.db"

    SIZE=$(du -sh "$DB_SOURCE" | cut -f1)
    log "Database size: $SIZE"
else
    log "Warning: Database not found at $DB_SOURCE"
fi

# ===========================
# 4. Create Restic Backup
# ===========================
log "Creating restic snapshot with compression..."

# Restic automatically:
# - Compresses data (enabled by default)
# - Deduplicates chunks (same data stored only once)
# - Only uploads changed chunks (incremental backups)

restic backup "$BACKUP_TEMP" \
    --tag "rpi-full-backup" \
    --tag "automated" \
    --host "raspberry-pi" \
    --exclude-caches \
    --one-file-system 2>&1 | tee -a "$LOG_FILE"

# ===========================
# 5. Cleanup and Stats
# ===========================
log "Cleaning up temporary files..."
rm -rf "$BACKUP_TEMP"

# Show repository statistics
log "Repository statistics:"
restic stats latest --mode raw-data 2>&1 | tee -a "$LOG_FILE" || log "Stats unavailable"

# Apply retention policy
log "Applying retention policy..."
restic forget \
    --tag "rpi-full-backup" \
    --keep-daily "${BACKUP_RETENTION_DAYS:-30}" \
    --keep-weekly "${BACKUP_RETENTION_WEEKS:-8}" \
    --keep-monthly "${BACKUP_RETENTION_MONTHS:-12}" \
    --prune 2>&1 | tee -a "$LOG_FILE"

# Verify backup integrity (weekly on days divisible by 7)
if [ $(($(date +%d) % 7)) -eq 0 ]; then
    log "Running weekly backup verification..."
    restic check --read-data-subset=5% 2>&1 | tee -a "$LOG_FILE"
fi

log "=== Full backup completed successfully ==="

# Show final repository size to monitor B2 usage
log "Checking total repository size..."
restic stats --mode restore-size 2>&1 | tee -a "$LOG_FILE" || log "Size check unavailable"

# Clean up old log files (keep last 30 days)
find "$PROJECT_DIR/logs" -name "backup-*.log" -mtime +30 -delete

exit 0
