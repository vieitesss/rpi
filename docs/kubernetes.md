# Kubernetes / Helmfile Conventions

## Environments

- Use `dev` by default.
- Only change `pro` when asked.

## Helmfile

- Deploy apps with `helmfile -e <env> sync` (avoid ad-hoc `kubectl apply`).
- Target one service with `-l name=<service>`.

## Values Layout

Service config lives in `kubernetes/values/<service>/`:

- `values.yaml`: shared defaults
- `dev.yaml` / `pro.yaml`: per-environment overrides

Keep values focused on the service.

## Generic Chart

Most services use the generic chart. Follow existing patterns and chart helpers for naming.

## Storage

PVCs are namespace-agnostic: `<service>-pvc` (supports cross-namespace restores).
