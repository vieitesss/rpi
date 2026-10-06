#!/usr/bin/env bash
# Point the host's tailscaled at the localhost ports Compose publishes.
# Run once per change with sudo; tailscaled keeps the config across reboots.
#   pro: Tailscale Services, https://<service>.<TAILNET_DOMAIN>
#   dev: ports on the host, https://<TAILNET_HOST>.<TAILNET_DOMAIN>:<port>
# The Services must exist in the tailnet first (scripts/tailnet-policy.sh).
set -euo pipefail

# service=local port (pro.yaml)
pro=(
  vaultwarden=9000
  tandem=9010
  tandem-backend=9011
  home=9020
  glances=9030
  forgejo=9040
  backrest=9050
)
for pair in "${pro[@]}"; do
  tailscale serve --service="svc:${pair%%=*}" --https=443 "http://127.0.0.1:${pair#*=}"
done
tailscale serve --service=svc:forgejo-git --tcp=22 tcp://127.0.0.1:2222

# tailnet port=local port (dev.yaml)
dev=(
  "8000=19000" # vaultwarden
  "8010=19010" # tandem
  "8011=19011" # tandem-backend
  "8020=19020" # home
  "8040=19040" # forgejo
)
for pair in "${dev[@]}"; do
  tailscale serve --bg --https="${pair%%=*}" "http://127.0.0.1:${pair#*=}"
done
tailscale serve --bg --tcp=2223 tcp://127.0.0.1:12222

tailscale serve status
