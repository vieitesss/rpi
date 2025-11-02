# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Self-hosted Raspberry Pi homelab with Docker services, Tailscale networking, and automated backups to Backblaze B2. Services run in Docker containers with Tailscale sidecars for secure remote access.

**Current Services:**
- **Vaultwarden**: Self-hosted password manager (Bitwarden-compatible)
- **Filebrowser**: Web-based file manager for media storage

## Common Commands

### Service Management
```bash
just up -d          # Start all services (detached)
just down           # Stop all services
just log -f         # Follow logs
docker compose up -d <service>    # Start specific service
docker compose down <service>     # Stop specific service
```

### Backup Operations
```bash
just b              # Run manual backup
just bl             # List all backups
just br             # Interactive restore helper
```

### System Management
```bash
# Check systemd services
sudo systemctl status rpi-services.service
sudo systemctl status rpi-backup.timer
sudo systemctl status manage-connection.timer

# View logs
sudo journalctl -u rpi-services.service -f
sudo journalctl -u rpi-backup.service -f
```

## Architecture

### Docker Service Pattern with Tailscale Sidecars

Services use a sidecar pattern where each application container shares its network namespace with a Tailscale container. This provides secure remote access without exposing ports.

**Architecture:**
1. **Base sidecar** defined with YAML anchor in `docker-compose.yaml`: `filebrowser-ts: &ts`
2. **Per-service overrides** in `docker-compose.override.yaml` set hostname, container name, and state volume
3. **Application** uses sidecar's network: `network_mode: service:filebrowser-ts`
4. **Tailscale state** stored in named Docker volumes (per-service)
5. **Serve configs** in `./tailscale/` directory (shared across services)

**Example from current setup:**

`docker-compose.yaml`:
```yaml
filebrowser-ts: &ts
  image: tailscale/tailscale:latest
  environment:
    - TS_AUTHKEY=${TAILSCALE_AUTH_KEY}
    - TS_STATE_DIR=/var/lib/tailscale
    - TS_USERSPACE=false
    - "TS_EXTRA_ARGS=--advertise-tags=tag:homelab --reset"
  cap_add:
    - net_admin
    - sys_module
  volumes:
    - ${PWD}/tailscale:/config
    - /dev/net/tun:/dev/net/tun

vaultwarden-ts: *ts

filebrowser:
  image: gtstef/filebrowser:beta
  network_mode: service:filebrowser-ts
```

`docker-compose.override.yaml`:
```yaml
filebrowser-ts:
  hostname: filebrowser
  container_name: filebrowser-ts
  environment:
    - TS_SERVE_CONFIG=/config/port-80.json
  volumes:
    - filebrowser-ts:/var/lib/tailscale
```

`tailscale/port-80.json`:
```json
{
  "TCP": {
    "443": {
      "HTTPS": true
    }
  },
  "Web": {
    "${TS_CERT_DOMAIN}:443": {
      "Handlers": {
        "/": {
          "Proxy": "http://127.0.0.1:80"
        }
      }
    }
  }
}
```

### Backup System Architecture

The backup system uses Restic with Backblaze B2 for encrypted offsite backups:

**What gets backed up:**
- All Docker volumes (auto-discovered)
- Media folder: `/media/vieitesrpi/vieitesss/filebrowser`
- Database: `filebrowser/database.db`

**Backup process:**
1. **Discovery**: Auto-discovers all Docker volumes
2. **Export**: Volumes copied to `/tmp/rpi-full-backup/docker-volumes/<volume-name>` using Alpine containers
3. **Media/DB**: Copies media folder and database to temp backup location
4. **Backup**: Restic creates encrypted, compressed, deduplicated snapshot and uploads to B2
5. **Retention**: Automatically prunes old snapshots (30 daily, 8 weekly, 12 monthly)
6. **Verification**: Weekly integrity checks on days divisible by 7 (checks 5% of data)
7. **Stats**: Shows repository size to monitor B2 10GB free tier usage

**Compression & Deduplication:**
- Restic automatically compresses all data
- Deduplication: identical chunks stored only once across all backups
- Incremental: only changed data uploaded after first backup
- This dramatically reduces storage usage, especially for similar/unchanged files

**Credentials**: Stored in `.backup.env` (git-ignored), sourced by scripts

### Systemd Automation

Three main automation services in `etc/systemd/system/`:

1. **rpi-services.service**: Auto-starts Docker services on boot
2. **rpi-backup.timer + service**: Daily backups at 23:00 with 30min random delay
3. **manage-connection.timer + service**: WiFi/Ethernet auto-switching every 10s

**Script location**: `manage-connection.sh` must be copied to `/usr/local/bin/` for systemd to access it.

## Adding New Services

When adding a new Docker service:

1. **In `docker-compose.yaml`:**
   - Create Tailscale sidecar using YAML anchor alias: `<service>-ts: *ts`
   - Define service with `network_mode: service:<service>-ts`

2. **In `docker-compose.override.yaml`:**
   - Add sidecar overrides: hostname, container name, TS_SERVE_CONFIG, and state volume
   - Format: `<service>-ts:/var/lib/tailscale`

3. **Create Tailscale serve config** in `tailscale/` if needed:
   - Use `port-80.json` for services listening on port 80 (shared by vaultwarden & filebrowser)
   - Create custom JSON for other port configurations
   - Config files are mounted read-only and can be shared across multiple services

4. **Add environment variables** to `.env` if needed

5. **Add named volume** for Tailscale state to volumes section

6. **Service volumes are automatically included in backups**

7. **Check if the service needs a `user` directive** (see below)

### Handling Docker User Permissions

Some Docker images run as non-root users internally, which can cause permission issues with volumes. To make the configuration portable and avoid manual `chown` commands:

**Add the `user` directive to match the container's internal UID/GID:**

```yaml
service_name:
  image: some/image:latest
  user: "1001:1001"  # Match the UID:GID the container expects
  volumes:
    - service-data:/data
```

**When to use this:**
- Container fails with "permission denied" or "cannot open database file" errors
- Check the container's user: `docker exec <container> id`
- If it runs as a non-root user (not UID 0), add the `user` directive

**Examples:**
- Joplin runs as UID 1001, so it uses `user: "1001:1001"`
- Vaultwarden and Filebrowser run as root, so they don't need this

**Benefits:**
- Docker automatically creates volumes with correct ownership
- Configuration works for anyone without manual permission fixes
- No need to run `chown` commands after volume creation

## Environment Files

- `.env` - Tailscale auth key and service-specific config (git-ignored)
- `.backup.env` - Backblaze B2 credentials and Restic settings (git-ignored)
  - Optional: `BACKUP_MEDIA_PATH` to override default media folder location
- `example.env` - Template for `.env`
- `backup.env.example` - Template for `.backup.env`

Never commit actual credential files.

## File Locations

- **Docker configs**: Root directory (`docker-compose.yaml`, `docker-compose.override.yaml`)
- **Scripts**: `scripts/` - backup.sh, restore.sh, manage-connection.sh
- **Systemd units**: `etc/systemd/system/` - service and timer files
- **Logs**: `logs/` - Auto-created backup logs
- **Tailscale**: `tailscale/` - Serve config JSON files (state stored in Docker volumes)
- **Service data**: `filebrowser/` - Service-specific persistent config

## Restoration Process

To restore from backup:

### Restore Docker Volume:
1. List snapshots: `just bl`
2. Stop service: `just down <service>`
3. Restore to temp: `restic restore latest --target /tmp/restore`
4. Copy to volume:
   ```bash
   docker run --rm \
     -v <volume-name>:/target \
     -v /tmp/restore/docker-volumes/<volume-name>:/source \
     alpine sh -c 'rm -rf /target/* && cp -a /source/. /target/'
   ```
5. Restart: `just up -d <service>`
6. Cleanup: `rm -rf /tmp/restore`

### Restore Media Folder:
```bash
restic restore latest --target /tmp/restore
sudo rsync -a /tmp/restore/media-filebrowser/ /media/vieitesrpi/vieitesss/filebrowser/
rm -rf /tmp/restore
```

### Restore Database:
```bash
restic restore latest --target /tmp/restore
cp /tmp/restore/filebrowser-db/database.db filebrowser/database.db
rm -rf /tmp/restore
```

## Systemd Service Setup

When installing systemd units, update `User` and `WorkingDirectory` to match your setup (default: `vieitesrpi` and `/home/vieitesrpi/rpi`).
