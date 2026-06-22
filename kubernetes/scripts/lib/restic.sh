#!/bin/bash
set -euo pipefail

RESTIC_IMAGE="restic/restic:0.18.1"
RESTIC_REPOSITORY_BUCKET="rpi-data"
RESTIC_REPOSITORY_BASE_PATH="kubernetes-pvcs"
RESTIC_PASSWORD_KEY="RESTIC_PASSWORD"
RESTIC_B2_ACCOUNT_ID_KEY="B2_ACCOUNT_ID"
RESTIC_B2_ACCOUNT_KEY_KEY="B2_ACCOUNT_KEY"
RESTIC_CREDENTIALS_SUFFIX="-credentials"

restic_credentials_secret() {
    printf '%s%s\n' "$1" "$RESTIC_CREDENTIALS_SUFFIX"
}

restic_repository_uri() {
    printf 'b2:%s:/%s\n' "$RESTIC_REPOSITORY_BUCKET" "$1"
}

restic_global_repository() {
    restic_repository_uri "$RESTIC_REPOSITORY_BASE_PATH"
}

restic_default_repository() {
    restic_repository_uri "$RESTIC_REPOSITORY_BASE_PATH/$1/$2"
}

restic_cronjob_exists() {
    kubectl get cronjob "$2" -n "$1" &>/dev/null
}

restic_cronjob_repository() {
    kubectl get cronjob "$2" -n "$1" -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].env[?(@.name=="RESTIC_REPOSITORY")].value}' 2>/dev/null
}

restic_repository() {
    local namespace=$1
    local app_name=$2
    local release=${3:-${RESTIC_RELEASE_NAME:-restic-backup}}
    local repo=""

    if [ "${RESTIC_LIB_NO_CLUSTER:-}" != "1" ]; then
        repo=$(restic_cronjob_repository "$namespace" "$release" || true)
    fi

    if [ -n "$repo" ]; then
        printf '%s\n' "$repo"
    else
        restic_default_repository "$namespace" "$app_name"
    fi
}

restic_secret_value() {
    local namespace=$1
    local release=$2
    local key=$3
    kubectl get secret "$(restic_credentials_secret "$release")" -n "$namespace" -o "jsonpath={.data.$key}" | base64 -d
}

restic_temp_pod_name() {
    printf '%s-%s-%s\n' "$1" "$(date +%s)" "$$"
}

restic_exec_repo() {
    if [ $# -lt 3 ]; then
        echo "Usage: restic_exec_repo <namespace> <repo> [restic-release] -- <restic args...>" >&2
        return 2
    fi

    local namespace=$1
    local repo=$2
    local release=${RESTIC_RELEASE_NAME:-restic-backup}
    shift 2

    if [ "${1:-}" != "--" ]; then
        release=$1
        shift
    fi

    if [ $# -eq 0 ] || [ "${1:-}" != "--" ]; then
        echo "Usage: restic_exec_repo <namespace> <repo> [restic-release] -- <restic args...>" >&2
        return 2
    fi
    shift

    local pod_name
    pod_name=$(restic_temp_pod_name "restic-exec")

    if [ "${RESTIC_EXEC_DRY_RUN:-}" = "1" ]; then
        echo "image=$RESTIC_IMAGE"
        echo "namespace=$namespace"
        echo "pod=$pod_name"
        echo "RESTIC_REPOSITORY=$repo"
        echo "credential_secret=$(restic_credentials_secret "$release")"
        echo "credential_keys=$RESTIC_PASSWORD_KEY,$RESTIC_B2_ACCOUNT_ID_KEY,$RESTIC_B2_ACCOUNT_KEY_KEY"
        printf 'command=restic'
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi

    local restic_password b2_account_id b2_account_key
    restic_password=$(restic_secret_value "$namespace" "$release" "$RESTIC_PASSWORD_KEY")
    b2_account_id=$(restic_secret_value "$namespace" "$release" "$RESTIC_B2_ACCOUNT_ID_KEY")
    b2_account_key=$(restic_secret_value "$namespace" "$release" "$RESTIC_B2_ACCOUNT_KEY_KEY")

    (
        trap 'kubectl delete pod '"$pod_name"' -n '"$namespace"' --ignore-not-found &>/dev/null || true' EXIT
        kubectl run "$pod_name" \
            --image="$RESTIC_IMAGE" \
            --restart=Never \
            -n "$namespace" \
            --rm \
            -i \
            --quiet \
            --env="RESTIC_REPOSITORY=${repo}" \
            --env="$RESTIC_PASSWORD_KEY=${restic_password}" \
            --env="$RESTIC_B2_ACCOUNT_ID_KEY=${b2_account_id}" \
            --env="$RESTIC_B2_ACCOUNT_KEY_KEY=${b2_account_key}" \
            --command -- restic "$@"
    )
}

restic_exec() {
    if [ $# -lt 3 ]; then
        echo "Usage: restic_exec <namespace> <app> [restic-release] -- <restic args...>" >&2
        return 2
    fi

    local namespace=$1
    local app_name=$2
    local release=${RESTIC_RELEASE_NAME:-restic-backup}
    shift 2

    if [ "${1:-}" != "--" ]; then
        release=$1
        shift
    fi

    local repo
    repo=$(restic_repository "$namespace" "$app_name" "$release")
    restic_exec_repo "$namespace" "$repo" "$release" "$@"
}

restic_self_check() {
    local out expected_repo expected_secret expected_keys
    expected_repo=$(restic_default_repository dev vaultwarden)
    expected_secret=$(restic_credentials_secret restic-backup)
    expected_keys="$RESTIC_PASSWORD_KEY,$RESTIC_B2_ACCOUNT_ID_KEY,$RESTIC_B2_ACCOUNT_KEY_KEY"
    out=$(RESTIC_LIB_NO_CLUSTER=1 RESTIC_EXEC_DRY_RUN=1 restic_exec dev vaultwarden -- snapshots --host dev)

    [[ "$out" == *"image=$RESTIC_IMAGE"* ]]
    [[ "$out" == *"RESTIC_REPOSITORY=$expected_repo"* ]]
    [[ "$out" == *"credential_secret=$expected_secret"* ]]
    [[ "$out" == *"credential_keys=$expected_keys"* ]]
    [[ "$out" == *"command=restic snapshots --host dev"* ]]

    echo "restic lib self-check passed"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    case "${1:-}" in
        --self-check|--dry-run)
            restic_self_check
            ;;
        *)
            echo "Usage: $0 --self-check" >&2
            exit 2
            ;;
    esac
fi
