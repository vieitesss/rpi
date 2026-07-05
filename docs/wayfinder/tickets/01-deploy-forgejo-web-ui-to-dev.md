<!-- child-of: Self-hosted private git server (Forgejo on Tailscale) -->
# Deploy Forgejo web UI to dev on Tailscale

- label: wayfinder:task
- status: closed
- assignee: Daniel
- blocked-by:

## Question

Add a `forgejo` Helmfile release using the generic chart: Forgejo image,
SQLite backend, a PVC for `/data`, registration disabled, HTTPS on the
`tailscale` Ingress (hostname e.g. `forgejo-dev`). Deploy to `dev` and verify
the web UI loads over Tailscale and an admin user can sign in.

Answer records: chosen image tag, hostname, PVC size, and how the admin user
was bootstrapped (this graduates the "Admin bootstrap" fog).

## Resolution

Deployed `forgejo` release (generic chart) to `dev`; web UI serves HTTP 200
over Tailscale at `https://forgejo-dev.burro-ph.ts.net/`, install-locked.

- **Image:** `codeberg.org/forgejo/forgejo:11` (pinned LTS)
- **Hostname:** `forgejo-dev` (`tag:private`), HTTPS on the `tailscale` Ingress
- **PVC:** `dev-forgejo-pvc`, 10Gi, `local-path-retain`, mounted `/data`
  (Forgejo `GITEA_WORK_DIR=/data`; SQLite DB + repos live under it)
- **Config:** `INSTALL_LOCK=true`, `DISABLE_REGISTRATION=true`, HTTP port 3000,
  `DOMAIN`/`ROOT_URL` set per-env in `dev.yaml`
- **Admin bootstrap (fog resolved):** CLI, not an ExternalSecret. Ran
  `forgejo admin user create --admin --username daniel --must-change-password=true`
  via `kubectl exec ... su git -c`, with a one-off random temp password. First
  web login forces a password change, so no credential is committed or
  long-lived. Repeat this one exec after any fresh install (empty PVC).

Files: `kubernetes/values/forgejo/{values,dev}.yaml`, `forgejo` release in
`helmfile.yaml.gotmpl` (guarded to dev+pro).
