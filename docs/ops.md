# Ops Workflows

This repo is GitOps. Prefer small, declarative changes and validate in `dev` before touching `pro`.

## Deploy

- Deploy an environment: `bash kubernetes/scripts/deploy.sh dev` or `bash kubernetes/scripts/deploy.sh pro`
- Sync a single release: `helmfile -e dev -l name=<service> sync`

## Verify

- Check resources: `kubectl get all -n dev` or `kubectl get all -n pro`
- Check pods quickly: `kubectl get pods -n dev`
- Follow logs for a release: `kubectl logs -f -l app.kubernetes.io/name=<service> -n dev`

## Backup / Restore

### Kubernetes (Restic per-app repositories)

- **Manual backup**: `bash kubernetes/scripts/restic-backup.sh <namespace> <app-name>`
  - Example: `bash kubernetes/scripts/restic-backup.sh dev vaultwarden`
  
- **List snapshots**: `bash kubernetes/scripts/restic-list.sh <namespace> <app-name>`
  - Example: `bash kubernetes/scripts/restic-list.sh dev vaultwarden`
  
- **Restore**: `bash kubernetes/scripts/restic-restore.sh <namespace> <app-name> [snapshot-id] [target-pvc]`
  - Example: `bash kubernetes/scripts/restic-restore.sh dev vaultwarden latest dev-vaultwarden-pvc`
  
- **Migrate old backups**: `bash kubernetes/scripts/restic-migrate-to-app-repos.sh <namespace> <app-name>`
  - Run this once per app to migrate from old global repository to new per-app structure
  - Example: `bash kubernetes/scripts/restic-migrate-to-app-repos.sh dev vaultwarden`

### Docker Compose (Legacy)

- Docker restore helper (interactive): `bash docker-compose/scripts/restore.sh`

## Docker Compose (Legacy)

Run these from `docker-compose/`.

- Start services: `just up` or `docker compose up -d`
- Stop services: `just down` or `docker compose down`
- Logs: `just log` or `docker compose logs -f`
- Backup: `just backup`
- Restore: `just restore` / `just restore-list`
