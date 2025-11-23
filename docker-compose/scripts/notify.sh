#!/usr/bin/env bash

# ---------------- SETUP ----------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
LOG_FILE="$HOME/startup_check.log"

# Redirect stdout and stderr to log file
exec > >(tee -a "$LOG_FILE") 2>&1

# Load environment variables
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo "$(date): ❌ Error: .env file not found at $ENV_FILE"
    exit 1
fi

# Kubernetes Configuration
export KUBECONFIG="$HOME/.kube/config"
export PATH=$PATH:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

# ---------------- NOTIFICATION FUNCTION ----------------
send_notification() {
    local message="$1"
    local title="$2"
    local priority="$3"
    local tags="$4"

    # Get CPU temperature
    TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0)
    TEMP_CELSIUS=$(($TEMP_RAW / 1000))

    curl -s \
        -d "$message
        
🌡️ CPU Temp: ${TEMP_CELSIUS}°C | 📅 $(date '+%H:%M')" \
        -H "Title: $title" \
        -H "Priority: $priority" \
        -H "Tags: $tags" \
        "ntfy.sh/$NTFY"
}

# ---------------- CHECKS ----------------

echo "$(date): Starting checks..."

# 1. KUBERNETES API CHECK (With timeout)
ATTEMPTS=0
MAX_ATTEMPTS=20

until kubectl get nodes &> /dev/null
do
  if [ $ATTEMPTS -ge $MAX_ATTEMPTS ]; then
      send_notification \
          "Kubernetes API unreachable after 100 seconds." \
          "❌ Critical: K8s Down" \
          "urgent" \
          "warning,skull"
      exit 1
  fi
  sleep 5
  ((ATTEMPTS++))
done
echo "$(date): Kubernetes API is responsive."

# 2. VAULTWARDEN DEPLOYMENT CHECK
if kubectl wait --for=condition=available deployment/vaultwarden -n pro --timeout=300s; then
    # --- SUCCESS ---
    send_notification \
        "Vaultwarden is UP." \
        "System Ready" \
        "high" \
        "white_check_mark,computer"
else
    # --- FAILURE ---
    LOGS_POD=$(kubectl logs -l app=vaultwarden -n pro --tail=3 2>/dev/null)
    
    send_notification \
        "Deployment failed to start after 5 minutes.
        
🔍 Recent Logs:
$LOGS_POD" \
        "⚠️ Error: Vaultwarden Failed" \
        "urgent" \
        "sos,x"
    exit 1
fi
