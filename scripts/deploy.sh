#!/usr/bin/env bash
# Bring an Environment up to what git says: deploy.sh <dev|pro>
# pro also refreshes the secrets file and Backrest's repos and plans first.
set -euo pipefail

env=${1:?usage: deploy.sh <dev|pro>}
[[ $env == dev || $env == pro ]] || { echo "unknown environment: $env" >&2; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
compose() { "$here/compose.sh" "$env" "$@"; }

: "${RPI_SECRETS:?RPI_SECRETS must point at the secrets env file}"

data=/srv/rpi/$env
if [[ $env == dev ]]; then
  # Dev starts empty or from `just dev-seed`.
  mkdir -p "$data"/{vaultwarden,tandem,forgejo}
else
  # Never let pro start on an empty dir that Docker created: a missing one
  # means the data was not put in place.
  for dir in vaultwarden tandem forgejo backrest/config backrest/data backrest/cache; do
    [[ -d $data/$dir ]] || { echo "missing $data/$dir" >&2; exit 1; }
  done
  "$here/secrets.sh" "$RPI_SECRETS"

  # Backrest owns config.json; merge only the git-tracked repos and plans in.
  # A failed read aborts the deploy: it must never look like "no config yet".
  live=$(compose run --rm -T --no-deps --entrypoint sh backrest \
    -c 'if [ -e /config/config.json ]; then cat /config/config.json; fi')
  status=0
  merged=$(printf '%s' "$live" | python3 "$here/backrest-config.py" "$here/../compose/backrest/config.template.json") || status=$?
  case $status in
    0)
      echo "backrest: repos or plans changed, rewriting config.json"
      compose stop backrest
      printf '%s\n' "$merged" | compose run --rm -T --no-deps --entrypoint sh backrest \
        -c 'umask 077 && cat > /config/config.json.new && test -s /config/config.json.new && mv /config/config.json.new /config/config.json'
      ;;
    3) echo "backrest: config up to date" ;;
    *) echo "backrest: config merge failed" >&2; exit 1 ;;
  esac
  unset live merged
fi

compose up -d --remove-orphans --wait --wait-timeout 300
compose ps
