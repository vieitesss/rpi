# Raspberry Pi Homelab

GitOps homelab for a single Raspberry Pi. Services are deployed on Kubernetes
(K3s + Helmfile) from a shared Helm chart, with secrets from GCP Secret Manager
and per-service backups to Backblaze B2.

## Documentation

- [`AGENTS.md`](./AGENTS.md) — conventions, workflow, and operational notes.
- [`CONTEXT.md`](./CONTEXT.md) — project glossary.
- [`docs/`](./docs) — security model, backups, and design records.
- [`system/README.md`](./system/README.md) — host-level systemd/apt configuration.

## Prerequisites

- K3s
- Helmfile
- Tailscale account

## Configuration

Set the Tailscale auth key used by the operator install script:

```bash
cp example.env .env
```

Application secrets are not stored in env files — they live in GCP Secret
Manager and are pulled into the cluster via External Secrets. See
[`docs/security.md`](./docs/security.md).
