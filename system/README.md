# System Configuration

This directory contains system-level configuration files to automate updates, manage Docker services on boot, and handle backups.

## Directory Contents

### `/etc/apt/apt.conf.d/`
- **`02periodic`**: Configures the system to automatically download and install security updates daily.

### `/etc/systemd/system/`
- **`rpi-services@.service`**: A template service that starts/stops your Docker Compose stack automatically when the Pi boots/shuts down.
- **`rpi-backup@.service`**: The logic script to backup Docker volumes.
- **`rpi-backup@.timer`**: A template scheduler that triggers the backup service daily for a specific user.

## Installation & Usage

### 1. Copy Configuration

Apply the configurations to your system (this merges the directories):

```bash
sudo cp -r etc/ /
```

### 2. Enable Automatic Updates

Ensure the required package is installed so `02periodic` works:

```bash
sudo apt update && sudo apt install unattended-upgrades
```

### 3. Enable Systemd Services

Reload the daemon to recognize the new files:

```bash
sudo systemctl daemon-reload
```

**Enable Docker Services on Boot:**

```bash
sudo systemctl enable --now rpi-services@<your-user-name>
```

**Enable Daily Backups:**

```bash
sudo systemctl enable --now rpi-backup@<your-user-name>.timer
```
