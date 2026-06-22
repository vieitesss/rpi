#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/lib/restic.sh"

# Restic Backup Helper Script
# Manually trigger a backup job for a specific app
# Usage: ./restic-backup.sh <namespace> <app-name> [restic-release]
# Example: ./restic-backup.sh dev vaultwarden

NAMESPACE=${1:-}
APP_NAME=${2:-}
RESTIC_RELEASE=${3:-${RESTIC_RELEASE_NAME:-restic-backup}}

if [ -z "$NAMESPACE" ] || [ -z "$APP_NAME" ]; then
    echo "Usage: $0 <namespace> <app-name> [restic-release]"
    echo ""
    echo "Arguments:"
    echo "  namespace      - Kubernetes namespace (dev, pro)"
    echo "  app-name       - Application name (must match repository.appName in values)"
    echo "  restic-release - CronJob/release to use (default: restic-backup)"
    echo ""
    echo "Examples:"
    echo "  $0 dev vaultwarden                         # Trigger vaultwarden backup in dev"
    echo "  $0 pro vaultwarden                         # Trigger vaultwarden backup in pro"
    echo "  $0 dev tandem restic-backup-tandem         # Trigger tandem backup in dev"
    echo "  $0 dev anythingllm restic-backup-anythingllm"
    exit 1
fi

RESTIC_REPO=$(restic_default_repository "$NAMESPACE" "$APP_NAME")

if ! kubectl get cronjob "$RESTIC_RELEASE" -n "$NAMESPACE" &>/dev/null; then
    echo "Error: CronJob $RESTIC_RELEASE not found in namespace $NAMESPACE"
    echo ""
    echo "Deploy it first with:"
    echo "  helmfile -l name=$RESTIC_RELEASE apply -e $NAMESPACE"
    exit 1
fi

echo "========================================="
echo "Restic Manual Backup"
echo "========================================="
echo "Namespace: $NAMESPACE"
echo "App: $APP_NAME"
echo "Restic Release: $RESTIC_RELEASE"
echo "Repository: $RESTIC_REPO"
echo ""

# Verify CronJob exists and has correct app config
CRONJOB_REPO=$(restic_cronjob_repository "$NAMESPACE" "$RESTIC_RELEASE")
EXPECTED_REPO=$(restic_default_repository "$NAMESPACE" "$APP_NAME")

if [ "$CRONJOB_REPO" != "$EXPECTED_REPO" ]; then
    echo "⚠️  WARNING: CronJob repository mismatch!"
    echo "   CronJob has: $CRONJOB_REPO"
    echo "   Expected:    $EXPECTED_REPO"
    echo ""
    echo "Please re-deploy the restic-backup chart:"
    echo "  helmfile -l name=$RESTIC_RELEASE apply -e $NAMESPACE"
    exit 1
fi

# Create a job from the CronJob (repository already correct in CronJob)
JOB_NAME="${RESTIC_RELEASE}-manual-$(date +%Y%m%d-%H%M%S)-$$"

if [ "${#JOB_NAME}" -gt 63 ]; then
    JOB_NAME="restic-manual-$(date +%Y%m%d-%H%M%S)-$$"
fi

echo "Creating job from CronJob..."
kubectl create job "$JOB_NAME" \
    --from=cronjob/"$RESTIC_RELEASE" \
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
