#!/bin/bash
set -euo pipefail

# Restic Backup Helper Script
# Manually trigger a backup job for a namespace
# Usage: ./restic-backup.sh <namespace>
# Example: ./restic-backup.sh dev

NAMESPACE=${1:-}

if [ -z "$NAMESPACE" ]; then
    echo "Usage: $0 <namespace>"
    echo ""
    echo "Examples:"
    echo "  $0 dev    # Trigger backup for dev namespace"
    echo "  $0 pro    # Trigger backup for pro namespace"
    exit 1
fi

echo "Triggering manual backup for namespace: $NAMESPACE"
echo ""

# Create a job from the CronJob
JOB_NAME="restic-backup-manual-$(date +%Y%m%d-%H%M%S)"

kubectl create job "$JOB_NAME" \
    --from=cronjob/restic-backup \
    -n "$NAMESPACE"

echo "Job created: $JOB_NAME"
echo ""
echo "Follow logs with:"
echo "  kubectl logs -f job/$JOB_NAME -n $NAMESPACE"
echo ""
echo "Check job status with:"
echo "  kubectl get job $JOB_NAME -n $NAMESPACE"
