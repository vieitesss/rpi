#!/bin/bash
set -euo pipefail

# Deploys services via helmfile for specified environment
# Usage: ./deploy.sh <environment>
# Example: ./deploy.sh dev

ENVIRONMENT=${1:-}

if [ -z "$ENVIRONMENT" ]; then
    echo "Usage: $0 <environment>"
    echo ""
    echo "Environments: dev, pro"
    echo ""
    echo "Example: $0 dev"
    exit 1
fi

if [[ ! "$ENVIRONMENT" =~ ^(dev|pro)$ ]]; then
    echo "Error: Invalid environment '$ENVIRONMENT'. Must be: dev or pro"
    exit 1
fi

echo "========================================="
echo "Deploying to: $ENVIRONMENT"
echo "========================================="
echo ""

# Get project root
SCRIPT_DIR="$(realpath $(dirname $0))"
PROJECT_ROOT="$(realpath ${SCRIPT_DIR}/../..)"
INFRA_DIR="${PROJECT_ROOT}/kubernetes/infra"

if ! kubectl cluster-info &>/dev/null; then
    echo "Error: Cannot connect to Kubernetes cluster"
    exit 1
fi
echo "✓ Connected to cluster"

if [ ! -f "$INFRA_DIR/gcp-credentials-secret.yaml" ]; then
    echo "Error: GCP credentials not found: $INFRA_DIR/gcp-credentials-secret.yaml"
    exit 1
fi
echo "✓ GCP credentials found"
echo ""

# Check if Tailscale operator is installed
echo "Checking Tailscale operator..."
if ! kubectl get namespace tailscale &>/dev/null || \
   ! kubectl get deployment tailscale-operator -n tailscale &>/dev/null; then
    echo "Tailscale operator not found. Installing..."
    INSTALL_SCRIPT="${SCRIPT_DIR}/install-tailscale-operator.sh"
    if [ ! -f "$INSTALL_SCRIPT" ]; then
        echo "Error: Install script not found: $INSTALL_SCRIPT"
        exit 1
    fi
    if ! bash "$INSTALL_SCRIPT"; then
        echo "Error: Failed to install Tailscale operator"
        exit 1
    fi
    echo "✓ Tailscale operator installed"
else
    echo "✓ Tailscale operator already installed"
fi
echo ""

echo "Applying infrastructure resources..."
kubectl apply -f "$INFRA_DIR/storageclass.yaml"
kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$INFRA_DIR/gcp-credentials-secret.yaml"
kubectl apply -f "$INFRA_DIR/gcp-cluster-secretstore.yaml"
kubectl apply -f "$INFRA_DIR/coredns-custom.yaml"
echo "✓ Infrastructure ready"
echo ""

echo "Deploying services via helmfile..."
cd "$PROJECT_ROOT"
helmfile -e "$ENVIRONMENT" sync
echo ""

echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo ""

kubectl get pods -n "$ENVIRONMENT"

echo ""
echo "Next steps:"
echo "  • Check status: kubectl get all -n $ENVIRONMENT"
echo "  • View logs: kubectl logs -f deployment/vaultwarden -c vaultwarden -n $ENVIRONMENT"
if [ "$ENVIRONMENT" = "dev" ]; then
  echo "  • Access via Tailscale: https://vaultwarden-dev.burro-ph.ts.net"
else
  echo "  • Access via Tailscale: https://vaultwarden.burro-ph.ts.net"
fi
echo ""
