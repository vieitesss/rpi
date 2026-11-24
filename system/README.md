# System Configuration

Host-level configuration for the Pi: automatic updates, the boot
notification, the memory guards that keep it responsive, and the user services
that remote tools connect to.

## Directory Contents

### `/etc/apt/apt.conf.d/`
- **`02periodic`**: downloads and installs security updates daily.

### `/etc/systemd/system/`
- **`notify.service`**: on boot, waits for the pro containers and sends an
  ntfy notification with how many are running (`scripts/notify.sh`, topic
  `NTFY` from the untracked `.env`, see `.env.example`).
- **`esbozo-update.timer`**, **`esbozo-update.service`**: advances esbozo to
  `origin/main` every 15 minutes, keeps the last 3 Builds, and restarts only
  the esbozo container.
- **`-.slice.d/10-oomd.conf`**, **`user@.service.d/10-oomd.conf`**:
  systemd-oomd kills the cgroup behind sustained memory pressure or a full
  zram swap, instead of letting the Pi thrash until it stops responding.
  Containers are also capped by their `mem_limit`, and agents started over SSH
  should run under `just agent <command>` (a memory-capped systemd scope).

### `user/` (installed to `~/.config/systemd/user/`)
- **`paseo-daemon.service`**: runs the Paseo daemon (`127.0.0.1:6767`) that
  paseito reaches over an SSH tunnel.
- **`tmux.service`**: starts the tmux server with a `main` session, so nexo
  lists the Pi as a tmux remote.

Both run with lingering on, so they start at boot without a login. They set
`PATH` themselves because `zsh -l` does not read `.zshrc`, where the pi-node
path lives; update the node version in both units when it changes.

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

### 5. Enable the esbozo Updater

Run the first build from the checkout before `just deploy pro`, because `pro`
refuses to start without `dist/current` (root is needed to write root-owned
`/srv/rpi/pro/esbozo` and drive docker; `just esbozo-build` is equivalent):

```bash
sudo ./scripts/esbozo-build.sh
sudo sed -i "s/<user>/$USER/g" /etc/systemd/system/esbozo-update.service /etc/systemd/system/esbozo-update.timer
sudo systemctl daemon-reload
sudo systemctl enable --now esbozo-update.timer
systemctl list-timers esbozo-update
```

### 6. Enable the User Services

```bash
mkdir -p ~/.config/systemd/user
cp user/*.service ~/.config/systemd/user/
sudo loginctl enable-linger "$USER"
systemctl --user daemon-reload
systemctl --user enable --now paseo-daemon.service tmux.service
```

Manage the daemon with `systemctl --user restart paseo-daemon` from then on;
a `paseo daemon start` alongside the unit starts a second daemon on the same
port. Stopping `tmux.service` kills the whole tmux server, sessions included.
