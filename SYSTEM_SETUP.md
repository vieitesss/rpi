# System Setup Guide

This guide covers the systemd services, scripts, and system configuration files for automating your Raspberry Pi homelab.

## Table of Contents

- [Systemd Services](#systemd-services)
- [Scripts](#scripts)
- [System Configuration](#system-configuration)

---

## Systemd Services

The `etc/systemd/system/` directory contains systemd service and timer units for automating various tasks.

### 1. Auto-Start Docker Services

**Files:**
- `etc/systemd/system/rpi-services.service`

**Purpose:** Automatically start all Docker services on boot.

**Setup:**
```bash
sudo cp etc/systemd/system/rpi-services.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable rpi-services.service
sudo systemctl start rpi-services.service
```

**Usage:**
```bash
# Check status
sudo systemctl status rpi-services.service

# Start/stop services
sudo systemctl start rpi-services.service
sudo systemctl stop rpi-services.service

# View logs
sudo journalctl -u rpi-services.service -f
```

**Note:** Update the `WorkingDirectory` and `User` in the service file to match your setup if different from `/home/vieitesrpi/rpi`.

---

### 2. Automated Backups

**Files:**
- `etc/systemd/system/rpi-backup.service`
- `etc/systemd/system/rpi-backup.timer`

**Purpose:** Run automated daily backups at 11:00 PM.

**Setup:**
```bash
sudo cp etc/systemd/system/rpi-backup.service /etc/systemd/system/
sudo cp etc/systemd/system/rpi-backup.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable rpi-backup.timer
sudo systemctl start rpi-backup.timer
```

**Usage:**
```bash
# Check timer status
sudo systemctl status rpi-backup.timer
sudo systemctl list-timers | grep rpi-backup

# Manually trigger backup
sudo systemctl start rpi-backup.service

# View backup logs
sudo journalctl -u rpi-backup.service -f
```

**Configuration:**
- Runs daily at 23:00 (11:00 PM)
- Randomized delay of up to 30 minutes to avoid load spikes
- Persistent: runs on next boot if system was off at trigger time

---

### 3. Network Connection Management

**Files:**
- `etc/systemd/system/manage-connection.service`
- `etc/systemd/system/manage-connection.timer`

**Purpose:** Automatically disable WiFi when Ethernet is connected, and enable WiFi when Ethernet is disconnected. Saves power and reduces network interface conflicts.

**Setup:**
```bash
# Copy script to system location
sudo cp scripts/manage-connection.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/manage-connection.sh

# Install systemd units
sudo cp etc/systemd/system/manage-connection.service /etc/systemd/system/
sudo cp etc/systemd/system/manage-connection.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable manage-connection.timer
sudo systemctl start manage-connection.timer
```

**Usage:**
```bash
# Check timer status
sudo systemctl status manage-connection.timer

# Manually trigger check
sudo systemctl start manage-connection.service

# View logs
sudo journalctl -u manage-connection.service -f
```

**How it works:**
- Checks every 10 seconds if Ethernet cable is connected
- If Ethernet is connected → disables WiFi
- If Ethernet is disconnected → enables WiFi
- Logs all actions to system journal

---

## Scripts

The `scripts/` directory contains automation scripts for backups and network management.

### 1. backup.sh

**Location:** `scripts/backup.sh`

**Purpose:** Backs up all Docker volumes to Backblaze B2 using Restic.

**Features:**
- Discovers and backs up all Docker volumes
- Encrypted backups with Restic
- Automatic retention policy (30 daily, 8 weekly, 12 monthly)
- Weekly integrity checks
- Detailed logging to `logs/` directory

**Usage:**
```bash
# Run manually
bash scripts/backup.sh
# or
just backup

# Required: backup.env must be configured first
```

**Environment Variables (in backup.env):**
- `B2_ACCOUNT_ID` - Backblaze B2 account ID
- `B2_ACCOUNT_KEY` - Backblaze B2 application key
- `RESTIC_REPOSITORY` - Restic repository path (e.g., `b2:bucket-name:/path`)
- `RESTIC_PASSWORD` - Encryption password for Restic
- `BACKUP_RETENTION_DAYS` - Optional, defaults to 30
- `BACKUP_RETENTION_WEEKS` - Optional, defaults to 8
- `BACKUP_RETENTION_MONTHS` - Optional, defaults to 12

**Logs:** Stored in `logs/backup-YYYYMMDD-HHMMSS.log`

---

### 2. restore.sh

**Location:** `scripts/restore.sh`

**Purpose:** Interactive helper tool for restoring backups from Backblaze B2.

**Features:**
- Lists available snapshots
- Provides usage examples
- Shows step-by-step restore instructions

**Usage:**
```bash
# Run restore helper
bash scripts/restore.sh
# or
just backup-restore

# Follow the on-screen instructions
```

**Typical restore workflow:**
1. List snapshots: `restic snapshots`
2. Stop container: `docker compose down <service>`
3. Restore: `restic restore <snapshot-id> --target /tmp/restore`
4. Copy to volume: `docker run --rm -v <volume>:/target -v /tmp/restore/<volume>:/source alpine sh -c 'rm -rf /target/* && cp -a /source/. /target/'`
5. Restart: `docker compose up -d <service>`

---

### 3. manage-connection.sh

**Location:** `scripts/manage-connection.sh`

**Purpose:** Automatically manages WiFi/Ethernet interface switching.

**Logic:**
```bash
if ethernet_connected; then
    disable_wifi
else
    enable_wifi
fi
```

**Usage:**
- Typically run automatically by systemd timer
- Can be run manually: `sudo /usr/local/bin/manage-connection.sh`

**Logs:** Uses `logger` to write to system journal

---

## System Configuration

### Automatic System Updates

**File:** `etc/apt/apt.conf.d/02periodic`

**Purpose:** Enable automatic security updates and package maintenance.

**Setup:**
```bash
sudo cp etc/apt/apt.conf.d/02periodic /etc/apt/apt.conf.d/
```

**Configuration:**
- `Update-Package-Lists "1"` - Daily update package lists
- `Download-Upgradeable-Packages "1"` - Daily download updates
- `Unattended-Upgrade "1"` - Daily install security updates
- `AutocleanInterval "1"` - Daily clean old packages
- `Verbose "2"` - Detailed logging

**View Update Logs:**
```bash
cat /var/log/unattended-upgrades/unattended-upgrades.log
cat /var/log/apt/history.log
```

---

## Quick Setup - All Services

To set up all system services at once:

```bash
# 1. Copy systemd units
sudo cp etc/systemd/system/*.service /etc/systemd/system/
sudo cp etc/systemd/system/*.timer /etc/systemd/system/

# 2. Copy scripts
sudo cp scripts/manage-connection.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/manage-connection.sh

# 3. Copy apt configuration
sudo cp etc/apt/apt.conf.d/02periodic /etc/apt/apt.conf.d/

# 4. Update systemd units if needed (change user/paths)
sudo vim /etc/systemd/system/rpi-services.service
sudo vim /etc/systemd/system/rpi-backup.service

# 5. Enable services
sudo systemctl daemon-reload
sudo systemctl enable rpi-services.service
sudo systemctl enable rpi-backup.timer
sudo systemctl enable manage-connection.timer

# 6. Start services
sudo systemctl start rpi-services.service
sudo systemctl start rpi-backup.timer
sudo systemctl start manage-connection.timer

# 7. Verify everything is running
sudo systemctl status rpi-services.service
sudo systemctl list-timers
```

---

## Monitoring

### Check All Service Status
```bash
# Active services
systemctl status rpi-services.service
systemctl status rpi-backup.service
systemctl status manage-connection.service

# Active timers
systemctl list-timers | grep rpi
```

### View Logs
```bash
# Recent logs for all services
sudo journalctl -u rpi-services.service --since today
sudo journalctl -u rpi-backup.service --since today
sudo journalctl -u manage-connection.service --since today

# Follow live logs
sudo journalctl -f
```

---

## Troubleshooting

### Service won't start
```bash
# Check service status and errors
sudo systemctl status <service-name>
sudo journalctl -u <service-name> -n 50

# Verify file paths and permissions
ls -la /home/vieitesrpi/rpi
ls -la /usr/local/bin/manage-connection.sh
```

### Timer not triggering
```bash
# Check timer status
sudo systemctl status <timer-name>
sudo systemctl list-timers --all

# Restart timer
sudo systemctl restart <timer-name>
```

### Permission errors
```bash
# Ensure user is in docker group
sudo usermod -aG docker $USER
# Log out and back in

# Check file ownership
ls -la ~/rpi/scripts/
```
