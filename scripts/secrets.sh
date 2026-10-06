#!/usr/bin/env bash
# Pull the homelab secrets from GCP Secret Manager into a 0600 env file that
# Compose reads (env_file). Runs only on deploy, so nothing polls Secret Manager.
# Never prints a value.
set -euo pipefail

out=${1:?usage: secrets.sh <env file>}
project=${GCP_PROJECT:?set GCP_PROJECT in .env}

# ENV_VAR=secret-name
secrets=(
  B2_ACCOUNT_ID=rpi-b2-account-id
  B2_ACCOUNT_KEY=rpi-b2-account-key
  RPI_RESTIC_PASSWORD=restic_password
  NTFY_TOPIC=ntfy_backup_error
)

umask 077
mkdir -p "$(dirname "$out")"
tmp=$(mktemp "$out.XXXXXX")
trap 'rm -f "$tmp"' EXIT

for pair in "${secrets[@]}"; do
  name=${pair%%=*}
  secret=${pair#*=}
  value=$(gcloud secrets versions access latest --secret="$secret" --project="$project")
  # Single quotes keep Compose from interpolating `$` in the value.
  if [[ $value == *"'"* || $value == *$'\n'* ]]; then
    echo "secret $secret contains a single quote or newline; cannot write it as an env file value" >&2
    exit 1
  fi
  printf "%s='%s'\n" "$name" "$value" >>"$tmp"
done

mv "$tmp" "$out"
trap - EXIT
echo "wrote ${#secrets[@]} secrets to $out"
