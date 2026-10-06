#!/usr/bin/env bash
# Boot notification (system/etc/systemd/system/notify.service): waits for the
# pro containers Docker restarts on boot, then reports how many are running.
set -euo pipefail

cd "$(dirname "$0")/.."
source .env

count() { docker ps -q --filter label=com.docker.compose.project=rpi-pro "$@" | wc -l; }

# Up to 3 minutes for every container to be running and past its healthcheck.
total=$(count -a)
for _ in $(seq 36); do
  running=$(($(count --filter status=running) - $(count --filter health=starting) - $(count --filter health=unhealthy)))
  ((running >= total)) && break
  sleep 5
done

if [[ -n "${NTFY:-}" ]]; then
  curl -fsS \
    -H "Title: Raspberry Pi booted" \
    -H "Tags: $( ((running >= total)) && echo white_check_mark || echo warning)" \
    -d "$(hostname): $running/$total pro containers running" \
    "https://ntfy.sh/${NTFY}" >/dev/null
fi
