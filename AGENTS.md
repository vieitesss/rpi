# AGENTS.md

This is a shared file for both the project owner and the coding agent.
Use it as the source of truth for project working agreements.

## Project Scope and Usage

### Scope
This repository is a GitOps homelab setup for a Raspberry Pi with:
- Kubernetes (K3s + Helmfile) as the current deployment path
- Generic Helm chart-based services in `kubernetes/values/<service>/`
- Legacy Docker Compose and systemd assets for older workflows

### Stack and Conventions
- Prefer small, declarative changes
- Validate in `dev` first
- Only change `pro` when explicitly asked
- Use Helmfile flows (`helmfile`, deploy scripts), avoid ad-hoc `kubectl apply`
- Keep service config focused and colocated in `kubernetes/values/<service>/`
- Preserve existing chart/value patterns unless asked to refactor

### Local Usage
- Deploy environment: `bash kubernetes/scripts/deploy.sh dev` or `bash kubernetes/scripts/deploy.sh pro`
- Sync one release: `helmfile -e dev -l name=<service> sync`
- Verify resources: `kubectl get all -n <env>`
- Verify pods: `kubectl get pods -n <env>`
- Follow logs: `kubectl logs -f -l app=<env>-<service> -n <env>`

### Backup / Restore (Kubernetes, Restic per app)
- Backup: `bash kubernetes/scripts/restic-backup.sh <namespace> <app-name>`
- List snapshots: `bash kubernetes/scripts/restic-list.sh <namespace> <app-name>`
- Restore: `bash kubernetes/scripts/restic-restore.sh <namespace> <app-name> [snapshot-id] [target-pvc] [source-namespace] [restic-release]`
- Migrate old backups: `bash kubernetes/scripts/restic-migrate-to-app-repos.sh <namespace> <app-name>`

### Legacy Docker Compose
Run from `docker-compose/`:
- Start: `just up` or `docker compose up -d`
- Stop: `just down` or `docker compose down`
- Logs: `just log` or `docker compose logs -f`
- Backup/restore: `just backup`, `just restore`, `just restore-list`

### More Guidance
- Ops workflows and common commands: `docs/ops.md`
- Kubernetes/Helmfile conventions: `docs/kubernetes.md`
- Secrets and safety rules: `docs/security.md`

### Tandem Notes
- Backend >=0.7.x uses PGlite lock file at the data dir parent: `.tandem.lock` (older `.pglite.lock` may be stale).
- Schema adds a `changes` table; add it to existing PGlite DBs when upgrading.
- If the tandem backend PVC is stuck Terminating and blocking scheduling, scale down the deployment, remove completed restic-backup pods, clear the PV claimRef, then re-sync to rebind.

### Security and Safety
- Never commit secrets
- Do not commit real credential files like `.env`, `.backup.env`, or generated secret YAMLs
- Use External Secrets Operator + GCP Secret Manager for Kubernetes secrets
- Avoid printing secrets in logs or command output

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
- Example solved: `helmfile sync failed due to missing env override - added dev values file`
- Example open: `restic restore timing out on large pvc - open`

### Notes
- tailscale operator CrashLoopBackOff due to unstable image expecting CRDs missing from stable chart - removed unstable image overrides, corrected deploy check to use Helm release/deployment operator, upgraded to chart/app v1.96.5, and verified all tailscale pods ready
- restoring pro/tandem into dev used wrong default restore scripts - added source namespace and restic release options to restic-restore.sh, then restored dev from pro/tandem and ran changes.sql migration
- pro/vaultwarden restic backup targeted old `vaultwarden-pvc` while live deployment uses `pro-vaultwarden-pvc` - updated pro restic values to back up `pro-vaultwarden-pvc`, synced restic-backup, and verified snapshot `d9a5b95d`
- pro/vaultwarden was running stale `vaultwarden/server:latest` pod - restarted after quiesced backup and verified Vaultwarden 1.36.0 on image digest `sha256:d626d04934cd1192ad8ced1adb975099fca78cec33ab467d2d3c923cde7f3b0c`
- old unused pro `vaultwarden-pvc` remained after migration to `pro-vaultwarden-pvc` - deleted completed jobs referencing it and deleted the unused PVC object; backing PV remains Retain/Released
- pro/vaultwarden used mutable `vaultwarden/server:latest` in shared values - pinned pro override to upstream release tag `vaultwarden/server:1.36.0`, backed up first, synced release, and verified rollout
- generic Helm chart lacked health probe support - added optional readiness/liveness/startup probe values and conditional deployment rendering, validated dev template and sample probe rendering
- documentation log selector used nonexistent `app.kubernetes.io/name` label - updated docs to use existing generic chart label format `app=<env>-<service>`
