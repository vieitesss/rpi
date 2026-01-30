# Ops Workflows

GitOps repo. Keep changes small and declarative. Validate in `dev` before `pro`.

## Deploy

- Deploy an environment: `bash kubernetes/scripts/deploy.sh dev` or `bash kubernetes/scripts/deploy.sh pro`
- Sync one release: `helmfile -e dev -l name=<service> sync`

## Verify

- Check resources: `kubectl get all -n <env>`
- Check pods: `kubectl get pods -n <env>`
- Follow logs: `kubectl logs -f -l app.kubernetes.io/name=<service> -n <env>`

## Backup / Restore (Kubernetes, Restic per app)

- Backup: `bash kubernetes/scripts/restic-backup.sh <namespace> <app-name>`
- List: `bash kubernetes/scripts/restic-list.sh <namespace> <app-name>`
- Restore: `bash kubernetes/scripts/restic-restore.sh <namespace> <app-name> [snapshot-id] [target-pvc]`
- Migrate old backups: `bash kubernetes/scripts/restic-migrate-to-app-repos.sh <namespace> <app-name>` (run once per app)

## Docker Compose (Legacy)

Run from `docker-compose/`.

- Start: `just up` or `docker compose up -d`
- Stop: `just down` or `docker compose down`
- Logs: `just log` or `docker compose logs -f`
- Backup: `just backup`
- Restore: `just restore` or `just restore-list`
- Restore helper (interactive): `bash docker-compose/scripts/restore.sh`
