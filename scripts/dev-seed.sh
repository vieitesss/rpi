#!/usr/bin/env bash
# Replace one dev app's data with a pro snapshot: dev-seed.sh <app> [snapshot]
# The snapshot defaults to the latest; dev must be down.
set -euo pipefail

app=${1:?usage: dev-seed.sh <vaultwarden|tandem|forgejo> [snapshot]}
snapshot=${2:-latest}
case $app in
  vaultwarden | tandem | forgejo) ;;
  *) echo "unknown app: $app" >&2; exit 1 ;;
esac

here=$(cd "$(dirname "$0")" && pwd)
compose() { "$here/compose.sh" dev "$@"; }
: "${RPI_SECRETS:?RPI_SECRETS must point at the secrets env file}"

if [[ -n $(compose ps -q) ]]; then
  echo "dev is running; run 'just dev-down' first" >&2
  exit 1
fi

"$here/secrets.sh" "$RPI_SECRETS"
mkdir -p "/srv/rpi/dev/$app"
# Old CronJob snapshots and Backrest ones both keep the app under /backup/<app>.
compose run --rm -T restic -r "b2:${B2_BUCKET:?set B2_BUCKET in .env}:/kubernetes-pvcs/pro/$app" \
  restore "$snapshot:/backup/$app" --target "/restore/$app" --delete
echo "dev/$app now holds pro snapshot $snapshot"
