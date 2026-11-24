#!/usr/bin/env bash
# Send a notification to the NTFY topic, or (with no args) wait for pro
# containers on boot (system/etc/systemd/system/notify.service) and report status.
set -euo pipefail

cd "$(dirname "$0")/.."
source .env

send() {
  local title=$1 tags=$2 body=$3
  [[ -n "${NTFY:-}" ]] || return 0
  curl -fsS \
    -H "Title: $title" \
    -H "Tags: $tags" \
    -d "$body" \
    "https://ntfy.sh/${NTFY}" >/dev/null
}

if (($#)); then
  send "$(hostname)" "information_source" "$*"
  exit 0
fi

count() { docker ps -q --filter label=com.docker.compose.project=rpi-pro "$@" | wc -l; }

# Up to 3 minutes for every container to be running and past its healthcheck.
total=$(count -a)
for _ in $(seq 36); do
  running=$(($(count --filter status=running) - $(count --filter health=starting) - $(count --filter health=unhealthy)))
  ((running >= total)) && break
  sleep 5
done

send "Raspberry Pi booted" \
  "$( ((running >= total)) && echo white_check_mark || echo warning)" \
  "$(hostname): $running/$total pro containers running"
