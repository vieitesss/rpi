#!/usr/bin/env bash

SCRIPT_DIR="$(dirname "$0")"
ENV_FILE="$(realpath "${SCRIPT_DIR}/../../.env")"

if [[ -f "${ENV_FILE}" ]]
then
    source "${ENV_FILE}"
    if [[ -z "${TAILSCALE_CLIENT_ID}" ]]; then
        echo "[ERROR] TAILSCALE_CLIENT_ID is not set in ${ENV_FILE}"
        exit 1
    fi
    if [[ -z "${TAILSCALE_AUTH_KEY}" ]]; then
        echo "[ERROR] TAILSCALE_AUTH_KEY is not set in ${ENV_FILE}"
        exit 1
    fi
    TAILSCALE_AUTH_KEY="$(echo "${TAILSCALE_AUTH_KEY}" | cut -d? -f1)"
else
    echo "[ERROR] The .env file does not exist in ${ENV_FILE}"
    exit 1
fi

helm repo add tailscale https://pkgs.tailscale.com/helmcharts
helm repo update
helm upgrade \
  --install \
  tailscale-operator \
  tailscale/tailscale-operator \
  --namespace=tailscale \
  --create-namespace \
  --set-string oauth.clientId="${TAILSCALE_CLIENT_ID}" \
  --set-string oauth.clientSecret="${TAILSCALE_AUTH_KEY}" \
  --wait

