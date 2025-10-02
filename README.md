# Raspberry Pi Homelab

Self-hosted services with Tailscale networking and automated backups to Backblaze B2.

## What's Included

- **Docker Services**: Containerized applications (currently: Vaultwarden)
- **Tailscale**: Secure zero-config VPN for remote access to all services
- **Automated Backups**: Daily encrypted backups to Backblaze B2 with Restic
- **Just Commands**: Convenient shortcuts for common operations

## Prerequisites

- Raspberry Pi (3/4/5 or Zero 2 W) running Raspberry Pi OS (64-bit recommended)
- Internet connection
- Tailscale account (free tier available)
- Backblaze B2 account (optional, for backups - 10GB free tier)

## Initial Setup

### 1. Update System & Install Dependencies

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git docker.io docker-compose restic
```

### 2. Configure Docker Permissions

```bash
sudo usermod -aG docker $USER
# Log out and back in for group changes to take effect
```

### 3. Install Just (command runner)

```bash
curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to ~/bin
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### 4. Clone This Repository

```bash
cd ~
git clone <your-repo-url> rpi
cd rpi
```

### 5. Configure Tailscale

1. Sign up at https://tailscale.com
2. Generate an auth key:
   - Go to Settings → Keys → Generate auth key
   - Enable "Reusable" and set expiration as needed
   - Copy the key (starts with `tskey-auth-`)

3. Create environment file:
```bash
cp example.env .env
vim .env
```

4. Set your Tailscale auth key:
```
TAILSCALE_AUTH_KEY=tskey-auth-your-key-here
```

### 6. Configure Services

Edit `docker-compose.yaml` to customize service settings:
```bash
vim docker-compose.yaml
```

Update any service-specific configuration (domains, ports, etc.)

### 7. Start Services

```bash
just up -d
# or: docker compose up -d
```

Verify services are running:
```bash
just log -f
# or: docker compose logs -f
```

### 8. Access Your Services

- Via Tailscale: Connect to your services using their Tailscale hostnames
- Check container names in `docker-compose.yaml` for service-specific details

## System Automation (Optional but Recommended)

### Automated Backups

See [BACKUP_SETUP.md](BACKUP_SETUP.md) for detailed instructions on:
- Configuring Backblaze B2
- Setting up automated daily backups
- Restore procedures

Quick setup:
```bash
cp backup.env.example backup.env
chmod 600 backup.env
vim backup.env  # Fill in your B2 credentials
just backup     # Run first backup
```

### Systemd Services & Scripts

See [SYSTEM_SETUP.md](SYSTEM_SETUP.md) for detailed setup of:
- **Auto-start services on boot** - Docker services start automatically
- **Network management** - Auto-switch between WiFi and Ethernet
- **Automatic system updates** - Daily security updates
- **Backup scripts** - Manual and automated backup tools

Quick setup all automation:
```bash
# See SYSTEM_SETUP.md for full instructions
sudo cp etc/systemd/system/*.service /etc/systemd/system/
sudo cp etc/systemd/system/*.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable rpi-services.service rpi-backup.timer manage-connection.timer
```

## Common Commands

### Service Management
```bash
just up -d        # Start all services (detached)
just down         # Stop all services
just log -f       # Follow logs
```

### Backups
```bash
just b            # Run backup
just bl           # List backups
just br           # Restore helper
```

### Full Command List
```bash
just              # Show all available commands
```

## Adding New Services

1. Edit `docker-compose.yaml` to add your service
2. If the service needs Tailscale access, create a sidecar container (see vaultwarden example)
3. Update `.env` if new environment variables are needed
4. Restart services: `just down && just up -d`

Services are automatically included in backups (all Docker volumes are backed up).

## Maintenance

### Update Services
```bash
just down
docker compose pull
just up -d
```

### Check Service Status
```bash
docker ps
docker compose logs <service-name>
```

### Monitor System Resources
```bash
htop
docker stats
```

## Troubleshooting

### Services won't start
```bash
# Check logs
just log

# Verify Docker is running
sudo systemctl status docker
```

### Can't access services via Tailscale
```bash
# Check Tailscale status for a service
docker exec <service-name>-ts tailscale status

# Check Tailscale IP
docker exec <service-name>-ts tailscale ip -4
```

### Backup issues
See [BACKUP_SETUP.md](BACKUP_SETUP.md#troubleshooting)

## Security Notes

- Never commit `.env` or `backup.env` files (they contain secrets)
- Use strong passwords for all services and Restic backups
- Keep your Raspberry Pi OS updated
- Regularly test your backup restores
- Review Tailscale ACLs to control access to services

## Project Structure

```
rpi/
├── docker-compose.yaml           # Service definitions
├── .env                          # Tailscale & service configuration (git-ignored)
├── backup.env                    # Backup credentials (git-ignored)
├── justfile                      # Command shortcuts
├── scripts/                      # Automation scripts
│   ├── backup.sh                 # Backup all Docker volumes
│   ├── restore.sh                # Interactive restore helper
│   └── manage-connection.sh      # WiFi/Ethernet auto-switching
├── etc/                          # System configuration files
│   ├── systemd/system/           # Systemd service units
│   │   ├── rpi-services.service  # Auto-start Docker services
│   │   ├── rpi-backup.service    # Backup service
│   │   ├── rpi-backup.timer      # Daily backup timer
│   │   ├── manage-connection.service
│   │   └── manage-connection.timer
│   └── apt/apt.conf.d/           # APT configuration
│       └── 02periodic            # Auto-update settings
├── logs/                         # Backup logs (auto-created)
├── tailscale/                    # Tailscale config (auto-created)
├── README.md                     # This file
├── BACKUP_SETUP.md              # Backup configuration guide
└── SYSTEM_SETUP.md              # System automation guide
```

## License

MIT
