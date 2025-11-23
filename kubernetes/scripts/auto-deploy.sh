#!/bin/bash
set -euo pipefail

# Auto-deploys Kubernetes services on boot
# Usage: Run by systemd k3s-deploy.service
# Can also run manually: ./auto-deploy.sh

SCRIPT_DIR="$(realpath $(dirname $0))"
PROJECT_ROOT="$(realpath ${SCRIPT_DIR}/../..)"
LOG_DIR="${PROJECT_ROOT}/logs"
LOG_FILE="${LOG_DIR}/auto-deploy-$(date +%Y%m%d-%H%M%S).log"
DEPLOY_SCRIPT="${SCRIPT_DIR}/deploy.sh"

export KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}

mkdir -p "$LOG_DIR"

tee -a "$LOG_FILE" <<EOF
=========================================
Kubernetes Auto-Deploy
Started: $(date)
=========================================

EOF

# Wait for K3s API server
echo "Waiting for K3s API server..." | tee -a "$LOG_FILE"
for i in {1..60}; do
  if kubectl cluster-info &>/dev/null; then
    echo "✓ K3s is ready" | tee -a "$LOG_FILE"
    break
  fi
  echo "  Attempt $i/60..." | tee -a "$LOG_FILE"
  sleep 5
done

if ! kubectl cluster-info &>/dev/null; then
  echo "Error: K3s not ready after 5 minutes" | tee -a "$LOG_FILE"
  exit 1
fi

echo "" | tee -a "$LOG_FILE"

# Deploy environments
for env in dev pro; do
  echo "Checking $env environment..." | tee -a "$LOG_FILE"

  # Check if already deployed and running
  if kubectl get namespace "$env" &>/dev/null &&
    kubectl get deployment vaultwarden -n "$env" &>/dev/null; then
    ready=$(kubectl get deployment vaultwarden -n "$env" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "$ready" -gt 0 ]; then
      echo "✓ $env already deployed and running" | tee -a "$LOG_FILE"
      continue
    fi
  fi

  echo "Deploying $env..." | tee -a "$LOG_FILE"
  if bash "$DEPLOY_SCRIPT" "$env" 2>&1 | tee -a "$LOG_FILE"; then
    echo "✓ $env deployed successfully" | tee -a "$LOG_FILE"
  else
    echo "✗ $env deployment failed" | tee -a "$LOG_FILE"
  fi
  echo "" | tee -a "$LOG_FILE"
done

tee -a "$LOG_FILE" <<EOF
=========================================
Auto-Deploy Complete
=========================================

Log file: $LOG_FILE
EOF
