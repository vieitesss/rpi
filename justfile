# Secrets pulled from GCP Secret Manager at deploy time (scripts/secrets.sh).
set positional-arguments
# Per-host settings (tailnet, GCP project, B2 bucket); see .env.example.
set dotenv-load

export RPI_SECRETS := env_var('HOME') / ".config/rpi/secrets.env"

default:
    just -l

# Bring an Environment (dev|pro) up to what is checked out
deploy env:
    ./scripts/deploy.sh "$1"

# Stop dev; its data stays in /srv/rpi/dev
dev-down:
    ./scripts/compose.sh dev down

# Replace one dev app's data with a pro snapshot (dev must be down)
dev-seed app snapshot="latest":
    ./scripts/dev-seed.sh "$@"

# Any docker compose command for an Environment, e.g. `just compose pro logs -f home`
compose env *args:
    ./scripts/compose.sh "$@"

# Point tailscaled at the Compose ports (Services for pro, host ports for dev)
tailnet-serve:
    sudo ./scripts/tailscale-serve.sh

# Tailnet policy and Services through the Tailscale API (pull <dir> | push <dir> | services)
tailnet-policy *args:
    ./scripts/tailnet-policy.sh "$@"

shutdown:
    sudo ./scripts/shutdown.sh

# Run a command (e.g. an agent) under a memory cap; AGENT_MEMORY_MAX overrides 2G
agent *cmd:
    ./scripts/agent.sh "$@"
