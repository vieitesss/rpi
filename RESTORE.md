# Backup Restore Guide

Complete guide for restoring backups from Backblaze B2 using Restic.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Listing Available Backups](#listing-available-backups)
- [Restore Scenarios](#restore-scenarios)
  - [Restore a Single Docker Volume](#restore-a-single-docker-volume)
  - [Restore All Docker Volumes](#restore-all-docker-volumes)
  - [Restore Media Folder](#restore-media-folder)
  - [Restore Filebrowser Database](#restore-filebrowser-database)
  - [Full System Restore](#full-system-restore)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

1. **Backup credentials configured** - Ensure `.backup.env` exists with correct B2 credentials
2. **Docker running** - Services should be stopped before restoring their volumes
3. **Sufficient disk space** - At least 2x the backup size for temporary extraction

---

## Listing Available Backups

### View all snapshots
```bash
just bl
# OR
source .backup.env && export B2_ACCOUNT_ID B2_ACCOUNT_KEY RESTIC_REPOSITORY RESTIC_PASSWORD && restic snapshots
```

**Output example:**
```
ID        Time                 Host          Tags                       Paths
-----------------------------------------------------------------------------------------------
062715bd  2025-11-01 19:58:36  raspberry-pi  rpi-full-backup,automated  /tmp/rpi-full-backup
e4c13038  2025-11-04 14:57:48  raspberry-pi  rpi-full-backup,automated  /tmp/rpi-full-backup
```

### Inspect a specific snapshot
```bash
source .backup.env && export B2_ACCOUNT_ID B2_ACCOUNT_KEY RESTIC_REPOSITORY RESTIC_PASSWORD && restic ls <SNAPSHOT_ID>

# Example: List contents of latest backup
source .backup.env && export B2_ACCOUNT_ID B2_ACCOUNT_KEY RESTIC_REPOSITORY RESTIC_PASSWORD && restic ls latest
```

### Find a specific volume in backups
```bash
source .backup.env && export B2_ACCOUNT_ID B2_ACCOUNT_KEY RESTIC_REPOSITORY RESTIC_PASSWORD && restic ls <SNAPSHOT_ID> | grep vaultwarden
```

---

## Restore Scenarios

### Restore a Single Docker Volume

**Use case:** Restore a specific volume (e.g., vaultwarden data was accidentally deleted)

**Steps:**

1. **Stop the service using the volume:**
   ```bash
   docker compose stop vaultwarden
   ```

2. **Restore backup to temporary location:**
   ```bash
   mkdir -p /tmp/restore
   source .backup.env && export B2_ACCOUNT_ID B2_ACCOUNT_KEY RESTIC_REPOSITORY RESTIC_PASSWORD
   restic restore latest --target /tmp/restore
   ```

   > **Note:** Replace `latest` with a specific snapshot ID (e.g., `062715bd`) if needed

3. **Copy restored data to Docker volume:**
   ```bash
   # For vaultwarden-data volume:
   docker run --rm \
     -v rpi_vaultwarden-data:/target \
     -v /tmp/restore/tmp/rpi-full-backup/docker-volumes/rpi_vaultwarden-data:/source \
     alpine sh -c 'rm -rf /target/* && cp -a /source/. /target/'
   ```

   **Generic template:**
   ```bash
   docker run --rm \
     -v <VOLUME_NAME>:/target \
     -v /tmp/restore/tmp/rpi-full-backup/docker-volumes/<VOLUME_NAME>:/source \
     alpine sh -c 'rm -rf /target/* && cp -a /source/. /target/'
   ```

4. **Restart the service:**
   ```bash
   docker compose start vaultwarden
   ```

5. **Verify service is working:**
   ```bash
   docker logs vaultwarden --tail 20
   ```

6. **Clean up:**
   ```bash
   rm -rf /tmp/restore
   ```

---

### Restore All Docker Volumes

**Use case:** System failure, need to restore all services

**Steps:**

1. **Stop all services:**
   ```bash
   just down
   # OR
   docker compose down
   ```

2. **Restore backup:**
   ```bash
   mkdir -p /tmp/restore
   source .backup.env && export B2_ACCOUNT_ID B2_ACCOUNT_KEY RESTIC_REPOSITORY RESTIC_PASSWORD
   restic restore latest --target /tmp/restore
   ```

3. **List available volumes in backup:**
   ```bash
   ls /tmp/restore/tmp/rpi-full-backup/docker-volumes/
   ```

4. **Restore each volume:**
   ```bash
   # For each volume, run:
   VOLUME_NAME="rpi_vaultwarden-data"
   docker run --rm \
     -v ${VOLUME_NAME}:/target \
     -v /tmp/restore/tmp/rpi-full-backup/docker-volumes/${VOLUME_NAME}:/source \
     alpine sh -c 'rm -rf /target/* && cp -a /source/. /target/'
   ```

5. **Restart services:**
   ```bash
   just up -d
   ```

6. **Clean up:**
   ```bash
   rm -rf /tmp/restore
   ```

---

### Restore Media Folder

**Use case:** Accidentally deleted files from media folder

**Steps:**

1. **Restore backup:**
   ```bash
   mkdir -p /tmp/restore
   source .backup.env && export B2_ACCOUNT_ID B2_ACCOUNT_KEY RESTIC_REPOSITORY RESTIC_PASSWORD
   restic restore latest --target /tmp/restore
   ```

2. **Copy media folder:**
   ```bash
   # Full restore (overwrites existing):
   rsync -av --delete /tmp/restore/tmp/rpi-full-backup/media-filebrowser/ /media/vieitesrpi/vieitesss/filebrowser/

   # OR merge with existing files:
   rsync -av /tmp/restore/tmp/rpi-full-backup/media-filebrowser/ /media/vieitesrpi/vieitesss/filebrowser/
   ```

   > **Note:** `--delete` removes files not in backup. Omit for merge mode.

3. **Verify files:**
   ```bash
   ls -lah /media/vieitesrpi/vieitesss/filebrowser/
   ```

4. **Clean up:**
   ```bash
   rm -rf /tmp/restore
   ```

---

### Restore Filebrowser Database

**Use case:** Filebrowser database corrupted

**Steps:**

1. **Stop filebrowser:**
   ```bash
   docker compose stop filebrowser
   ```

2. **Restore backup:**
   ```bash
   mkdir -p /tmp/restore
   source .backup.env && export B2_ACCOUNT_ID B2_ACCOUNT_KEY RESTIC_REPOSITORY RESTIC_PASSWORD
   restic restore latest --target /tmp/restore
   ```

3. **Copy database:**
   ```bash
   cp /tmp/restore/tmp/rpi-full-backup/filebrowser-db/database.db filebrowser/database.db
   ```

4. **Restart filebrowser:**
   ```bash
   docker compose start filebrowser
   ```

5. **Clean up:**
   ```bash
   rm -rf /tmp/restore
   ```

---

### Full System Restore

**Use case:** Complete system failure, restoring to new Raspberry Pi or fresh install

**Steps:**

1. **Install prerequisites:**
   ```bash
   # Install Docker
   curl -fsSL https://get.docker.com | sh
   sudo usermod -aG docker $USER

   # Install restic
   sudo apt update && sudo apt install restic -y
   ```

2. **Clone repository:**
   ```bash
   git clone <your-repo-url> ~/rpi
   cd ~/rpi
   ```

3. **Configure backup credentials:**
   ```bash
   cp backup.env.example .backup.env
   nano .backup.env  # Add your B2 credentials
   ```

4. **List available backups:**
   ```bash
   source .backup.env && export B2_ACCOUNT_ID B2_ACCOUNT_KEY RESTIC_REPOSITORY RESTIC_PASSWORD
   restic snapshots
   ```

5. **Choose and restore a snapshot:**
   ```bash
   # Use latest or specific snapshot ID
   SNAPSHOT_ID="latest"
   mkdir -p /tmp/restore
   restic restore $SNAPSHOT_ID --target /tmp/restore
   ```

6. **Create Docker volumes (if they don't exist):**
   ```bash
   docker volume create rpi_vaultwarden-data
   docker volume create rpi_vaultwarden-ts
   docker volume create rpi_filebrowser-ts
   ```

7. **Restore Docker volumes:**
   ```bash
   for volume in rpi_vaultwarden-data rpi_vaultwarden-ts rpi_filebrowser-ts; do
     echo "Restoring $volume..."
     docker run --rm \
       -v ${volume}:/target \
       -v /tmp/restore/tmp/rpi-full-backup/docker-volumes/${volume}:/source \
       alpine sh -c 'rm -rf /target/* && cp -a /source/. /target/'
   done
   ```

8. **Restore media folder:**
   ```bash
   sudo mkdir -p /media/vieitesrpi/vieitesss/filebrowser
   sudo rsync -av /tmp/restore/tmp/rpi-full-backup/media-filebrowser/ /media/vieitesrpi/vieitesss/filebrowser/
   ```

9. **Restore filebrowser database:**
   ```bash
   mkdir -p filebrowser
   cp /tmp/restore/tmp/rpi-full-backup/filebrowser-db/database.db filebrowser/database.db
   ```

10. **Configure environment:**
    ```bash
    cp example.env .env
    nano .env  # Add Tailscale key and other credentials
    ```

11. **Start services:**
    ```bash
    docker compose up -d
    ```

12. **Verify services:**
    ```bash
    docker ps
    docker logs vaultwarden --tail 20
    docker logs rpi-filebrowser-1 --tail 20
    ```

13. **Clean up:**
    ```bash
    rm -rf /tmp/restore
    ```

---

## Troubleshooting

### Issue: "Permission denied" when accessing restored files

**Cause:** Ownership/permissions mismatch after restore

**Solution:**
```bash
# For Docker volumes - use Alpine container to fix permissions:
docker run --rm -v rpi_vaultwarden-data:/data alpine chmod -R a+rX /data

# For media folder:
sudo chown -R vieitesrpi:vieitesrpi /media/vieitesrpi/vieitesss/filebrowser
sudo chmod -R 755 /media/vieitesrpi/vieitesss/filebrowser
```

---

### Issue: "No snapshot found" error

**Cause:** Wrong snapshot ID or credentials issue

**Solution:**
```bash
# Verify credentials are loaded:
echo $RESTIC_REPOSITORY

# If empty, reload:
source .backup.env && export B2_ACCOUNT_ID B2_ACCOUNT_KEY RESTIC_REPOSITORY RESTIC_PASSWORD

# List all snapshots to get correct ID:
restic snapshots
```

---

### Issue: Volume already in use

**Cause:** Service still running with volume mounted

**Solution:**
```bash
# Stop specific service:
docker compose stop <service-name>

# OR stop all services:
docker compose down

# Then retry restore
```

---

### Issue: WAL checkpoint needed for SQLite databases

**Cause:** SQLite database with Write-Ahead Log files not merged

**Solution:**
```bash
# After restoring, checkpoint the database:
docker run --rm -v /tmp/restore/tmp/rpi-full-backup/docker-volumes/rpi_vaultwarden-data:/data alpine sh -c \
  'apk add --no-cache sqlite && sqlite3 /data/db.sqlite3 "PRAGMA wal_checkpoint(TRUNCATE);"'

# Then copy to volume:
docker run --rm \
  -v rpi_vaultwarden-data:/target \
  -v /tmp/restore/tmp/rpi-full-backup/docker-volumes/rpi_vaultwarden-data:/source \
  alpine sh -c 'rm -rf /target/* && cp -a /source/. /target/'
```

---

### Issue: Backup is from old script (October 2025 or earlier)

**Cause:** Old backup script had empty volume directories

**Symptoms:** Restored volumes are empty even though backup succeeded

**Solution:**
```bash
# Only use backups from November 1st, 2025 or later:
source .backup.env && export B2_ACCOUNT_ID B2_ACCOUNT_KEY RESTIC_REPOSITORY RESTIC_PASSWORD
restic snapshots --tag rpi-full-backup

# Use snapshots with tag "rpi-full-backup" only
```

---

## Quick Reference Commands

```bash
# List backups
just bl

# Restore latest to temp
mkdir -p /tmp/restore && source .backup.env && export B2_ACCOUNT_ID B2_ACCOUNT_KEY RESTIC_REPOSITORY RESTIC_PASSWORD && restic restore latest --target /tmp/restore

# Copy volume to Docker
docker run --rm -v <VOLUME>:/target -v /tmp/restore/tmp/rpi-full-backup/docker-volumes/<VOLUME>:/source alpine sh -c 'rm -rf /target/* && cp -a /source/. /target/'

# Clean up
rm -rf /tmp/restore
```

---

## Important Notes

1. **Always test restores** - Periodically test your backup restoration process
2. **Stop services first** - Always stop services before restoring their volumes
3. **Check backup date** - Verify the snapshot date matches your expectation
4. **Backup before restore** - If restoring over existing data, back it up first
5. **Use `latest` carefully** - `latest` refers to most recent snapshot, which may not be what you want
6. **Old backups** - Backups before November 1st, 2025 may have empty Docker volumes due to script bug
7. **Verify after restore** - Always check service logs and data after restoration
8. **Clean up temp files** - Remove `/tmp/restore` to free disk space

---

## Additional Resources

- **Restic documentation:** https://restic.readthedocs.io/
- **Backup script:** `scripts/backup.sh`
- **Project docs:** `CLAUDE.md`
- **Justfile commands:** Run `just` to see all available commands
