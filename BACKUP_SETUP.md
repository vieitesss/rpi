# Backup Setup Guide

## Overview
Automated daily backups of all Docker volumes to Backblaze B2 using Restic.

- **Schedule**: Daily at 11:00 PM
- **Retention**: 30 daily, 8 weekly, 12 monthly backups
- **Encryption**: End-to-end with Restic
- **Storage**: Backblaze B2 (10GB free tier)

## Initial Setup on Raspberry Pi

### 1. Install Restic
```bash
sudo apt update
sudo apt install restic
```

### 2. Create Backblaze B2 Account & Bucket
1. Sign up at https://www.backblaze.com/b2/sign-up.html
2. Create a new bucket (e.g., `rpi-backups`)
3. Create an application key:
   - Go to "App Keys" → "Add a New Application Key"
   - Give it a name (e.g., `restic-backup`)
   - Allow access to your bucket
   - Save the `keyID` and `applicationKey`

### 3. Configure Backup Credentials
```bash
cd ~/rpi
cp backup.env.example backup.env
chmod 600 backup.env
nano backup.env
```

Fill in:
```
B2_ACCOUNT_ID=your_key_id
B2_ACCOUNT_KEY=your_application_key
B2_BUCKET_NAME=rpi-backups
RESTIC_REPOSITORY=b2:rpi-backups:/restic-repo
RESTIC_PASSWORD=create_a_strong_password_here
```

### 4. Test Backup Manually
```bash
# Make scripts executable
chmod +x scripts/backup.sh scripts/restore.sh

# Run first backup
just backup
# or: bash scripts/backup.sh
```

### 5. Setup Automated Daily Backups
```bash
# Copy systemd files
sudo cp systemd/rpi-backup.service /etc/systemd/system/
sudo cp systemd/rpi-backup.timer /etc/systemd/system/

# Enable and start timer
sudo systemctl daemon-reload
sudo systemctl enable rpi-backup.timer
sudo systemctl start rpi-backup.timer

# Check timer status
sudo systemctl status rpi-backup.timer
sudo systemctl list-timers | grep rpi-backup
```

## Usage

### Manual Backup
```bash
just b
# or: just backup
```

### List Backups
```bash
just bl
# or: just backup-list
```

### Restore Helper
```bash
just br
# or: just backup-restore
```

### Check Backup Logs
```bash
ls -lh logs/
cat logs/backup-YYYYMMDD-HHMMSS.log
```

## Restore Process

### Full Volume Restore
```bash
# 1. List available snapshots
just bl

# 2. Stop the service
just d vaultwarden

# 3. Restore to temporary location
source backup.env
export B2_ACCOUNT_ID B2_ACCOUNT_KEY RESTIC_REPOSITORY RESTIC_PASSWORD
restic restore latest --target /tmp/restore

# 4. Copy data back to volume
docker run --rm \
  -v vaultwarden-data:/target \
  -v /tmp/restore/rpi_vaultwarden-data:/source \
  alpine sh -c 'rm -rf /target/* && cp -a /source/. /target/'

# 5. Restart service
just u -d vaultwarden

# 6. Clean up
rm -rf /tmp/restore
```

## Monitoring

### Check Timer Status
```bash
sudo systemctl status rpi-backup.timer
```

### View Last Backup
```bash
just bl
```

### Manual Backup Run
```bash
sudo systemctl start rpi-backup.service
journalctl -u rpi-backup.service -f
```

## Troubleshooting

### Backup fails with "permission denied"
```bash
# Ensure user can run docker without sudo
sudo usermod -aG docker vieitesrpi
# Log out and back in
```

### Check backup integrity
```bash
source backup.env
export B2_ACCOUNT_ID B2_ACCOUNT_KEY RESTIC_REPOSITORY RESTIC_PASSWORD
restic check
```

### Repository locked
```bash
# If backup was interrupted
source backup.env
export B2_ACCOUNT_ID B2_ACCOUNT_KEY RESTIC_REPOSITORY RESTIC_PASSWORD
restic unlock
```

## Cost Estimate

**Backblaze B2 Pricing:**
- First 10GB: Free
- Storage: $0.006/GB/month
- Download: First 3x storage free, then $0.01/GB

**Example**: 5GB of data = $0/month (within free tier)
