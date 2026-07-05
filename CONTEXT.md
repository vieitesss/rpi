# rpi

GitOps homelab for a single Raspberry Pi. The current deployment path is
Kubernetes (K3s + Helmfile) running self-hosted services from a shared Helm
chart, with secrets from GCP Secret Manager and per-service backups to
Backblaze B2. This file is a glossary only — commands and conventions live in
`AGENTS.md` and `docs/`.

## Language

**Service**:
A user-facing logical application (e.g. Tandem, Vaultwarden, AnythingLLM). The
thing you actually care about; may map to several releases.
_Avoid_: App, deployment (when you mean the logical application)

**Release**:
A single Helmfile-deployed unit (e.g. `tandem-backend`, `restic-backup-anythingllm`).
One service can map to several releases.
_Avoid_: App, deployment (when you mean the Helm unit)

**Environment**:
A K3s namespace plus its values overlay. `dev` is the validation environment
and is always changed first; `pro` is production and is only touched when
explicitly asked.
_Avoid_: Stage, tier

**Generic chart**:
The single shared Helm chart most services deploy through
(`kubernetes/helm/charts/generic`); per-service behavior comes from values, not
bespoke charts.
_Avoid_: The template (Helmfile `templates:` is a different concept)

## Secrets

**Secret Manager**:
GCP Secret Manager, the single source of truth for all credentials in this
repo. Secrets are referenced by name (e.g. `ntfy_backup_error`) and pulled into
the cluster via External Secrets.
_Avoid_: Vault (Vaultwarden is an unrelated service), env secrets

## Backups

**Restic release**:
A `restic-backup-*` Helmfile release that runs scheduled CronJob backups for one
service's PVC(s).
_Avoid_: Backup job (when you mean the release)

**Service repo**:
A per-service Restic repository on Backblaze B2 (one service → one repo). All
dev and pro services use service repos; the old global repository no longer
exists.
_Avoid_: App repo, bucket (the B2 bucket is the container, not the repo)

**Snapshot**:
A single Restic backup taken at a point in time.
