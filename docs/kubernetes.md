# Kubernetes / Helmfile Conventions

## Environments

- `dev` is the default proving ground.
- Avoid changing `pro` unless explicitly asked.

## Helmfile

- Helmfile drives deployments; prefer `helmfile -e <env> sync` over ad-hoc `kubectl apply` for app changes.
- When iterating on one service, use a label selector (e.g., `-l name=<service>`).

## Values Layout

Service configuration lives under `kubernetes/values/<service>/`:

- `values.yaml`: shared defaults
- `dev.yaml` / `pro.yaml`: environment overrides

Keep values small and focused on the service.

## Generic Chart

Most services use the generic chart. Follow existing patterns in values files and keep resource naming consistent with chart helpers.

## Storage

PVC naming is namespace-agnostic (`<service>-pvc`) to support cross-namespace restores.
