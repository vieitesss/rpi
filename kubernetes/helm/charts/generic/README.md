# Generic Helm Chart

A flexible, reusable Helm chart for deploying containerized services with Tailscale integration.

## Overview

This generic chart eliminates the need for service-specific charts. Deploy any containerized application by providing values files.

**Supported Resources:**
- Deployment (always enabled)
- Service (ClusterIP)
- Ingress (Tailscale with automatic TLS)
- PersistentVolumeClaim
- ConfigMap (environment variables)
- Secret (sensitive data)

## Configuration

### Required Values

```yaml
deployment:
  image: your-image:tag  # REQUIRED
```

### Common Options

```yaml
# Service
service:
  enabled: true
  port: 80
  targetPort: 80

# Tailscale Ingress
ingress:
  enabled: true
  hostname: myapp-dev  # defaults to release name
  domain: burro-ph.ts.net
  tags: "tag:private"  # optional

# Persistent Storage
pvc:
  enabled: true
  storage: "10Gi"
  mountPath: /data

# Environment Variables
cm:
  data:
    ENV_VAR: value

# Deployment
deployment:
  replicas: 1
  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "256Mi"
      cpu: "200m"
```

## Usage Example

**values.yaml** (base config):
```yaml
deployment:
  image: vaultwarden/server:latest

service:
  enabled: true

ingress:
  enabled: true

pvc:
  enabled: true

cm:
  data:
    DOMAIN: https://vaultwarden.burro-ph.ts.net
```

**dev.yaml** (environment override):
```yaml
ingress:
  hostname: vaultwarden-dev

cm:
  data:
    DOMAIN: https://vaultwarden-dev.burro-ph.ts.net
```

**Deploy:**
```bash
helmfile -e dev -l name=vaultwarden apply
```

**Result:** Service accessible at `https://vaultwarden-dev.burro-ph.ts.net`

## Naming Convention

All resources are named: `<namespace>-<release-name>[-suffix]`

Example (release: `vaultwarden`, namespace: `pro`):
- Deployment: `pro-vaultwarden`
- Service: `pro-vaultwarden-svc`
- Ingress: `pro-vaultwarden-ingress`
- PVC: `pro-vaultwarden-pvc`

## Adding a New Service

1. Create values directory: `kubernetes/values/myservice/`
2. Create `values.yaml` with base config
3. Create `dev.yaml` and `pro.yaml` with environment overrides
4. Add release to `helmfile.yaml.gotmpl`:
   ```yaml
   releases:
   - name: myservice
     inherit:
     - template: default
   ```
5. Deploy: `helmfile -e dev -l name=myservice apply`

## Tailscale Ingress

**Important:** Each service needs a unique hostname in your Tailnet. Hostname conflicts prevent TLS certificate provisioning.

The chart creates an Ingress with `ingressClassName: tailscale`. The Tailscale Operator automatically:
- Creates a proxy pod in `tailscale` namespace
- Registers hostname in your Tailnet
- Provisions TLS certificate
- Makes service accessible at `https://<hostname>.<domain>`

## See Also

- Example deployment: `kubernetes/values/vaultwarden/`
- Helmfile config: `helmfile.yaml.gotmpl`
- Full values reference: `values.yaml`
