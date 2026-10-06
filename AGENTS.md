## Project Scope and Usage

### Scope
This repository is a homelab setup for a Raspberry Pi with:
- Docker Compose as the deployment path: shared services in `compose/compose.yaml`, per-Environment overlays in `compose/dev.yaml` and `compose/pro.yaml`
- Config files mounted into services in `compose/<service>/`
- Deploy, secrets, seeding and Tailscale scripts in `scripts/`, run through the `justfile`
- Host-level systemd/apt assets in `system/` (boot notification, auto-updates, memory guards)

### Stack and Conventions
- Prefer small, declarative changes
- Validate in `dev` first (`just deploy dev`, then `just dev-down`)
- Only change `pro` when explicitly asked
- Deploy with `just deploy <env>` on the Pi after `git pull`; use `just compose <env> ...` for anything else, avoid ad-hoc `docker run`/`docker compose`
- `pro` pins every image to an exact tag; promote a release by copying the tag tested in `dev.yaml` into `pro.yaml`
- Every service sets a `mem_limit`, binds its ports to `127.0.0.1`, and keeps its data under `${RPI_DATA}/<service>` (`/srv/rpi/<env>/<service>`)
- Preserve existing compose and script patterns unless asked to refactor

### Security and Safety
- Never commit secrets
- Do not commit real credential files like `.env`, `.backup.env`, `secrets.env`, or anything generated with credentials
- Secrets live in GCP Secret Manager and are pulled only at deploy time by `scripts/secrets.sh`; nothing may poll Secret Manager (each access is billed). A rotation is picked up by the next deploy. See `docs/security.md`.
- Avoid printing secrets in logs or command output; inspect secret-bearing files with an allowlist of keys, never a denylist

## My Own Likings
- Keep the codebase clean and organized
- Preserve existing patterns unless asked to refactor
- Keep operations safe and non-destructive by default
- If a change can impact production, verify in `dev` first
- Ask before adding new dependencies or tooling
- Do not commit unless explicitly requested
- When updating tandem related services, check the ~/personal/tandem repository and read the documentation files.

## Went Wrong / Solved
- Add short notes here as we work
- The coding agent must update this section whenever an issue is reported or a fix is completed
- Only record items that went wrong and required a fix; do not add routine successful operations
- Solved format: `issue - solution`
- Unsolved format: `issue - open`
- Example solved: `pro deploy refused to start because a data dir was missing - restored the dir from a snapshot`
- Example open: `restic restore timing out on large repo - open`

### Notes
- Backrest UI download button failed for vaultwarden SQLite from latest snapshot while raw `restic dump` from the Backrest container works - caused by stale Backrest operation links indexed under old repo id `b2` after repo was renamed to `vaultwarden`; use fresh index/links or keep repo id stable
- vaultwarden snapshot `7f17b302` looked empty because it is a dev backup and its SQLite tables have 0 user/cipher rows; pro snapshots hold the real vault data
- GCP Secret Manager showed ~20k requests/month because secrets were refreshed hourly - secrets are now fetched only at deploy time (`scripts/secrets.sh`), made a repo rule in `docs/security.md`/`AGENTS.md`
- Homepage (`home`) crashed when its whole `/app/config` was mounted read-only, because it seeds skeleton files there on start - mount each config file on its own so the directory stays writable
- photos-manager image pull failed because `ghcr.io/vieitesss/photos-manager` was private and the Pi has no registry auth - on user decision made the GHCR package public (app secrets are injected at runtime, never baked into images); a future private image needs a `docker login` on the Pi
- vaultwarden floating on `vaultwarden/server:latest` (stuck at 1.36.0) was rejected by Bitwarden clients 2026.7.0+ - pinned `vaultwarden/server:1.37.1`, tested in dev, backed up pro, then promoted
- Pi locked up from memory exhaustion under K3s (dev+pro always on, 20 per-service Tailscale proxy pods, agents on top) - migrated to Docker Compose with Tailscale Services on the host (ADR 0001/0002), `mem_limit` on every container, on-demand dev, systemd-oomd drop-ins and `just agent` for agents; k3s uninstalled after the cutover, pro alone leaves ~6.1 GiB available
- systemd-oomd could not run because the Raspberry Pi kernel ships with PSI disabled (`/proc/pressure` missing) - appended `psi=1` to `/boot/firmware/cmdline.txt` and documented it in `system/README.md`; oomd starts after the next reboot
- `k3s-uninstall.sh` runs `rm -rf /var/lib/rancher/k3s`, which would also delete the old local-path PV data - moved `storage/` to `/srv/rpi/k3s-storage-archive` (root 0700) before uninstalling; delete it only on explicit OK
- printed the pro Backrest multihost sync private key (`sync.identity.ed25519priv`, unused: sync never configured) into an agent session while inspecting the live config, because the redaction was a denylist that missed the key - rotated at cutover: dropped `sync.identity` from the copied config.json and Compose Backrest generated a new one; inspect secret-bearing files with an allowlist of keys only
- cutover copy made `/srv/rpi/pro/backrest` itself 0700 root, so `just deploy pro` (run as the deploy user) could not see `backrest/config` and refused to start - chmod 755 on the parent only; `config/` and `data/` stay 0700 root
- after the cutover, old k8s operator proxy devices showed green in the admin console while the pro apps behind them were scaled to 0 - expected during the gap; replaced by host-served Tailscale Services (operator and `ts-pro-*` proxies scaled to 0, old devices deleted)
- Tailscale Service URLs timed out (curl 000) for ~1 minute right after `tailscale serve` while each Service's first TLS cert was issued - transient, all 200 on retry
