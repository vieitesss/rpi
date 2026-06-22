#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/lib/restic.sh"

# Restic Migration Script
# Migrate snapshots from the old global repository to new per-app repositories
# Usage: ./restic-migrate-to-app-repos.sh <namespace> <app-name>
# Example: ./restic-migrate-to-app-repos.sh dev vaultwarden

NAMESPACE=${1:-}
APP_NAME=${2:-}
RESTIC_RELEASE=${RESTIC_RELEASE_NAME:-restic-backup}

if [ -z "$NAMESPACE" ] || [ -z "$APP_NAME" ]; then
    echo "Usage: $0 <namespace> <app-name>"
    echo ""
    echo "Arguments:"
    echo "  namespace - Kubernetes namespace (dev, pro)"
    echo "  app-name  - Application name (must match repository.appName)"
    echo ""
    echo "Examples:"
    echo "  $0 dev vaultwarden    # Migrate vaultwarden snapshots from dev"
    echo "  $0 pro vaultwarden    # Migrate vaultwarden snapshots from pro"
    echo ""
    echo "IMPORTANT: This script will:"
    echo "  1. Copy snapshots from the old global repository to the new app-specific repo"
    echo "  2. Initialize the new repository if it doesn't exist"
    echo "  3. Keep the old repository intact (snapshots will NOT be deleted)"
    echo ""
    exit 1
fi

# Repository paths
OLD_REPO=$(restic_global_repository)
NEW_REPO=$(restic_default_repository "$NAMESPACE" "$APP_NAME")

echo "========================================="
echo "Restic Migration to Per-App Repositories"
echo "========================================="
echo "Namespace: $NAMESPACE"
echo "App: $APP_NAME"
echo ""
echo "Source (old): $OLD_REPO"
echo "Target (new): $NEW_REPO"
echo ""
echo "WARNING: This will copy all snapshots for this namespace/app"
echo "         from the old global repository to the new app-specific repository."
echo ""
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Migration cancelled."
    exit 0
fi

# Check if CronJob exists
if ! restic_cronjob_exists "$NAMESPACE" "$RESTIC_RELEASE"; then
    echo "Error: $RESTIC_RELEASE CronJob not found in namespace $NAMESPACE"
    echo ""
    echo "Deploy it first with:"
    echo "  helmfile -l name=$RESTIC_RELEASE apply -e $NAMESPACE"
    exit 1
fi

# Get credentials from secret
echo ""
echo "Retrieving credentials from Kubernetes secret..."

# Create temporary pod for migration
POD_NAME="restic-migrate-$(date +%s)-$$"
CLEANUP_POD=false

cleanup() {
    if [ "$CLEANUP_POD" = true ]; then
        echo ""
        echo "Cleaning up temporary pod..."
        kubectl delete pod "$POD_NAME" -n "$NAMESPACE" --ignore-not-found &>/dev/null || true
    fi
}
trap cleanup EXIT

echo "Creating temporary migration pod: $POD_NAME"
echo ""

# Create pod with both repository credentials
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $POD_NAME
  namespace: $NAMESPACE
spec:
  restartPolicy: Never
  containers:
  - name: restic
    image: $RESTIC_IMAGE
    command: ["/bin/sh", "-c", "sleep 3600"]
    env:
    - name: OLD_REPO
      value: "$OLD_REPO"
    - name: NEW_REPO
      value: "$NEW_REPO"
    - name: NAMESPACE
      value: "$NAMESPACE"
    envFrom:
    - secretRef:
        name: $(restic_credentials_secret "$RESTIC_RELEASE")
EOF

CLEANUP_POD=true

# Wait for pod to be ready
echo "Waiting for pod to be ready..."
kubectl wait --for=condition=Ready pod/"$POD_NAME" -n "$NAMESPACE" --timeout=60s

echo ""
echo "========================================="
echo "Step 1: Checking old repository"
echo "========================================="
echo ""

# List snapshots in old repository
echo "Listing snapshots in old repository (filtered by host=$NAMESPACE)..."
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- sh -c "
    export RESTIC_REPOSITORY=\$OLD_REPO
    restic snapshots --host $NAMESPACE --compact
" || {
    echo "Error: Failed to list snapshots in old repository"
    echo "The repository may not exist or credentials are incorrect"
    exit 1
}

echo ""
echo "========================================="
echo "Step 2: Initializing new repository"
echo "========================================="
echo ""

# Initialize new repository if it doesn't exist
echo "Checking if new repository exists..."
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- sh -c "
    export RESTIC_REPOSITORY=\$NEW_REPO
    if ! restic snapshots > /dev/null 2>&1; then
        echo 'Repository not found. Initializing new repository...'
        restic init
        echo 'Repository initialized successfully!'
    else
        echo 'Repository already exists. Skipping initialization.'
    fi
"

echo ""
echo "========================================="
echo "Step 3: Copying snapshots"
echo "========================================="
echo ""

echo "Copying snapshots from old repository to new repository..."
echo "This may take a while depending on the number and size of snapshots..."
echo ""

# Use restic copy to migrate snapshots
# Setting RESTIC_FROM_PASSWORD explicitly for --from-repo
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- sh -c "
    export RESTIC_REPOSITORY=\$NEW_REPO
    export RESTIC_FROM_PASSWORD=\$${RESTIC_PASSWORD_KEY}
    restic copy \
        --from-repo \$OLD_REPO \
        --host $NAMESPACE \
        --verbose
" || {
    echo ""
    echo "Error: Failed to copy snapshots"
    exit 1
}

echo ""
echo "========================================="
echo "Step 4: Verifying migration"
echo "========================================="
echo ""

echo "Listing snapshots in new repository..."
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- sh -c "
    export RESTIC_REPOSITORY=\$NEW_REPO
    restic snapshots --compact
"

echo ""
echo "Checking repository integrity..."
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- sh -c "
    export RESTIC_REPOSITORY=\$NEW_REPO
    restic check
"

echo ""
echo "========================================="
echo "Migration Complete!"
echo "========================================="
echo ""
echo "Summary:"
echo "  - Old repository: $OLD_REPO (preserved - NOT deleted)"
echo "  - New repository: $NEW_REPO"
echo "  - Namespace: $NAMESPACE"
echo "  - App: $APP_NAME"
echo ""
echo "Next steps:"
echo "  1. Re-deploy restic-backup with new configuration:"
echo "     helmfile -l name=restic-backup apply -e $NAMESPACE"
echo ""
echo "  2. Trigger a manual backup to verify:"
echo "     ./kubernetes/scripts/restic-backup.sh $NAMESPACE $APP_NAME"
echo ""
echo "  3. List snapshots in new repository:"
echo "     ./kubernetes/scripts/restic-list.sh $NAMESPACE $APP_NAME"
echo ""
echo "The old repository remains intact and can be safely deleted after"
echo "verifying that the new repository works correctly."
echo ""
