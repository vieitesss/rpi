# rpi

GitOps homelab for a single Raspberry Pi running self-hosted services as
Docker containers, with secrets from GCP Secret Manager and per-service backups
to Backblaze B2. This file is a glossary only — commands and conventions live in
`AGENTS.md` and `docs/`.

## Language

**Service**:
A user-facing logical application (e.g. Tandem, Vaultwarden, Forgejo). The
thing you actually care about; may run as several containers.
_Avoid_: App, deployment (when you mean the logical application)

**Environment**:
One full, isolated copy of every service with its own data. `pro` is
production: always running, only touched when explicitly asked. `dev` is the
validation environment: started on demand to try a change first, then stopped,
so it costs nothing while idle. Its data persists between runs and is only
replaced by production data on explicit request.
_Avoid_: Stage, tier, namespace

**Source-tracked service**:
A Service whose own code is rebuilt from the upstream default branch by a
timer, so it has no pinned version; only the image it runs in is pinned.
_Avoid_: Rolling service, live app

**Build**:
One commit's compiled server and editor assets, named by that commit's sha and
kept after the next one lands, so a swap can be undone.
_Avoid_: Artifact, release

**Mirror clone**:
The deploy-owned copy of a Source-tracked service's repository. Never a working
clone, and safe to reset to the upstream default branch.
_Avoid_: Working clone, checkout

## Secrets

**Secret Manager**:
GCP Secret Manager, the single source of truth for all credentials in this
repo. Secrets are referenced by name (e.g. `ntfy_backup_error`) and fetched
only at deploy time, never polled.
_Avoid_: Vault (Vaultwarden is an unrelated service), env secrets

## Backups

**Backup plan**:
The schedule and retention for backing up one service's data into its service
repo. Only `pro` services have backup plans; `dev` data is never backed up.
_Avoid_: Backup job, restic release

**Service repo**:
A per-service Restic repository on Backblaze B2 (one service → one repo),
holding that service's `pro` snapshots. The old global repository no longer
exists.
_Avoid_: App repo, bucket (the B2 bucket is the container, not the repo)

**Snapshot**:
A single Restic backup taken at a point in time.
