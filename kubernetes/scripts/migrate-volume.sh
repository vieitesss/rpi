#!/bin/bash
set -euo pipefail

# Set kubeconfig for k3s
export KUBECONFIG=${KUBECONFIG:-/home/vieitesrpi/.kube/config}

# Migrate Docker volume to Kubernetes PVC
# Usage: ./migrate-volume.sh <docker-volume-name> <k8s-pvc-name> <namespace>
# Example: ./migrate-volume.sh rpi_vaultwarden-data pro-vaultwarden-pvc pro

if [ $# -ne 3 ]; then
    echo "Usage: $0 <docker-volume-name> <k8s-pvc-name> <namespace>"
    echo ""
    echo "Examples:"
    echo "  $0 rpi_vaultwarden-data pro-vaultwarden-pvc pro"
    echo "  $0 rpi_filebrowser-ts pro-filebrowser-pvc pro"
    exit 1
fi

DOCKER_VOLUME=$1
K8S_PVC=$2
NAMESPACE=$3
HELPER_POD="volume-migrator-$(date +%s)"

echo "========================================"
echo "Docker Volume → Kubernetes PVC Migration"
echo "========================================"
echo "Docker Volume: $DOCKER_VOLUME"
echo "K8s PVC: $K8S_PVC"
echo "Namespace: $NAMESPACE"
echo ""

# Find Docker volume path
echo "[1/6] Finding Docker volume path..."
if ! docker volume inspect "$DOCKER_VOLUME" &>/dev/null; then
    echo "ERROR: Docker volume '$DOCKER_VOLUME' not found"
    exit 1
fi

DOCKER_PATH=$(docker volume inspect "$DOCKER_VOLUME" --format '{{.Mountpoint}}')
echo "✓ Docker volume path: $DOCKER_PATH"

# Check if PVC exists
echo "[2/6] Checking if PVC exists..."
if ! kubectl get pvc "$K8S_PVC" -n "$NAMESPACE" &>/dev/null; then
    echo "ERROR: PVC '$K8S_PVC' not found in namespace '$NAMESPACE'"
    echo "Create the PVC first with: kubectl apply -f kubernetes/pro/<service>/pvc.yaml"
    exit 1
fi
echo "✓ PVC exists"

# Check PVC status
PVC_STATUS=$(kubectl get pvc "$K8S_PVC" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
echo "✓ PVC status: $PVC_STATUS"

if [ "$PVC_STATUS" != "Bound" ] && [ "$PVC_STATUS" != "Pending" ]; then
    echo "WARNING: PVC is in unexpected state: $PVC_STATUS"
fi

# Check if Docker volume has data
echo "[3/6] Checking Docker volume contents..."
DATA_COUNT=$(docker run --rm -v "$DOCKER_VOLUME:/data:ro" alpine sh -c 'find /data -type f | wc -l')
DATA_SIZE=$(docker run --rm -v "$DOCKER_VOLUME:/data:ro" alpine sh -c 'du -sh /data' | cut -f1)
echo "✓ Files found: $DATA_COUNT"
echo "✓ Total size: $DATA_SIZE"

if [ "$DATA_COUNT" -eq 0 ]; then
    echo "WARNING: Docker volume appears to be empty!"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create helper pod
echo "[4/6] Creating migration helper pod..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $HELPER_POD
  namespace: $NAMESPACE
spec:
  restartPolicy: Never
  volumes:
    - name: k8s-pvc
      persistentVolumeClaim:
        claimName: $K8S_PVC
    - name: docker-volume
      hostPath:
        path: $DOCKER_PATH
        type: Directory
  containers:
  - name: migrator
    image: alpine:latest
    command: ["sleep", "3600"]
    volumeMounts:
      - name: k8s-pvc
        mountPath: /dest
      - name: docker-volume
        mountPath: /src
        readOnly: true
EOF

# Wait for pod to be ready
echo "Waiting for helper pod to be ready..."
kubectl wait --for=condition=Ready pod/"$HELPER_POD" -n "$NAMESPACE" --timeout=60s

echo "✓ Helper pod ready"

# Copy data
echo "[5/6] Copying data from Docker volume to K8s PVC..."
echo "This may take a while depending on data size..."

kubectl exec -n "$NAMESPACE" "$HELPER_POD" -- sh -c '
echo "Source files:"
ls -lah /src/ | head -10
echo ""
echo "Copying..."
cp -av /src/. /dest/ 2>&1 | tail -20
echo ""
echo "Destination after copy:"
ls -lah /dest/ | head -10
'

echo "✓ Copy complete"

# Verify
echo "[6/6] Verifying migration..."
DEST_COUNT=$(kubectl exec -n "$NAMESPACE" "$HELPER_POD" -- sh -c 'find /dest -type f | wc -l')
DEST_SIZE=$(kubectl exec -n "$NAMESPACE" "$HELPER_POD" -- sh -c 'du -sh /dest' | cut -f1)

echo "✓ Files in PVC: $DEST_COUNT"
echo "✓ Total size: $DEST_SIZE"

if [ "$DATA_COUNT" -ne "$DEST_COUNT" ]; then
    echo "WARNING: File count mismatch! Source: $DATA_COUNT, Destination: $DEST_COUNT"
else
    echo "✓ File count matches!"
fi

# Cleanup
echo ""
echo "Cleaning up helper pod..."
kubectl delete pod "$HELPER_POD" -n "$NAMESPACE"

echo ""
echo "========================================"
echo "✅ Migration Complete!"
echo "========================================"
echo "Docker volume '$DOCKER_VOLUME' has been copied to K8s PVC '$K8S_PVC'"
echo ""
echo "Next steps:"
echo "1. Deploy your service: kubectl apply -f kubernetes/pro/<service>/"
echo "2. Verify the service can access the data"
echo "3. Once verified, you can stop the Docker service"
echo ""
