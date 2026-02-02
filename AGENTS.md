# AGENTS.md

This repository is a GitOps homelab setup for a Raspberry Pi (K3s + Helmfile, plus some legacy Docker Compose).

Keep changes small and declarative. When in doubt, test in `dev` first.

Tandem notes:
- Backend >=0.7.x uses PGlite lock file at the data dir parent: `.tandem.lock` (older `.pglite.lock` may be stale).
- Schema adds a `changes` table; add it to existing PGlite DBs when upgrading.
- If the tandem backend PVC is stuck Terminating and blocking scheduling, scale down the deployment, remove completed restic-backup pods, clear the PV claimRef, then re-sync to rebind.

- Ops workflows and common commands: `docs/ops.md`
- Kubernetes/Helmfile conventions: `docs/kubernetes.md`
- Secrets and safety rules: `docs/security.md`
