#!/bin/sh
# shellcheck shell=sh
set -eu

echo "========================================="
echo "Restic Backup Started: $(date)"
echo "Namespace: $NAMESPACE"
echo "App: $APP_NAME"
echo "Repository: $RESTIC_REPOSITORY"
echo "========================================="
echo ""

export PATH="/kubectl-bin:$PATH"

REPLICA_COUNTS_FILE="/tmp/replica_counts"
> "$REPLICA_COUNTS_FILE"

send_failure_notification() {
  if [ "$NOTIFICATIONS_ENABLED" != "true" ]; then
    return 0
  fi

  MESSAGE=$(printf '%s\n' \
    "Restic backup failed" \
    "Namespace: $NAMESPACE" \
    "Release: $RELEASE_NAME" \
    "App: $APP_NAME" \
    "Repository: $RESTIC_REPOSITORY" \
    "Time: $(date)" \
    "" \
    "Inspect with:" \
    "kubectl get jobs -n $NAMESPACE -l app=restic-backup,job=backup" \
    "kubectl logs -n $NAMESPACE -l app=restic-backup,job=backup --tail=100")

  if command -v curl >/dev/null 2>&1; then
    curl -fsS \
      -H "Title: ❌ Restic backup failed" \
      -H "Priority: urgent" \
      -H "Tags: warning,floppy_disk" \
      -d "$MESSAGE" \
      "${NTFY_URL}/${NTFY_TOPIC}" >/dev/null || true
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- \
      --header="Title: ❌ Restic backup failed" \
      --header="Priority: urgent" \
      --header="Tags: warning,floppy_disk" \
      --post-data="$MESSAGE" \
      "${NTFY_URL}/${NTFY_TOPIC}" >/dev/null || true
  else
    echo "Notification requested, but neither curl nor wget is available in the backup image"
  fi
}

cleanup() {
  if [ "$SCALE_DOWN_ENABLED" = "true" ] && [ -f "$REPLICA_COUNTS_FILE" ]; then
    echo ""
    echo "Scaling deployments back up..."
    while IFS=: read -r deployment replicas; do
      if [ -n "$deployment" ] && [ "$replicas" -gt 0 ]; then
        if kubectl scale deployment "$deployment" -n "$NAMESPACE" --replicas="$replicas"; then
          echo "  ✓ Scaled up $deployment to $replicas replicas"
        else
          echo "  ⚠️ Failed to scale up $deployment to $replicas replicas"
        fi
      fi
    done < "$REPLICA_COUNTS_FILE"
    echo "✓ Scale-up cleanup complete"
  fi
}

on_exit() {
  exit_code=$?
  cleanup
  if [ "$exit_code" -ne 0 ]; then
    send_failure_notification
  fi
  exit "$exit_code"
}

trap on_exit EXIT

if [ "$SCALE_DOWN_ENABLED" = "true" ] && [ -n "$SCALE_DOWN_DEPLOYMENTS" ]; then
  echo "Scaling down deployments for consistent backup..."

  echo "$SCALE_DOWN_DEPLOYMENTS" | tr ',' '\n' | while read -r deployment; do
    deployment=$(echo "$deployment" | tr -d ' ')
    if [ -n "$deployment" ]; then
      echo "  Checking deployment: $deployment"

      REPLICAS=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
      REPLICAS=${REPLICAS:-0}
      echo "$deployment:$REPLICAS" >> "$REPLICA_COUNTS_FILE"

      kubectl scale deployment "$deployment" -n "$NAMESPACE" --replicas=0
      echo "  ✓ Scaled down $deployment (was $REPLICAS replicas)"

      echo "  Waiting for $deployment pods to terminate..."
      kubectl wait --for=delete pod -l app="$deployment" -n "$NAMESPACE" --timeout=60s 2>/dev/null || true
      echo "  ✓ Pods deleted"
    fi
  done

  echo ""
  echo "Waiting ${SCALE_DOWN_WAIT_SECONDS}s for filesystem sync..."
  sleep "$SCALE_DOWN_WAIT_SECONDS"
  echo "✓ Filesystem synced"
  echo ""
fi

echo "Checking repository..."
if ! restic snapshots > /dev/null 2>&1; then
  echo "Repository not found. Initializing..."
  restic init
  echo "Repository initialized successfully"
fi

echo ""
echo "Starting backup..."
restic backup /backup \
  --tag "namespace=$NAMESPACE" \
  --tag "cronjob=$RELEASE_NAME" \
  --host "$NAMESPACE" \
  --verbose

echo ""
echo "Backup completed successfully!"

echo ""
echo "Pruning old backups..."
restic forget \
  --keep-daily "$RETENTION_KEEP_DAILY" \
  --keep-weekly "$RETENTION_KEEP_WEEKLY" \
  --keep-monthly "$RETENTION_KEEP_MONTHLY" \
  --keep-yearly "$RETENTION_KEEP_YEARLY" \
  --prune \
  --verbose

echo ""
echo "Prune completed successfully!"

echo ""
echo "Latest snapshots:"
restic snapshots --latest 5

echo ""
echo "Repository statistics:"
restic stats

echo ""
echo "========================================="
echo "Backup job completed: $(date)"
echo "========================================="
