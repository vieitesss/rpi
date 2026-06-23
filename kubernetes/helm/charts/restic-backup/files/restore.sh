#!/bin/sh
# shellcheck shell=sh
set -eu

echo "========================================="
echo "Restic Restore Started: $(date)"
echo "Namespace: $NAMESPACE"
echo "App: $APP_NAME"
echo "Repository: $RESTIC_REPOSITORY"
echo "========================================="

SNAPSHOT_ID="${SNAPSHOT_ID:-latest}"
RESTORE_PATH="${RESTORE_PATH:-/restore}"
RESTORE_SOURCE_PATH="${RESTORE_SOURCE_PATH:-/backup/$APP_NAME}"
RESTIC_HOST="${RESTIC_HOST:-$NAMESPACE}"

case "$RESTORE_SOURCE_PATH" in
  /*) ;;
  *) echo "RESTORE_SOURCE_PATH must be absolute (example: /backup/$APP_NAME)"; exit 1 ;;
esac

case "$RESTORE_PATH" in
  /*) ;;
  *) echo "RESTORE_PATH must be absolute (example: /restore)"; exit 1 ;;
esac

if [ "$RESTORE_PATH" = "/" ]; then
  echo "RESTORE_PATH must not be /"
  exit 1
fi

echo "Snapshot: $SNAPSHOT_ID"
echo "Restore path: $RESTORE_PATH"
echo "Source path: $RESTORE_SOURCE_PATH"
echo "Host: $RESTIC_HOST"
echo ""

echo "Available snapshots:"
restic snapshots --host "$RESTIC_HOST"
echo ""

echo "Cleaning target directory..."
mkdir -p "$RESTORE_PATH"
rm -rf "$RESTORE_PATH"/* "$RESTORE_PATH"/.[!.]* "$RESTORE_PATH"/..?*
echo "✓ Target directory cleaned"
echo ""

echo "Restoring snapshot: $SNAPSHOT_ID:$RESTORE_SOURCE_PATH"
restic restore "$SNAPSHOT_ID:$RESTORE_SOURCE_PATH" \
  --target "$RESTORE_PATH" \
  --verify \
  --verbose

echo ""
echo "Restore completed successfully!"
echo ""
echo "Restored files:"
ls -lah "$RESTORE_PATH/"

echo ""
echo "========================================="
echo "Restore job completed: $(date)"
echo "========================================="
