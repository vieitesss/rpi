# Docker Compose over K3s, with on-demand dev on the same Pi

The Pi (8 GiB) ran out of memory under K3s with dev and pro both always on, a
Tailscale proxy pod per hostname and coding agents on top; it locked up
instead of recovering. We replaced K3s + Helmfile with plain Docker Compose:
one base file plus a `pro` and a `dev` overlay, each its own Compose project
with its own data dir under `/srv/rpi/<env>`. `pro` is always on; `dev` runs
only while a change is being tried (`just deploy dev`, then `just dev-down`),
so it costs nothing while idle. Every container has a `mem_limit`.

## Considered Options

- **Keep K3s, trim it** (drop dev, fewer proxies): the control plane, the
  operators and a Tailscale proxy per exposed name would still cost memory
  that the apps need; with everything up K3s settled at ~4.4 GiB used of 8.
- **Dev on another machine**: no second always-on machine; dev must test
  against the same arch, paths and Tailscale setup as pro.

## Consequences

- No reconciler: the checked-out repo is the desired state, applied by
  `just deploy <env>`; `restart: unless-stopped` brings pro back after a boot.
- Dev and pro share the host, so dev must stay down when not in use.
- Backups move from restic CronJobs to Backrest (a long-running container)
  over the same B2 service repos.
