#!/bin/bash
set -euo pipefail

# Restic List Snapshots Script
# List all available restic snapshots for an app
# Usage: ./restic-list.sh <namespace> <app-name>
# Example: ./restic-list.sh dev vaultwarden

NAMESPACE=${1:-}
APP_NAME=${2:-}

if [ -z "$NAMESPACE" ] || [ -z "$APP_NAME" ]; then
    echo "Usage: $0 <namespace> <app-name>"
    echo ""
    echo "Arguments:"
    echo "  namespace - Kubernetes namespace (dev, pro)"
    echo "  app-name  - Application name (must match repository.appName)"
    echo ""
    echo "Examples:"
    echo "  $0 dev vaultwarden    # List snapshots for vaultwarden in dev"
    echo "  $0 pro vaultwarden    # List snapshots for vaultwarden in pro"
    echo "  $0 dev ittools        # List snapshots for ittools in dev"
    exit 1
fi

# Calculate repository path dynamically
RESTIC_REPO="b2:rpi-data:/kubernetes-pvcs/${NAMESPACE}/${APP_NAME}"

echo "========================================="
echo "Restic Snapshots"
echo "========================================="
echo "Namespace: $NAMESPACE"
echo "App: $APP_NAME"
echo "Repository: $RESTIC_REPO"
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
    --env="RESTIC_REPOSITORY=${RESTIC_REPO}" \
    --env="RESTIC_PASSWORD=$(kubectl get secret restic-backup-credentials -n $NAMESPACE -o jsonpath='{.data.RESTIC_PASSWORD}' | base64 -d)" \
    --env="B2_ACCOUNT_ID=$(kubectl get secret restic-backup-credentials -n $NAMESPACE -o jsonpath='{.data.B2_ACCOUNT_ID}' | base64 -d)" \
    --env="B2_ACCOUNT_KEY=$(kubectl get secret restic-backup-credentials -n $NAMESPACE -o jsonpath='{.data.B2_ACCOUNT_KEY}' | base64 -d)" \
    --command -- restic snapshots --host "$NAMESPACE"
