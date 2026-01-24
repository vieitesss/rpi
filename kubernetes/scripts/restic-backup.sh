#!/bin/bash
set -euo pipefail

# Restic Backup Helper Script
# Manually trigger a backup job for a specific app
# Usage: ./restic-backup.sh <namespace> <app-name>
# Example: ./restic-backup.sh dev vaultwarden

NAMESPACE=${1:-}
APP_NAME=${2:-}

if [ -z "$NAMESPACE" ] || [ -z "$APP_NAME" ]; then
    echo "Usage: $0 <namespace> <app-name>"
    echo ""
    echo "Arguments:"
    echo "  namespace - Kubernetes namespace (dev, pro)"
    echo "  app-name  - Application name (must match repository.appName in values)"
    echo ""
    echo "Examples:"
    echo "  $0 dev vaultwarden    # Trigger backup for vaultwarden in dev"
    echo "  $0 pro vaultwarden    # Trigger backup for vaultwarden in pro"
    echo "  $0 dev ittools        # Trigger backup for ittools in dev"
    exit 1
fi

# Calculate repository path dynamically
RESTIC_REPO="b2:rpi-data:/kubernetes-pvcs/${NAMESPACE}/${APP_NAME}"

echo "========================================="
echo "Restic Manual Backup"
echo "========================================="
echo "Namespace: $NAMESPACE"
echo "App: $APP_NAME"
echo "Repository: $RESTIC_REPO"
echo ""

# Verify CronJob exists and has correct app config
CRONJOB_REPO=$(kubectl get cronjob restic-backup -n "$NAMESPACE" -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].env[?(@.name=="RESTIC_REPOSITORY")].value}')
EXPECTED_REPO="b2:rpi-data:/kubernetes-pvcs/${NAMESPACE}/${APP_NAME}"

if [ "$CRONJOB_REPO" != "$EXPECTED_REPO" ]; then
    echo "⚠️  WARNING: CronJob repository mismatch!"
    echo "   CronJob has: $CRONJOB_REPO"
    echo "   Expected:    $EXPECTED_REPO"
    echo ""
    echo "Please re-deploy the restic-backup chart:"
    echo "  helmfile -l name=restic-backup apply -e $NAMESPACE"
    exit 1
fi

# Create a job from the CronJob (repository already correct in CronJob)
JOB_NAME="restic-backup-manual-$(date +%Y%m%d-%H%M%S)"

echo "Creating job from CronJob..."
kubectl create job "$JOB_NAME" \
    --from=cronjob/restic-backup \
    -n "$NAMESPACE"

echo ""
echo "========================================="
echo "Job created: $JOB_NAME"
echo "========================================="
echo ""
echo "Follow logs with:"
echo "  kubectl logs -f job/$JOB_NAME -n $NAMESPACE"
echo ""
echo "Check job status with:"
echo "  kubectl get job $JOB_NAME -n $NAMESPACE"
