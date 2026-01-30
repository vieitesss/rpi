# Security

## Secrets

- Never commit secrets.
- Do not commit real credential files like `.env` or `.backup.env`.
- Use External Secrets Operator + GCP Secret Manager for Kubernetes secrets.
- Do not commit generated secret YAMLs.

## Safe Ops Defaults

- Prefer non-destructive, declarative changes.
- Validate in `dev` first.
- Avoid printing secrets in logs or command output.
