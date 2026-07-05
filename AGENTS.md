## Project Scope and Usage

### Scope
This repository is a homelab setup for a Raspberry Pi with:
- Kubernetes (K3s + Helmfile) as the current deployment path
- Generic Helm chart-based services in `kubernetes/values/<service>/`
- Host-level systemd/apt assets in `system/` (boot notification, auto-updates)

### Stack and Conventions
- Prefer small, declarative changes
- Validate in `dev` first
- Only change `pro` when explicitly asked
- Use Helmfile flows (`helmfile`, deploy scripts), avoid ad-hoc `kubectl apply`
- Keep service config focused and colocated in `kubernetes/values/<service>/`
- Preserve existing chart/value patterns unless asked to refactor

### Security and Safety
- Never commit secrets
- Do not commit real credential files like `.env`, `.backup.env`, or generated secret YAMLs
- Use External Secrets Operator + GCP Secret Manager for Kubernetes secrets
- Every `ExternalSecret` MUST set `refreshInterval: "0"` (no periodic refresh) to avoid GCP Secret Manager access costs; re-sync the release to pick up a rotation. See `docs/security.md`.
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
- restic CronJobs had no failure alerting - added optional ntfy failure notifications sourced from GCP Secret Manager secret `ntfy_backup_error`, enabled for dev/pro vaultwarden and tandem backup releases, and validated Helm templates
- knot server reported inaccessible - checked knotserver/cloudflared logs and current HTTP access works; intermittent Cloudflare tunnel reconnects observed, no fix applied yet - open
- anythingllm helmfile diff failed because main values file was misspelled `vaules.yaml`, leaving `deployment.image` empty - renamed it to `values.yaml` and verified `helmfile -e dev -l name=anythingllm diff`
- anythingllm `/files` missing after deploy because standalone files PVC was not applied and rolling update stuck while old pod held app PVC - applied files PV/PVC, set AnythingLLM strategy to Recreate, reused existing data volume for MCP init, and verified `/files` writes to `/home/vieitesrpi/me`
- anythingllm chat failed with `model is required` because Ollama provider had no model env/default (`initialized with model: undefined`) - pinned dev AnythingLLM config to `OLLAMA_MODEL_PREF=qwen2.5:7b`, synced/restarted, and verified pod can list Ollama models
- anythingllm PVCs were not covered by restic backups - added restic-backup-anythingllm release values, fixed scale-down pod wait selector, suspended dev schedule for manual-only backups, deployed pro schedule, and verified snapshots `85617659` (dev) / `69328f63` (pro); restore drill verified pro snapshot restored both AnythingLLM PVC paths
- restic restore helper could only flatten `/backup/<app>` and was awkward for multi-PVC apps - added explicit snapshot source path support, verified `/backup/anythingllm-files` restores to a scratch PVC root, and synced updated AnythingLLM backup releases in dev/pro
- restic backup/list helpers were hardcoded to `restic-backup` and temp pod names collided under parallel use - added optional restic release args and process-suffixed temporary names
- restic CronJobs all ran at the same minute and lacked explicit timezone - added `timeZone: Etc/UTC`, staggered vaultwarden/tandem/anythingllm to 23:00/23:15/23:30 UTC, and synced dev/pro releases
- backups had no UI for visualizing snapshots or triggering runs - deployed dev-only Backrest pilot with B2/restic secrets, persistent config/data, read-only mounts for dev backup PVCs, and Tailnet hostname `backrest-dev`
- Backrest repo setup returned `b2 authorize account: 401` when using `.backup.env` - verified `.backup.env` B2 auth is stale/bad while Backrest pod's Kubernetes-injected B2/restic secrets can list existing snapshots
- Backrest UI download button failed for vaultwarden SQLite from latest snapshot while raw `restic dump` from the Backrest pod works - caused by stale Backrest operation links indexed under old repo id `b2` after repo was renamed to `vaultwarden`; use fresh index/links or keep repo id stable
- dev Backrest uninstall removed the PVC object despite trying to keep it - local-path-retain kept the PV/data, cleared the retained PV claimRef and rebound a standalone `dev-backrest-pvc`
- vaultwarden snapshot `7f17b302` looked empty because it is the dev backup and its SQLite tables have 0 user/cipher rows; pro latest has data, use pro vaultwarden snapshots for real vault data
- GCP Secret Manager showed ~20k requests/month - all ExternalSecrets refreshed hourly over static B2/restic/ntfy/backrest/tandem creds; set every ExternalSecret to `refreshInterval: "0"` (chart defaults + tandem values), made it a required repo rule in `docs/security.md`/`AGENTS.md`, rotations now picked up by re-syncing the release
