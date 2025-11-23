#!/bin/bash
set -euo pipefail

# Restic List Snapshots Script
# List all available restic snapshots for a namespace
# Usage: ./restic-list.sh <namespace>
# Example: ./restic-list.sh dev

NAMESPACE=${1:-}

if [ -z "$NAMESPACE" ]; then
    echo "Usage: $0 <namespace>"
    echo ""
    echo "Examples:"
    echo "  $0 dev    # List snapshots for dev namespace"
    echo "  $0 pro    # List snapshots for pro namespace"
    exit 1
fi

echo "Restic Snapshots for: $NAMESPACE"
echo ""

# Check if CronJob exists
if ! kubectl get cronjob restic-backup -n "$NAMESPACE" &>/dev/null; then
    echo "Error: restic-backup CronJob not found in namespace $NAMESPACE"
    echo ""
    echo "Deploy it first with:"
    echo "  helmfile -l name=restic-backup apply -e $NAMESPACE"
    exit 1
fi

# Create a temporary pod to run restic list
POD_NAME="restic-list-$(date +%s)"

kubectl run "$POD_NAME" \
    --image=restic/restic:0.18.1 \
    --restart=Never \
    -n "$NAMESPACE" \
    --rm \
    -i \
    --quiet \
    --env="RESTIC_REPOSITORY=b2:rpi-data:/kubernetes-pvcs" \
    --env="RESTIC_PASSWORD=$(kubectl get secret restic-backup-credentials -n $NAMESPACE -o jsonpath='{.data.RESTIC_PASSWORD}' | base64 -d)" \
    --env="B2_ACCOUNT_ID=$(kubectl get secret restic-backup-credentials -n $NAMESPACE -o jsonpath='{.data.B2_ACCOUNT_ID}' | base64 -d)" \
    --env="B2_ACCOUNT_KEY=$(kubectl get secret restic-backup-credentials -n $NAMESPACE -o jsonpath='{.data.B2_ACCOUNT_KEY}' | base64 -d)" \
    --command -- restic snapshots --host "$NAMESPACE"
