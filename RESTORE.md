# Backup Restore Guide

Complete guide for restoring backups from Backblaze B2 using the automated restore script.

## Quick Start

```bash
# Interactive restore menu (easiest way)
just restore

# List available backups
just restore-list

# Restore vaultwarden volume
just restore-volume rpi_vaultwarden-data latest vaultwarden

# Restore all volumes
just restore-all-volumes

# Restore media folder
just restore-media
```

---

## Table of Contents
- [Prerequisites](#prerequisites)
- [Using the Restore Script](#using-the-restore-script)
- [Common Restore Scenarios](#common-restore-scenarios)
- [Command Reference](#command-reference)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

1. **Backup credentials configured** - `.backup.env` file exists with B2 credentials
2. **Docker running** - Services will be automatically stopped/started
3. **Sufficient disk space** - Temp files automatically cleaned up

---

## Using the Restore Script

The restore script (`scripts/restore.sh`) provides two modes:

### Interactive Mode

Run without arguments to get an interactive menu:

```bash
just restore
# or: just br
# or: bash scripts/restore.sh
```

**Menu options:**
```
1) List available snapshots
2) Restore single Docker volume
3) Restore all Docker volumes
4) Restore media folder (merge)
5) Restore media folder (overwrite)
6) Restore filebrowser database
7) List volumes in backup
0) Exit
```

The script will guide you through:
- Selecting a snapshot
- Choosing what to restore
- Confirming destructive actions
- Automatic service stop/start

### Command-Line Mode

For automation or quick restores, use commands directly:

```bash
bash scripts/restore.sh [command] [options]
```

See [Command Reference](#command-reference) for all available commands.

---

## Common Restore Scenarios

### Restore a Single Docker Volume

**Use case:** Vaultwarden data was deleted or corrupted

```bash
# Interactive mode
just restore
# Select option 2, enter snapshot ID and volume name

# Command-line mode
just restore-volume rpi_vaultwarden-data
# With service auto-restart:
just restore-volume rpi_vaultwarden-data latest vaultwarden
# From specific snapshot:
just restore-volume rpi_vaultwarden-data 062715bd vaultwarden
```

**What happens:**
1. ✅ Service stopped automatically (if specified)
2. ✅ Snapshot downloaded and extracted
3. ✅ Volume validated (warns if empty)
4. ✅ Data copied to Docker volume
5. ✅ Service restarted and logs shown
6. ✅ Temp files cleaned up

---

### Restore All Docker Volumes

**Use case:** System failure, need to restore all services

```bash
# Interactive mode - safest
just restore
# Select option 3

# Command-line mode
just restore-all-volumes
# From specific snapshot:
just restore-all-volumes 062715bd
```

**What happens:**
1. ⚠️ Confirmation prompt (destructive operation)
2. ✅ All services stopped
3. ✅ Snapshot downloaded
4. ✅ Each volume restored with progress
5. ✅ All services restarted
6. ✅ Service status shown

---

### Restore Media Folder

**Use case:** Accidentally deleted files from media folder

**Merge Mode** (keeps existing files):
```bash
just restore-media
# or: just restore-media latest merge
```

**Overwrite Mode** (deletes files not in backup):
```bash
just restore-media latest overwrite
```

⚠️ Overwrite mode prompts for confirmation

---

### Restore Filebrowser Database

**Use case:** Database corrupted or wrong configuration

```bash
just restore-database
# From specific snapshot:
just restore-database 062715bd
```

**What happens:**
1. ✅ Filebrowser stopped
2. ✅ Current database backed up to `database.db.backup-TIMESTAMP`
3. ✅ New database restored
4. ✅ Filebrowser restarted with logs

---

### List Volumes in Backup

**Use case:** Want to see what's available before restoring

```bash
just restore-list-volumes
# From specific snapshot:
just restore-list-volumes 062715bd
```

**Output example:**
```
Available volumes in backup:
rpi_filebrowser-ts
rpi_vaultwarden-data
rpi_vaultwarden-ts
```

---

## Command Reference

### Justfile Commands (Recommended)

```bash
# List operations
just restore-list                           # List all snapshots
just restore-list-volumes [snapshot]        # List volumes in backup

# Restore operations
just restore                                # Interactive menu
just restore-volume <name> [snapshot] [svc] # Restore single volume
just restore-all-volumes [snapshot]         # Restore all volumes
just restore-media [snapshot] [mode]        # Restore media folder
just restore-database [snapshot]            # Restore database
```

### Direct Script Usage

```bash
# Help
bash scripts/restore.sh --help

# List snapshots
bash scripts/restore.sh list

# Restore volume
bash scripts/restore.sh volume <name> [snapshot] [service]
bash scripts/restore.sh volume rpi_vaultwarden-data
bash scripts/restore.sh volume rpi_vaultwarden-data latest vaultwarden

# Restore all volumes
bash scripts/restore.sh all-volumes [snapshot]

# Restore media
bash scripts/restore.sh media [snapshot] [mode]
bash scripts/restore.sh media latest merge
bash scripts/restore.sh media latest overwrite

# Restore database
bash scripts/restore.sh database [snapshot]

# List volumes
bash scripts/restore.sh list-volumes [snapshot]
```

### Snapshot ID Usage

- **`latest`** - Most recent backup (default)
- **Specific ID** - e.g., `062715bd` (first 8 chars of snapshot ID)
- Get IDs with: `just restore-list`

---

## Troubleshooting

### Volume is empty in backup

**Symptom:**
```
[WARNING] Volume rpi_vaultwarden-data is empty in backup!
Continue anyway? (y/N):
```

**Cause:**
- Old backup from before Nov 1, 2025 (script bug)
- Service was never started when backup ran
- Volume legitimately empty

**Solution:**
```bash
# List all snapshots and find a newer one
just restore-list

# Only use backups tagged "rpi-full-backup"
# Backups tagged "rpi-services" may have empty volumes
```

---

### Snapshot not found

**Symptom:**
```
[ERROR] Snapshot ID 'abc123' not found
```

**Solution:**
```bash
# List available snapshots
just restore-list

# Use correct 8-char ID or 'latest'
just restore-volume rpi_vaultwarden-data 062715bd
```

---

### Service already stopped

**Symptom:**
```
[WARNING] Service may not be running
```

**Cause:** Service was already stopped, not an error

**Solution:** Script continues normally, no action needed

---

### Permission denied after restore

**Symptom:** Service logs show permission errors after restore

**Solution:**
```bash
# Fix volume permissions
docker run --rm -v <volume-name>:/data alpine chmod -R a+rX /data

# Example:
docker run --rm -v rpi_vaultwarden-data:/data alpine chmod -R a+rX /data

# Restart service
docker compose restart vaultwarden
```

---

### Restore taking too long

**Cause:** Large backup being downloaded from B2

**Solution:**
- Script shows progress automatically
- Restoration speed depends on:
  - Internet connection speed
  - Backup size
  - Backblaze B2 region
- Be patient, script handles everything

---

### "No docker-volumes directory found"

**Symptom:**
```
[WARNING] No docker-volumes directory found. This may be an old backup (pre-Nov 2025)
```

**Cause:** Backup from before November 1st, 2025 when script was fixed

**Solution:**
```bash
# Only use backups from Nov 1, 2025 or later
just restore-list | grep "rpi-full-backup"

# Look for tag "rpi-full-backup" not "rpi-services"
```

---

## Full System Restore (New Raspberry Pi)

When restoring to a completely new system:

### 1. Install Prerequisites

```bash
# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker

# Install restic
sudo apt update && sudo apt install restic -y

# Install just (optional but recommended)
cargo install just
# or: curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to ~/bin
```

### 2. Clone Repository

```bash
git clone <your-repo-url> ~/rpi
cd ~/rpi
```

### 3. Configure Credentials

```bash
# Backup credentials
cp backup.env.example .backup.env
nano .backup.env
# Add: B2_ACCOUNT_ID, B2_ACCOUNT_KEY, RESTIC_REPOSITORY, RESTIC_PASSWORD

# Service credentials
cp example.env .env
nano .env
# Add: TAILSCALE_AUTH_KEY, etc.
```

### 4. Restore Everything

```bash
# List available backups
just restore-list

# Use interactive restore for safety
just restore

# Or restore all volumes in one command
just restore-all-volumes
```

### 5. Restore Media and Database

```bash
# Restore media folder
sudo mkdir -p /media/vieitesrpi/vieitesss/filebrowser
just restore-media

# Restore database
just restore-database
```

### 6. Verify Services

```bash
docker compose ps
docker compose logs
```

---

## Important Notes

1. ✅ **Always use `just restore-list` first** to see available backups
2. ✅ **Script handles all cleanup** automatically (no manual temp file removal)
3. ✅ **Services auto-stop/start** when service name provided
4. ✅ **Existing data backed up** before database restores
5. ⚠️ **Old backups** (pre-Nov 2025) may have empty Docker volumes
6. ⚠️ **Overwrite mode** deletes files not in backup (use with caution)
7. 💡 **Interactive mode** is safest for beginners
8. 💡 **Command-line mode** is best for automation/scripting

---

## Quick Reference Card

```bash
# MOST COMMON COMMANDS

# Interactive menu (easiest)
just restore

# List backups
just restore-list

# Restore vaultwarden
just restore-volume rpi_vaultwarden-data latest vaultwarden

# Restore filebrowser
just restore-volume rpi_filebrowser-ts latest filebrowser

# Restore everything
just restore-all-volumes

# Restore media (safe merge)
just restore-media

# Check what's in backup
just restore-list-volumes
```

---

## Script Features

### Automatic Features
- ✅ Validates snapshot IDs
- ✅ Stops/starts services
- ✅ Checks for empty volumes
- ✅ Backs up existing databases
- ✅ Shows service logs after restore
- ✅ Cleans up temp files on exit
- ✅ Detects old/incompatible backups
- ✅ Colored output for readability
- ✅ Progress indication

### Safety Features
- ⚠️ Confirmation prompts for destructive actions
- ⚠️ Warns about empty volumes
- ⚠️ Validates volume exists in backup
- ⚠️ Read-only mounts for source data
- ⚠️ Automatic database backup before restore

---

## Additional Resources

- **Interactive help:** `just restore` (select option 1)
- **Command help:** `bash scripts/restore.sh --help`
- **List commands:** `just -l`
- **Project docs:** `CLAUDE.md`
- **Backup script:** `scripts/backup.sh`
- **Restic docs:** https://restic.readthedocs.io/
