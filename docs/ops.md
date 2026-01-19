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

- K8s restic backup: `bash kubernetes/scripts/restic-backup.sh dev`
- K8s restic list: `bash kubernetes/scripts/restic-list.sh dev`
- K8s restic restore helper: `bash kubernetes/scripts/restic-restore.sh dev [snapshot] [target-pvc]`
- Docker restore helper (interactive): `bash docker-compose/scripts/restore.sh`

## Docker Compose (Legacy)

Run these from `docker-compose/`.

- Start services: `just up` or `docker compose up -d`
- Stop services: `just down` or `docker compose down`
- Logs: `just log` or `docker compose logs -f`
- Backup: `just backup`
- Restore: `just restore` / `just restore-list`
