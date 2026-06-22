#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/lib/restic.sh"

# Restic Restore Helper Script
# Restore PVCs from restic backup
# Usage: ./restic-restore.sh <namespace> <app-name> <snapshot-id> <target-pvc> [source-namespace] [restic-release] [source-path]
# Example: ./restic-restore.sh dev vaultwarden latest dev-vaultwarden-pvc
# Example (restore pro backup into dev): ./restic-restore.sh dev tandem latest dev-tandem-backend-pvc pro restic-backup-tandem /backup/tandem

NAMESPACE=${1:-}
APP_NAME=${2:-}
SNAPSHOT_ID=${3:-latest}
TARGET_PVC=${4:-}
SOURCE_NAMESPACE=${5:-${RESTIC_SOURCE_NAMESPACE:-$NAMESPACE}}
RESTIC_RELEASE=${6:-${RESTIC_RELEASE_NAME:-restic-backup}}
RESTORE_SOURCE_PATH=${7:-${RESTIC_RESTORE_SOURCE_PATH:-/backup/$APP_NAME}}
SCRIPTS_CONFIGMAP="${RESTIC_RELEASE}-scripts"
CREDENTIALS_SECRET=$(restic_credentials_secret "$RESTIC_RELEASE")

if [ -z "$NAMESPACE" ] || [ -z "$APP_NAME" ]; then
    echo "Usage: $0 <namespace> <app-name> [snapshot-id] [target-pvc] [source-namespace] [restic-release] [source-path]"
    echo ""
    echo "Arguments:"
    echo "  namespace    - Kubernetes namespace (dev, pro)"
    echo "  app-name     - Application name (must match repository.appName)"
    echo "  snapshot-id  - Restic snapshot ID or 'latest' (default: latest)"
    echo "  target-pvc   - Target PVC to restore to (optional - lists snapshots if not specified)"
    echo "  source-namespace - Source backup namespace in B2 (default: namespace)"
    echo "  restic-release - Release name that provides scripts/credentials (default: restic-backup)"
    echo "  source-path - Path inside the snapshot to restore (default: /backup/<app-name>)"
    echo ""
    echo "Examples:"
    echo "  $0 dev vaultwarden                                # List available snapshots"
    echo "  $0 dev vaultwarden latest                         # Info about latest snapshot"
    echo "  $0 dev vaultwarden latest dev-vaultwarden-pvc     # Restore to existing PVC"
    echo "  $0 dev tandem latest dev-tandem-backend-pvc pro   # Restore pro backup to dev"
    echo "  $0 dev tandem latest dev-tandem-backend-pvc pro restic-backup-tandem /backup/tandem"
    echo "  $0 pro anythingllm latest anythingllm-files-pvc pro restic-backup-anythingllm /backup/anythingllm-files"
    echo "  $0 dev vaultwarden a1b2c3d4 dev-vaultwarden-pvc   # Restore specific snapshot"
    exit 1
fi

if [[ "$RESTORE_SOURCE_PATH" != /* ]]; then
    echo "Error: source-path must be absolute inside the snapshot (example: /backup/$APP_NAME)"
    exit 1
fi

if [ "$SOURCE_NAMESPACE" = "$NAMESPACE" ]; then
    RESTIC_REPO=$(restic_repository "$NAMESPACE" "$APP_NAME" "$RESTIC_RELEASE")
else
    RESTIC_REPO=$(restic_default_repository "$SOURCE_NAMESPACE" "$APP_NAME")
fi

echo "========================================="
echo "Restic Restore Helper"
echo "========================================="
echo "Namespace: $NAMESPACE"
echo "Source Namespace: $SOURCE_NAMESPACE"
echo "App: $APP_NAME"
echo "Restic Release: $RESTIC_RELEASE"
echo "Repository: $RESTIC_REPO"
echo "Snapshot: $SNAPSHOT_ID"
echo "Target PVC: ${TARGET_PVC:-<none - will list snapshots>}"
echo "Source path: $RESTORE_SOURCE_PATH"
echo ""

# List available snapshots first
echo "Available snapshots for $SOURCE_NAMESPACE/$APP_NAME:"
echo ""

echo "Checking for available snapshots..."
if kubectl get cronjob "$RESTIC_RELEASE" -n "$NAMESPACE" &>/dev/null; then
    restic_exec_repo "$NAMESPACE" "$RESTIC_REPO" "$RESTIC_RELEASE" -- snapshots --host "$SOURCE_NAMESPACE" 2>/dev/null || {
        echo "Note: No snapshots available yet for $SOURCE_NAMESPACE/$APP_NAME"
        echo ""
        echo "Repository may not be initialized yet. First backup will create it."
    }
else
    echo "Note: $RESTIC_RELEASE not deployed yet"
    echo ""
    echo "To deploy $RESTIC_RELEASE:"
    echo "  helmfile -l name=$RESTIC_RELEASE apply -e $NAMESPACE"
fi

if [ -z "$TARGET_PVC" ]; then
    echo ""
    echo "========================================="
    echo "Restore Instructions"
    echo "========================================="
    echo ""
    echo "No target PVC specified. Use one of these commands:"
    echo ""
    echo "  $0 $NAMESPACE $APP_NAME $SNAPSHOT_ID ${NAMESPACE}-${APP_NAME}-pvc $SOURCE_NAMESPACE $RESTIC_RELEASE $RESTORE_SOURCE_PATH    # Restore to PVC"
    echo ""
    exit 0
fi

echo ""
echo "========================================="
echo "Starting Restore"
echo "========================================="
echo ""

# Use template file
TEMPLATE_FILE="$HOME/rpi/kubernetes/templates/restic-restore-job.yaml"
POD_NAME="restic-restore-$(date +%s)-$$"

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: Template file not found: $TEMPLATE_FILE"
    exit 1
fi

# Create temporary file with substituted values
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

sed -e "s/{{RESTORE_POD_NAME}}/$POD_NAME/g" \
    -e "s/{{NAMESPACE}}/$NAMESPACE/g" \
    -e "s|{{RESTIC_IMAGE}}|$RESTIC_IMAGE|g" \
    -e "s|{{RESTIC_REPOSITORY}}|$RESTIC_REPO|g" \
    -e "s/{{SNAPSHOT_ID}}/$SNAPSHOT_ID/g" \
    -e "s/{{TARGET_PVC}}/$TARGET_PVC/g" \
    -e "s|{{RESTORE_SOURCE_PATH}}|$RESTORE_SOURCE_PATH|g" \
    -e "s/{{RESTIC_HOST}}/$SOURCE_NAMESPACE/g" \
    -e "s/{{SCRIPTS_CONFIGMAP}}/$SCRIPTS_CONFIGMAP/g" \
    -e "s/{{CREDENTIALS_SECRET}}/$CREDENTIALS_SECRET/g" \
    "$TEMPLATE_FILE" > "$TEMP_FILE"

echo "Creating restore pod: $POD_NAME"
kubectl apply -f "$TEMP_FILE"

echo ""
echo "Waiting for restore to complete..."
echo "Following logs:"
echo ""

# Wait for pod to be ready and follow logs
kubectl wait --for=condition=Ready pod/"$POD_NAME" -n "$NAMESPACE" --timeout=60s 2>/dev/null || true
kubectl logs -f "$POD_NAME" -n "$NAMESPACE" 2>/dev/null || true

echo ""
echo "========================================="
echo "Restore Complete"
echo "========================================="
echo ""
echo "To clean up the restore pod:"
echo "  kubectl delete pod $POD_NAME -n $NAMESPACE"
