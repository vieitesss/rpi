#!/bin/bash
set -euo pipefail

# Load backup environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$PROJECT_DIR/.backup.env" ]; then
    source "$PROJECT_DIR/.backup.env"
else
    echo "Error: .backup.env not found"
    exit 1
fi

export B2_ACCOUNT_ID B2_ACCOUNT_KEY RESTIC_REPOSITORY RESTIC_PASSWORD

# Configuration
RESTORE_TEMP="/tmp/restore"
BACKUP_PATH_IN_SNAPSHOT="home/vieitesrpi/rpi/.backup-temp"  # Path as stored in restic
MEDIA_PATH="${BACKUP_MEDIA_PATH:-/media/vieitesrpi/vieitesss/filebrowser}"
DB_PATH="$PROJECT_DIR/filebrowser/database.db"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

cleanup() {
    if [ -d "$RESTORE_TEMP" ]; then
        log "Cleaning up temporary files..."
        rm -rf "$RESTORE_TEMP" 2>/dev/null || true
    fi
}

trap cleanup EXIT

list_snapshots() {
    log "Available snapshots:"
    echo ""
    restic snapshots --compact
    echo ""
    info "Use snapshot ID or 'latest' to restore"
}

get_snapshot_id() {
    local snapshot="${1:-latest}"

    if [ "$snapshot" = "latest" ]; then
        echo "latest"
    else
        # Validate snapshot ID exists
        if restic snapshots --json | grep -qE "(\"id\":\"$snapshot\"|\"short_id\":\"$snapshot\")"; then
            echo "$snapshot"
        else
            error "Snapshot ID '$snapshot' not found"
            exit 1
        fi
    fi
}

restore_snapshot() {
    local snapshot="$1"

    log "Restoring snapshot $snapshot to $RESTORE_TEMP..."
    mkdir -p "$RESTORE_TEMP"

    if ! restic restore "$snapshot" --target "$RESTORE_TEMP"; then
        error "Failed to restore snapshot"
        exit 1
    fi

    log "Snapshot restored successfully"
}

list_volumes_in_backup() {
    local snapshot="${1:-latest}"

    log "Discovering volumes in snapshot..."
    mkdir -p "$RESTORE_TEMP"

    if ! restic restore "$snapshot" --target "$RESTORE_TEMP" 2>/dev/null; then
        error "Failed to restore snapshot"
        exit 1
    fi

    if [ -d "$RESTORE_TEMP/$BACKUP_PATH_IN_SNAPSHOT/docker-volumes" ]; then
        echo ""
        info "Available volumes in backup:"
        ls -1 "$RESTORE_TEMP/$BACKUP_PATH_IN_SNAPSHOT/docker-volumes"
        echo ""
    else
        warn "No docker-volumes directory found. This may be an old backup (pre-Nov 2025)"
        return 1
    fi
}

restore_docker_volume() {
    local volume_name="$1"
    local snapshot="${2:-latest}"
    local service_name="${3:-}"

    log "Restoring Docker volume: $volume_name"

    # Stop service if specified
    if [ -n "$service_name" ]; then
        log "Stopping service: $service_name"
        docker compose stop "$service_name" || warn "Service may not be running"
    fi

    # Restore snapshot
    restore_snapshot "$snapshot"

    # Verify volume exists in backup
    local volume_path="$RESTORE_TEMP/$BACKUP_PATH_IN_SNAPSHOT/docker-volumes/$volume_name"
    if [ ! -d "$volume_path" ]; then
        error "Volume $volume_name not found in backup"
        error "Available volumes:"
        ls -1 "$RESTORE_TEMP/$BACKUP_PATH_IN_SNAPSHOT/docker-volumes" 2>/dev/null || echo "None"
        exit 1
    fi

    # Check if volume has data
    if [ -z "$(ls -A "$volume_path")" ]; then
        warn "Volume $volume_name is empty in backup!"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    # Copy to Docker volume
    log "Copying data to Docker volume: $volume_name"
    if ! docker run --rm \
        -v "$volume_name:/target" \
        -v "$volume_path:/source:ro" \
        alpine sh -c 'rm -rf /target/* /target/..?* /target/.[!.]* 2>/dev/null || true && cp -a /source/. /target/'; then
        error "Failed to copy data to volume"
        exit 1
    fi

    log "Volume restored successfully: $volume_name"

    # Restart service if specified
    if [ -n "$service_name" ]; then
        log "Starting service: $service_name"
        docker compose start "$service_name"
        sleep 2
        log "Service logs:"
        docker logs "$service_name" --tail 10 2>&1 || docker compose logs "$service_name" --tail 10
    fi
}

restore_all_volumes() {
    local snapshot="${1:-latest}"

    log "Restoring all Docker volumes"

    # Stop all services
    log "Stopping all services..."
    docker compose down

    # Restore snapshot
    restore_snapshot "$snapshot"

    # Get list of volumes
    local volumes_dir="$RESTORE_TEMP/$BACKUP_PATH_IN_SNAPSHOT/docker-volumes"
    if [ ! -d "$volumes_dir" ]; then
        error "No docker-volumes directory found in backup"
        exit 1
    fi

    # Restore each volume
    for volume_path in "$volumes_dir"/*; do
        if [ -d "$volume_path" ]; then
            local volume_name=$(basename "$volume_path")
            log "Restoring volume: $volume_name"

            if ! docker run --rm \
                -v "$volume_name:/target" \
                -v "$volume_path:/source:ro" \
                alpine sh -c 'rm -rf /target/* /target/..?* /target/.[!.]* 2>/dev/null || true && cp -a /source/. /target/'; then
                error "Failed to restore volume: $volume_name"
            else
                info "✓ Restored: $volume_name"
            fi
        fi
    done

    log "All volumes restored"
    log "Starting services..."
    docker compose up -d

    sleep 3
    log "Service status:"
    docker compose ps
}

restore_media() {
    local snapshot="${1:-latest}"
    local mode="${2:-merge}"

    log "Restoring media folder"

    # Restore snapshot
    restore_snapshot "$snapshot"

    # Verify media folder exists in backup
    local media_backup="$RESTORE_TEMP/$BACKUP_PATH_IN_SNAPSHOT/media-filebrowser"
    if [ ! -d "$media_backup" ]; then
        error "Media folder not found in backup"
        exit 1
    fi

    # Create target directory if it doesn't exist
    mkdir -p "$MEDIA_PATH"

    # Restore based on mode
    if [ "$mode" = "overwrite" ]; then
        warn "Overwrite mode: Existing files not in backup will be DELETED"
        read -p "Are you sure? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
        log "Restoring media (overwrite mode)..."
        rsync -av --delete "$media_backup/" "$MEDIA_PATH/"
    else
        log "Restoring media (merge mode)..."
        rsync -av "$media_backup/" "$MEDIA_PATH/"
    fi

    log "Media folder restored successfully"
    log "Total size: $(du -sh "$MEDIA_PATH" | cut -f1)"
}

restore_database() {
    local snapshot="${1:-latest}"

    log "Restoring filebrowser database"

    # Stop filebrowser
    log "Stopping filebrowser service..."
    docker compose stop filebrowser || warn "Filebrowser may not be running"

    # Backup existing database
    if [ -f "$DB_PATH" ]; then
        local backup_name="$DB_PATH.backup-$(date +%Y%m%d-%H%M%S)"
        log "Backing up current database to: $backup_name"
        cp "$DB_PATH" "$backup_name"
    fi

    # Restore snapshot
    restore_snapshot "$snapshot"

    # Verify database exists in backup
    local db_backup="$RESTORE_TEMP/$BACKUP_PATH_IN_SNAPSHOT/filebrowser-db/database.db"
    if [ ! -f "$db_backup" ]; then
        error "Database not found in backup"
        exit 1
    fi

    # Copy database
    log "Copying database..."
    mkdir -p "$(dirname "$DB_PATH")"
    cp "$db_backup" "$DB_PATH"

    log "Database restored successfully"

    # Restart filebrowser
    log "Starting filebrowser service..."
    docker compose start filebrowser
    sleep 2
    docker compose logs filebrowser --tail 10
}

interactive_restore() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║    Restic Backup Restore Tool          ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "Select restore operation:"
    echo ""
    echo "  1) List available snapshots"
    echo "  2) Restore single Docker volume"
    echo "  3) Restore all Docker volumes"
    echo "  4) Restore media folder (merge)"
    echo "  5) Restore media folder (overwrite)"
    echo "  6) Restore filebrowser database"
    echo "  7) List volumes in backup"
    echo "  0) Exit"
    echo ""
    read -p "Enter choice [0-7]: " choice

    case $choice in
        1)
            list_snapshots
            ;;
        2)
            list_snapshots
            echo ""
            read -p "Enter snapshot ID (or 'latest'): " snapshot_id
            snapshot_id=$(get_snapshot_id "$snapshot_id")

            list_volumes_in_backup "$snapshot_id"
            read -p "Enter volume name: " volume_name
            read -p "Enter service name (optional, e.g., vaultwarden): " service_name

            restore_docker_volume "$volume_name" "$snapshot_id" "$service_name"
            ;;
        3)
            list_snapshots
            echo ""
            read -p "Enter snapshot ID (or 'latest'): " snapshot_id
            snapshot_id=$(get_snapshot_id "$snapshot_id")

            warn "This will stop all services and restore all volumes"
            read -p "Continue? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                restore_all_volumes "$snapshot_id"
            fi
            ;;
        4)
            list_snapshots
            echo ""
            read -p "Enter snapshot ID (or 'latest'): " snapshot_id
            snapshot_id=$(get_snapshot_id "$snapshot_id")

            restore_media "$snapshot_id" "merge"
            ;;
        5)
            list_snapshots
            echo ""
            read -p "Enter snapshot ID (or 'latest'): " snapshot_id
            snapshot_id=$(get_snapshot_id "$snapshot_id")

            restore_media "$snapshot_id" "overwrite"
            ;;
        6)
            list_snapshots
            echo ""
            read -p "Enter snapshot ID (or 'latest'): " snapshot_id
            snapshot_id=$(get_snapshot_id "$snapshot_id")

            restore_database "$snapshot_id"
            ;;
        7)
            list_snapshots
            echo ""
            read -p "Enter snapshot ID (or 'latest'): " snapshot_id
            snapshot_id=$(get_snapshot_id "$snapshot_id")

            list_volumes_in_backup "$snapshot_id"
            ;;
        0)
            log "Exiting"
            exit 0
            ;;
        *)
            error "Invalid choice"
            exit 1
            ;;
    esac
}

# Parse command line arguments
case "${1:-}" in
    list|ls)
        list_snapshots
        ;;
    volume)
        if [ $# -lt 2 ]; then
            error "Usage: $0 volume <volume-name> [snapshot-id] [service-name]"
            exit 1
        fi
        restore_docker_volume "$2" "${3:-latest}" "${4:-}"
        ;;
    all-volumes)
        restore_all_volumes "${2:-latest}"
        ;;
    media)
        restore_media "${2:-latest}" "${3:-merge}"
        ;;
    database|db)
        restore_database "${2:-latest}"
        ;;
    list-volumes)
        list_volumes_in_backup "${2:-latest}"
        ;;
    -h|--help|help)
        echo "Usage: $0 [command] [options]"
        echo ""
        echo "Commands:"
        echo "  list, ls                           List available snapshots"
        echo "  volume <name> [snapshot] [service] Restore single Docker volume"
        echo "  all-volumes [snapshot]             Restore all Docker volumes"
        echo "  media [snapshot] [mode]            Restore media folder (mode: merge|overwrite)"
        echo "  database, db [snapshot]            Restore filebrowser database"
        echo "  list-volumes [snapshot]            List volumes in backup"
        echo "  help, -h, --help                   Show this help"
        echo ""
        echo "Examples:"
        echo "  $0                                 Interactive mode"
        echo "  $0 list                            List snapshots"
        echo "  $0 volume rpi_vaultwarden-data     Restore vaultwarden volume"
        echo "  $0 volume rpi_vaultwarden-data latest vaultwarden"
        echo "  $0 all-volumes                     Restore all volumes from latest"
        echo "  $0 media                           Restore media (merge mode)"
        echo "  $0 media latest overwrite          Restore media (overwrite mode)"
        echo "  $0 database                        Restore filebrowser database"
        echo ""
        ;;
    "")
        interactive_restore
        ;;
    *)
        error "Unknown command: $1"
        echo "Run '$0 --help' for usage information"
        exit 1
        ;;
esac

log "Done!"
