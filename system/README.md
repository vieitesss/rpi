# System Configuration

This directory contains host-level configuration files for automatic updates
and boot-time notifications.

## Directory Contents

### `/etc/apt/apt.conf.d/`
- **`02periodic`**: Configures the system to automatically download and install security updates daily.

### `/etc/systemd/system/`
- **`notify.service`**: Sends a notification on boot once K3s and the network are ready.

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

**Enable Boot Notification:**

```bash
sudo systemctl enable --now notify.service
```
