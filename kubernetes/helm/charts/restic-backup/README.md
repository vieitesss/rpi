# Restic Backup Chart

Automated PVC backups to Backblaze B2 using Restic with per-application repository isolation.

## Architecture

### Repository Structure

Each application gets its own isolated Restic repository within the B2 bucket:

```
b2:rpi-data:/kubernetes-pvcs/
├── dev/
│   ├── vaultwarden/     # Separate repo for dev vaultwarden
│   ├── ittools/         # Separate repo for dev ittools
│   └── ...
└── pro/
    ├── vaultwarden/     # Separate repo for pro vaultwarden
    ├── ittools/         # Separate repo for pro ittools
    └── ...
```

**Benefits:**
- Isolation: Each app's backups are independent
- Security: Compromised app credentials don't expose other apps' backups
- Deduplication: Restic deduplicates within each app's repository
- Flexibility: Different retention policies per app (future enhancement)
- Easier recovery: Restore specific apps without interference

### How It Works

1. **CronJob** runs daily at 23:00 UTC (configurable via `schedule`)
2. **Optional scale-down**: Deployments can be scaled to 0 before backup for consistency
3. **Backup**: All configured PVCs mounted under `/backup/<mountPath>` are backed up
4. **Repository**: Dynamic path `b2:<bucket>:/<basePath>/<namespace>/<appName>`
5. **Retention**: Old snapshots pruned according to policy (7 daily, 4 weekly, 6 monthly, 1 yearly)
6. **Optional verification**: Can run `restic check` after backup

## Configuration

### Required Values

Each namespace deployment **must** set `repository.appName`:

```yaml
# kubernetes/values/restic-backup/dev.yaml
repository:
  appName: vaultwarden  # REQUIRED: Application name for this deployment

pvcs:
  - name: dev-vaultwarden-pvc
    mountPath: /backup/vaultwarden
```

### Available Options

```yaml
# Backup schedule (cron format)
schedule: "0 23 * * *"  # Daily at 23:00 UTC

# Repository configuration
repository:
  bucket: "rpi-data"                    # B2 bucket name
  basePath: "kubernetes-pvcs"           # Base path in bucket
  appName: ""                           # REQUIRED: Application name (e.g., "vaultwarden")
  
  # Retention policy
  retention:
    keepDaily: 7      # Keep 7 daily snapshots
    keepWeekly: 4     # Keep 4 weekly snapshots
    keepMonthly: 6    # Keep 6 monthly snapshots
    keepYearly: 1     # Keep 1 yearly snapshot

# PVCs to backup (list all PVCs for this app)
pvcs:
  - name: dev-vaultwarden-pvc
    mountPath: /backup/vaultwarden

# Scale down deployments before backup (ensures data consistency)
scaleDown:
  enabled: false              # Enable to scale down before backup
  deployments:                # List of deployments to scale down
    - dev-vaultwarden
  waitSeconds: 10            # Wait time after scaling down

# External Secrets configuration
externalSecrets:
  enabled: true
  secretStoreName: gcp-cluster-secretstore
  b2AccountIdKey: rpi-b2-account-id
  b2AccountKeyKey: rpi-b2-account-key
  resticPasswordKey: restic_password

# Backup verification (optional)
verify:
  enabled: false    # Enable to run restic check after backup
  percentage: 5     # Check 5% of data
```

## Usage

### Manual Backup

Trigger a manual backup for an app:

```bash
bash kubernetes/scripts/restic-backup.sh <namespace> <app-name>

# Examples
bash kubernetes/scripts/restic-backup.sh dev vaultwarden
bash kubernetes/scripts/restic-backup.sh pro ittools
```

### List Snapshots

View all snapshots for an app:

```bash
bash kubernetes/scripts/restic-list.sh <namespace> <app-name>

# Example
bash kubernetes/scripts/restic-list.sh dev vaultwarden
```

### Restore from Backup

Restore data to a PVC:

```bash
bash kubernetes/scripts/restic-restore.sh <namespace> <app-name> [snapshot-id] [target-pvc] [source-namespace] [restic-release] [source-path]

# List available snapshots
bash kubernetes/scripts/restic-restore.sh dev vaultwarden

# Restore latest snapshot to PVC
bash kubernetes/scripts/restic-restore.sh dev vaultwarden latest dev-vaultwarden-pvc

# Restore specific snapshot
bash kubernetes/scripts/restic-restore.sh dev vaultwarden a1b2c3d4 dev-vaultwarden-pvc
```

### Selective Restore (Multiple PVCs)

If your app has multiple PVCs in the same repository, restore each snapshot path to the matching PVC:

```bash
# Restore AnythingLLM app data
bash kubernetes/scripts/restic-restore.sh pro anythingllm latest pro-anythingllm-pvc pro restic-backup-anythingllm /backup/anythingllm

# Restore AnythingLLM files
bash kubernetes/scripts/restic-restore.sh pro anythingllm latest anythingllm-files-pvc pro restic-backup-anythingllm /backup/anythingllm-files
```

## Migration

### Migrating from Old Global Repository

If you're upgrading from the old global repository structure (`b2:rpi-data:/kubernetes-pvcs`), use the migration script:

```bash
bash kubernetes/scripts/restic-migrate-to-app-repos.sh <namespace> <app-name>

# Example
bash kubernetes/scripts/restic-migrate-to-app-repos.sh dev vaultwarden
```

**What the migration does:**
1. Copies all snapshots for the specified namespace/app from the old repository
2. Initializes the new per-app repository if it doesn't exist
3. Verifies the migration with `restic check`
4. **Preserves the old repository** (does NOT delete snapshots)

**After migration:**
1. Update your values file to include `repository.appName`
2. Re-deploy the chart: `helmfile -l name=restic-backup apply -e <namespace>`
3. Verify with a manual backup
4. Keep the old repository as a safety backup or delete it once verified

## Deployment

Deploy to a namespace:

```bash
# Deploy to dev
helmfile -l name=restic-backup apply -e dev

# Deploy to pro
helmfile -l name=restic-backup apply -e pro
```

## Monitoring

### Check CronJob Status

```bash
kubectl get cronjob restic-backup -n dev
kubectl get cronjob restic-backup -n pro
```

### View Recent Jobs

```bash
kubectl get jobs -n dev -l app=restic-backup
kubectl get jobs -n pro -l app=restic-backup
```

### Check Logs

```bash
# Latest job
kubectl logs -n dev -l app=restic-backup --tail=100

# Specific job
kubectl logs -n dev job/restic-backup-manual-20250124-120000
```

## Security

- **Credentials**: Managed via External Secrets (GCP Secret Manager)
- **Encryption**: All data encrypted at rest in B2 with Restic's encryption
- **Isolation**: Each app has its own repository with separate encryption key
- **Access**: Kubernetes RBAC controls who can trigger backups/restores

## Troubleshooting

### Validation Error: "repository.appName is required"

Make sure you've set `repository.appName` in your environment-specific values file:

```yaml
# kubernetes/values/restic-backup/dev.yaml
repository:
  appName: vaultwarden
```

### Repository Not Found

If you see "repository does not exist" errors:
- First backup will automatically initialize the repository
- For restores, run migration script first if upgrading from old structure

### Failed to List Snapshots

Check that credentials are correct:

```bash
kubectl get secret restic-backup-credentials -n dev -o yaml
```

Ensure External Secrets is running:

```bash
kubectl get externalsecret restic-backup-external-secret -n dev
```

## Architecture Details

### Environment Variables

The CronJob sets these environment variables for the backup script:

- `NAMESPACE`: Target namespace (dev/pro)
- `RESTIC_REPOSITORY`: Dynamic path `b2:<bucket>:/<basePath>/<namespace>/<appName>`
- `RESTIC_PASSWORD`: Encryption password from secret
- `B2_ACCOUNT_ID`: Backblaze B2 account ID from secret
- `B2_ACCOUNT_KEY`: Backblaze B2 account key from secret
- `SCALE_DOWN_ENABLED`: Whether to scale down deployments
- `SCALE_DOWN_DEPLOYMENTS`: Comma-separated list of deployments
- `SCALE_DOWN_WAIT_SECONDS`: Wait time after scaling down

### Restic Tags

Snapshots are tagged with:
- `namespace=<namespace>` (e.g., `namespace=dev`)
- `cronjob=restic-backup`
- `--host <namespace>` (for filtering in multi-tenant repositories)

## See Also

- [Restic Documentation](https://restic.readthedocs.io/)
- [Backblaze B2 Setup](https://www.backblaze.com/b2/docs/)
- [Ops Workflows](../../../docs/ops.md)
