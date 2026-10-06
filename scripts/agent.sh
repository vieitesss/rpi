#!/usr/bin/env bash
# Run a coding agent (or any command) on the Pi inside a memory-capped
# systemd scope, so it cannot starve the containers: agent.sh <command...>
# AGENT_MEMORY_MAX (default 2G) sets the cap; swap is capped too.
set -euo pipefail

(($#)) || { echo "usage: agent.sh <command...>" >&2; exit 1; }
max=${AGENT_MEMORY_MAX:-2G}
exec systemd-run --user --scope --quiet --collect \
  -p MemoryMax="$max" -p MemorySwapMax=512M \
  -- "$@"
