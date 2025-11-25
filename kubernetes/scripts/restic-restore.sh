#!/bin/bash
set -euo pipefail

# Restic Restore Helper Script
# Restore PVCs from restic backup
# Usage: ./restic-restore.sh <namespace> <snapshot-id> <target-pvc>
# Example: ./restic-restore.sh dev latest dev-vaultwarden-pvc

NAMESPACE=${1:-}
SNAPSHOT_ID=${2:-latest}
TARGET_PVC=${3:-}

if [ -z "$NAMESPACE" ]; then
    echo "Usage: $0 <namespace> [snapshot-id] [target-pvc]"
    echo ""
    echo "Arguments:"
    echo "  namespace    - Kubernetes namespace (dev, pro)"
    echo "  snapshot-id  - Restic snapshot ID or 'latest' (default: latest)"
    echo "  target-pvc   - Target PVC to restore to (optional - creates temp PVC if not specified)"
    echo ""
    echo "Examples:"
    echo "  $0 dev                                    # List available snapshots"
    echo "  $0 dev latest                             # Restore latest to temp PVC"
    echo "  $0 dev latest dev-vaultwarden-pvc         # Restore to existing PVC"
    echo "  $0 dev a1b2c3d4                           # Restore specific snapshot"
    exit 1
fi

echo "========================================="
echo "Restic Restore Helper"
echo "========================================="
echo "Namespace: $NAMESPACE"
echo "Snapshot: $SNAPSHOT_ID"
echo "Target PVC: ${TARGET_PVC:-<will create temp PVC>}"
echo ""

# List available snapshots first
echo "Available snapshots for $NAMESPACE:"
echo ""

echo "Checking for available snapshots..."
if kubectl get cronjob restic-backup -n "$NAMESPACE" &>/dev/null; then
    TEMP_POD_NAME="restic-list-temp-$(date +%s)"
    cleanup_temp_pod() {
        kubectl delete pod "$TEMP_POD_NAME" -n "$NAMESPACE" --ignore-not-found &>/dev/null || true
    }
    trap cleanup_temp_pod EXIT ERR
    kubectl run "$TEMP_POD_NAME" \
        --image=restic/restic:0.18.1 \
        --restart=Never \
        -n "$NAMESPACE" \
        --rm \
        -i \
        --quiet \
        --env="RESTIC_REPOSITORY=b2:rpi-data:/kubernetes-pvcs" \
        --env="RESTIC_PASSWORD=$(kubectl get secret restic-backup-credentials -n "$NAMESPACE" -o jsonpath='{.data.RESTIC_PASSWORD}' | base64 -d)" \
        --env="B2_ACCOUNT_ID=$(kubectl get secret restic-backup-credentials -n "$NAMESPACE" -o jsonpath='{.data.B2_ACCOUNT_ID}' | base64 -d)" \
        --env="B2_ACCOUNT_KEY=$(kubectl get secret restic-backup-credentials -n "$NAMESPACE" -o jsonpath='{.data.B2_ACCOUNT_KEY}' | base64 -d)" \
        --command -- restic snapshots --host "$NAMESPACE" 2>/dev/null || {
        echo "Note: No snapshots available yet for $NAMESPACE"
    }
else
    echo "Note: restic-backup not deployed yet"
    echo ""
    echo "To deploy restic-backup:"
    echo "  helmfile -l name=restic-backup apply -e $NAMESPACE"
fi

if [ -z "$TARGET_PVC" ]; then
    echo ""
    echo "========================================="
    echo "Restore Instructions"
    echo "========================================="
    echo ""
    echo "No target PVC specified. Use one of these commands:"
    echo ""
    echo "  $0 $NAMESPACE $SNAPSHOT_ID ${NAMESPACE}-vaultwarden-pvc    # Restore to vaultwarden PVC"
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
POD_NAME="restic-restore-$(date +%s)"

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: Template file not found: $TEMPLATE_FILE"
    exit 1
fi

# Create temporary file with substituted values
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

sed -e "s/{{RESTORE_POD_NAME}}/$POD_NAME/g" \
    -e "s/{{NAMESPACE}}/$NAMESPACE/g" \
    -e "s/{{SNAPSHOT_ID}}/$SNAPSHOT_ID/g" \
    -e "s/{{TARGET_PVC}}/$TARGET_PVC/g" \
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
