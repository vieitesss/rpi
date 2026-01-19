# Security

## Secrets

- Keep secrets out of Git.
- Do not commit real credential files like `.env` or `.backup.env`.
- Prefer External Secrets Operator + GCP Secret Manager for Kubernetes secrets.
- Avoid committing generated secret YAMLs.

## Safe Ops Defaults

- Prefer non-destructive, declarative changes.
- Validate in `dev` first.
- Avoid printing secret values in logs or command output.
