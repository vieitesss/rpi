# Security

## Secrets

- Never commit secrets.
- Do not commit real credential files like `.env` or `.backup.env`.
- Use External Secrets Operator + GCP Secret Manager for Kubernetes secrets.
- Do not commit generated secret YAMLs.

### ExternalSecret refresh (GCP Secret Manager cost control) — REQUIRED

- Every `ExternalSecret` MUST set `refreshInterval: "0"` (no periodic refresh). GCP
  Secret Manager bills per access; hourly refresh across all secrets was doing
  ~20k requests/month for values that never change.
- `0` means ESO only reads the provider on ExternalSecret create/spec-change.
  Our secrets are static and managed via GitOps, so a rotation is picked up by
  re-syncing the release: `helmfile -e <env> -l name=<service> sync`.
- Never set a time-based `refreshInterval` (e.g. `1h`, `24h`) unless a secret
  genuinely rotates out-of-band AND the app cannot tolerate a redeploy to pick
  it up. If you must, use the longest interval that works and note why.
- The generic and restic-backup charts default to `"0"`; do not override it back
  to a time interval in per-service values.

## Safe Ops Defaults

- Prefer non-destructive, declarative changes.
- Validate in `dev` first.
- Avoid printing secrets in logs or command output.
