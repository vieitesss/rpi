#!/bin/bash
set -euo pipefail

# Restic List Snapshots Script
# List all available restic snapshots for an app
# Usage: ./restic-list.sh <namespace> <app-name> [restic-release]
# Example: ./restic-list.sh dev vaultwarden

NAMESPACE=${1:-}
APP_NAME=${2:-}
RESTIC_RELEASE=${3:-${RESTIC_RELEASE_NAME:-restic-backup}}
CREDENTIALS_SECRET="${RESTIC_RELEASE}-credentials"

if [ -z "$NAMESPACE" ] || [ -z "$APP_NAME" ]; then
    echo "Usage: $0 <namespace> <app-name> [restic-release]"
    echo ""
    echo "Arguments:"
    echo "  namespace      - Kubernetes namespace (dev, pro)"
    echo "  app-name       - Application name (must match repository.appName)"
    echo "  restic-release - CronJob/release to use for credentials (default: restic-backup)"
    echo ""
    echo "Examples:"
    echo "  $0 dev vaultwarden                         # List vaultwarden snapshots in dev"
    echo "  $0 pro vaultwarden                         # List vaultwarden snapshots in pro"
    echo "  $0 dev tandem restic-backup-tandem         # List tandem snapshots in dev"
    echo "  $0 dev anythingllm restic-backup-anythingllm"
    exit 1
fi

# Calculate repository path dynamically
RESTIC_REPO="b2:rpi-data:/kubernetes-pvcs/${NAMESPACE}/${APP_NAME}"

if ! kubectl get cronjob "$RESTIC_RELEASE" -n "$NAMESPACE" &>/dev/null; then
    echo "Error: CronJob $RESTIC_RELEASE not found in namespace $NAMESPACE"
    echo ""
    echo "Deploy it first with:"
    echo "  helmfile -l name=$RESTIC_RELEASE apply -e $NAMESPACE"
    exit 1
fi

echo "========================================="
echo "Restic Snapshots"
echo "========================================="
echo "Namespace: $NAMESPACE"
echo "App: $APP_NAME"
echo "Restic Release: $RESTIC_RELEASE"
echo "Repository: $RESTIC_REPO"
echo ""

# Create a temporary pod to run restic list
POD_NAME="restic-list-$(date +%s)-$$"

kubectl run "$POD_NAME" \
    --image=restic/restic:0.18.1 \
    --restart=Never \
    -n "$NAMESPACE" \
    --rm \
    -i \
    --quiet \
    --env="RESTIC_REPOSITORY=${RESTIC_REPO}" \
    --env="RESTIC_PASSWORD=$(kubectl get secret "$CREDENTIALS_SECRET" -n "$NAMESPACE" -o jsonpath='{.data.RESTIC_PASSWORD}' | base64 -d)" \
    --env="B2_ACCOUNT_ID=$(kubectl get secret "$CREDENTIALS_SECRET" -n "$NAMESPACE" -o jsonpath='{.data.B2_ACCOUNT_ID}' | base64 -d)" \
    --env="B2_ACCOUNT_KEY=$(kubectl get secret "$CREDENTIALS_SECRET" -n "$NAMESPACE" -o jsonpath='{.data.B2_ACCOUNT_KEY}' | base64 -d)" \
    --command -- restic snapshots --host "$NAMESPACE"
