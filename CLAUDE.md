# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Self-hosted Raspberry Pi homelab with Docker services, Tailscale networking, and automated backups to Backblaze B2. Services run in Docker containers with Tailscale sidecars for secure remote access.

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

**Pattern in docker-compose.yaml:**
1. Tailscale sidecar defined with anchor: `filebrowser-ts: &ts`
2. Application uses sidecar's network: `network_mode: service:filebrowser-ts`
3. Tailscale config in `./tailscale/` directory with serve configuration

**Example:**
```yaml
filebrowser-ts: &ts
  image: tailscale/tailscale:latest
  environment:
    - TS_SERVE_CONFIG=/config/https.json
  volumes:
    - ./tailscale:/config

filebrowser:
  image: gtstef/filebrowser:beta
  network_mode: service:filebrowser-ts
```

### Backup System Architecture

The backup system uses Restic with Backblaze B2 for encrypted offsite backups:

1. **Discovery**: `scripts/backup.sh` auto-discovers all Docker volumes
2. **Export**: Each volume copied to `/tmp/rpi-volumes-backup/<volume-name>` using Alpine containers
3. **Backup**: Restic creates encrypted snapshot and uploads to B2
4. **Retention**: Automatically prunes old snapshots (30 daily, 8 weekly, 12 monthly)
5. **Verification**: Weekly integrity checks on day 7, 14, 21, 28

**Credentials**: Stored in `backup.env` (git-ignored), sourced by scripts

### Systemd Automation

Three main automation services in `etc/systemd/system/`:

1. **rpi-services.service**: Auto-starts Docker services on boot
2. **rpi-backup.timer + service**: Daily backups at 23:00 with 30min random delay
3. **manage-connection.timer + service**: WiFi/Ethernet auto-switching every 10s

**Script location**: `manage-connection.sh` must be copied to `/usr/local/bin/` for systemd to access it.

## Adding New Services

When adding a new Docker service:

1. Create Tailscale sidecar entry using YAML anchor pattern
2. Configure service with `network_mode: service:<sidecar-name>`
3. Create Tailscale serve config in `tailscale/<service>.json` if needed
4. Add any required environment variables to `.env`
5. Service volumes are automatically included in backups

## Environment Files

- `.env` - Tailscale auth key and service-specific config (git-ignored)
- `backup.env` - Backblaze B2 credentials and Restic settings (git-ignored)
- `example.env` - Template for `.env`
- `backup.env.example` - Template for `backup.env`

Never commit actual credential files.

## File Locations

- **Docker configs**: Root directory (`docker-compose.yaml`, `docker-compose.override.yaml`)
- **Scripts**: `scripts/` - backup.sh, restore.sh, manage-connection.sh
- **Systemd units**: `etc/systemd/system/` - service and timer files
- **Logs**: `logs/` - Auto-created backup logs
- **Tailscale**: `tailscale/` - Auto-created Tailscale state and config
- **Service data**: `filebrowser/` - Service-specific persistent config

## Restoration Process

To restore a service from backup:

1. List snapshots: `just bl`
2. Stop service: `just down <service>`
3. Restore to temp: `restic restore <snapshot-id> --target /tmp/restore`
4. Copy to volume:
   ```bash
   docker run --rm \
     -v <volume-name>:/target \
     -v /tmp/restore/<volume-name>:/source \
     alpine sh -c 'rm -rf /target/* && cp -a /source/. /target/'
   ```
5. Restart: `just up -d <service>`
6. Cleanup: `rm -rf /tmp/restore`

## Systemd Service Setup

When installing systemd units, update `User` and `WorkingDirectory` to match your setup (default: `vieitesrpi` and `/home/vieitesrpi/rpi`).
