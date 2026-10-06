# System Configuration

Host-level configuration for the Pi: automatic updates, the boot
notification, and the memory guards that keep it responsive.

## Directory Contents

### `/etc/apt/apt.conf.d/`
- **`02periodic`**: downloads and installs security updates daily.

### `/etc/systemd/system/`
- **`notify.service`**: on boot, waits for the pro containers and sends an
  ntfy notification with how many are running (`scripts/notify.sh`, topic
  `NTFY` from the untracked `.env`, see `.env.example`).
- **`-.slice.d/10-oomd.conf`**, **`user@.service.d/10-oomd.conf`**:
  systemd-oomd kills the cgroup behind sustained memory pressure or a full
  zram swap, instead of letting the Pi thrash until it stops responding.
  Containers are also capped by their `mem_limit`, and agents started over SSH
  should run under `just agent <command>` (a memory-capped systemd scope).

## Installation & Usage

### 1. Copy Configuration

```bash
sudo cp -r etc/ /
sudo systemctl daemon-reload
```

### 2. Enable Automatic Updates

```bash
sudo apt update && sudo apt install unattended-upgrades
```

### 3. Enable systemd-oomd

systemd-oomd needs PSI, which Raspberry Pi kernels ship disabled: append
` psi=1` to the single line in `/boot/firmware/cmdline.txt` and reboot.

```bash
sudo apt install systemd-oomd
sudo systemctl enable systemd-oomd
sudo reboot
oomctl   # after the reboot: lists the cgroups it now watches
```

### 4. Enable the Boot Notification

`notify.service` names the deploy user and the checkout as `<user>` and
`/home/<user>/rpi`; fill them in after copying:

```bash
sudo sed -i "s/<user>/$USER/g" /etc/systemd/system/notify.service
sudo systemctl daemon-reload
sudo systemctl enable --now notify.service
```
