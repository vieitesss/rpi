#!/usr/bin/env bash
# docker compose for one Environment: compose.sh <dev|pro> <compose args...>
# Sets RPI_DATA to the Environment's data dir and stacks its overlay.
set -euo pipefail

env=${1:?usage: compose.sh <dev|pro> <compose args...>}
shift
case $env in
  dev | pro) ;;
  *) echo "unknown environment: $env (want dev or pro)" >&2; exit 1 ;;
esac

cd "$(dirname "$0")/.."
# Always derived from the env, never inherited: dev must never see pro data.
export RPI_DATA=/srv/rpi/$env
exec docker compose -f compose/compose.yaml -f "compose/$env.yaml" "$@"
