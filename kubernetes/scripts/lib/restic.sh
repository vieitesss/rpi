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

restic_fallback_repository() {
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

    if [ "${RESTIC_LIB_NO_CLUSTER:-}" != "1" ] && [ "${RESTIC_CLI_DRY_RUN:-}" != "1" ]; then
        repo=$(restic_cronjob_repository "$namespace" "$release" || true)
    fi

    if [ -n "$repo" ]; then
        printf '%s\n' "$repo"
    else
        restic_fallback_repository "$namespace" "$app_name"
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

restic_cli_require_cronjob() {
    local namespace=$1
    local release=$2

    if [ "${RESTIC_CLI_DRY_RUN:-}" = "1" ]; then
        echo "cronjob=$release namespace=$namespace"
        return 0
    fi

    if ! restic_cronjob_exists "$namespace" "$release"; then
        echo "Error: CronJob $release not found in namespace $namespace"
        echo ""
        echo "Deploy it first with:"
        echo "  helmfile -l name=$release apply -e $namespace"
        return 1
    fi
}

restic_cli_banner() {
    local title=$1
    local namespace=$2
    local app_name=$3
    local release=$4
    local repo=$5

    echo "========================================="
    echo "$title"
    echo "========================================="
    echo "Namespace: $namespace"
    echo "App: $app_name"
    echo "Restic Release: $release"
    echo "Repository: $repo"
    echo ""
}

restic_cli_backup_usage() {
    local script=$1
    echo "Usage: $script <namespace> <app-name> [restic-release]"
    echo ""
    echo "Arguments:"
    echo "  namespace      - Kubernetes namespace (dev, pro)"
    echo "  app-name       - Application name (must match repository.appName in values)"
    echo "  restic-release - CronJob/release to use (default: restic-backup)"
    echo ""
    echo "Examples:"
    echo "  $script dev vaultwarden                         # Trigger vaultwarden backup in dev"
    echo "  $script pro vaultwarden                         # Trigger vaultwarden backup in pro"
    echo "  $script dev tandem restic-backup-tandem         # Trigger tandem backup in dev"
    echo "  $script dev anythingllm restic-backup-anythingllm"
}

restic_cli_backup() {
    local script=$1
    local namespace=${2:-}
    local app_name=${3:-}
    local release=${4:-${RESTIC_RELEASE_NAME:-restic-backup}}

    if [ -z "$namespace" ] || [ -z "$app_name" ]; then
        restic_cli_backup_usage "$script"
        return 1
    fi

    restic_cli_require_cronjob "$namespace" "$release" || return 1

    local repo
    repo=$(restic_repository "$namespace" "$app_name" "$release")
    restic_cli_banner "Restic Manual Backup" "$namespace" "$app_name" "$release" "$repo"

    local job_name
    job_name="${release}-manual-$(date +%Y%m%d-%H%M%S)-$$"

    if [ "${#job_name}" -gt 63 ]; then
        job_name="restic-manual-$(date +%Y%m%d-%H%M%S)-$$"
    fi

    if [ "${RESTIC_CLI_DRY_RUN:-}" = "1" ]; then
        echo "would_create_job=$job_name"
        return 0
    fi

    echo "Creating job from CronJob..."
    kubectl create job "$job_name" \
        --from=cronjob/"$release" \
        -n "$namespace"

    echo ""
    echo "========================================="
    echo "Job created: $job_name"
    echo "========================================="
    echo ""
    echo "Follow logs with:"
    echo "  kubectl logs -f job/$job_name -n $namespace"
    echo ""
    echo "Check job status with:"
    echo "  kubectl get job $job_name -n $namespace"
}

restic_cli_list_usage() {
    local script=$1
    echo "Usage: $script <namespace> <app-name> [restic-release]"
    echo ""
    echo "Arguments:"
    echo "  namespace      - Kubernetes namespace (dev, pro)"
    echo "  app-name       - Application name (must match repository.appName)"
    echo "  restic-release - CronJob/release to use for credentials (default: restic-backup)"
    echo ""
    echo "Examples:"
    echo "  $script dev vaultwarden                         # List vaultwarden snapshots in dev"
    echo "  $script pro vaultwarden                         # List vaultwarden snapshots in pro"
    echo "  $script dev tandem restic-backup-tandem         # List tandem snapshots in dev"
    echo "  $script dev anythingllm restic-backup-anythingllm"
}

restic_cli_list() {
    local script=$1
    local namespace=${2:-}
    local app_name=${3:-}
    local release=${4:-${RESTIC_RELEASE_NAME:-restic-backup}}

    if [ -z "$namespace" ] || [ -z "$app_name" ]; then
        restic_cli_list_usage "$script"
        return 1
    fi

    restic_cli_require_cronjob "$namespace" "$release" || return 1

    local repo
    repo=$(restic_repository "$namespace" "$app_name" "$release")
    restic_cli_banner "Restic Snapshots" "$namespace" "$app_name" "$release" "$repo"
    if [ "${RESTIC_CLI_DRY_RUN:-}" = "1" ]; then
        RESTIC_EXEC_DRY_RUN=1 restic_exec_repo "$namespace" "$repo" "$release" -- snapshots --host "$namespace"
    else
        restic_exec_repo "$namespace" "$repo" "$release" -- snapshots --host "$namespace"
    fi
}

restic_cli_restore_usage() {
    local script=$1
    echo "Usage: $script <namespace> <app-name> [snapshot-id] [target-pvc] [source-namespace] [restic-release] [source-path]"
    echo ""
    echo "Arguments:"
    echo "  namespace    - Kubernetes namespace (dev, pro)"
    echo "  app-name     - Application name (must match repository.appName)"
    echo "  snapshot-id  - Restic snapshot ID or 'latest' (default: latest)"
    echo "  target-pvc   - Target PVC to restore to (optional - lists snapshots if not specified)"
    echo "  source-namespace - Source backup namespace in B2 (default: namespace)"
    echo "  restic-release - Release name that provides scripts/credentials (default: restic-backup)"
    echo "  source-path - Path inside the snapshot to restore (default: /backup/<app-name>)"
    echo ""
    echo "Examples:"
    echo "  $script dev vaultwarden                                # List available snapshots"
    echo "  $script dev vaultwarden latest                         # Info about latest snapshot"
    echo "  $script dev vaultwarden latest dev-vaultwarden-pvc     # Restore to existing PVC"
    echo "  $script dev tandem latest dev-tandem-backend-pvc pro   # Restore pro backup to dev"
    echo "  $script dev tandem latest dev-tandem-backend-pvc pro restic-backup-tandem /backup/tandem"
    echo "  $script pro anythingllm latest anythingllm-files-pvc pro restic-backup-anythingllm /backup/anythingllm-files"
    echo "  $script dev vaultwarden a1b2c3d4 dev-vaultwarden-pvc   # Restore specific snapshot"
}

restic_cli_restore() {
    local script=$1
    local namespace=${2:-}
    local app_name=${3:-}
    local snapshot_id=${4:-latest}
    local target_pvc=${5:-}
    local source_namespace=${6:-${RESTIC_SOURCE_NAMESPACE:-$namespace}}
    local release=${7:-${RESTIC_RELEASE_NAME:-restic-backup}}
    local restore_source_path=${8:-${RESTIC_RESTORE_SOURCE_PATH:-/backup/$app_name}}
    local scripts_configmap="${release}-scripts"
    local credentials_secret
    credentials_secret=$(restic_credentials_secret "$release")

    if [ -z "$namespace" ] || [ -z "$app_name" ]; then
        restic_cli_restore_usage "$script"
        return 1
    fi

    if [[ "$restore_source_path" != /* ]]; then
        echo "Error: source-path must be absolute inside the snapshot (example: /backup/$app_name)"
        return 1
    fi

    local repo
    if [ "$source_namespace" = "$namespace" ]; then
        repo=$(restic_repository "$namespace" "$app_name" "$release")
    else
        repo=$(restic_fallback_repository "$source_namespace" "$app_name")
    fi

    restic_cli_banner "Restic Restore Helper" "$namespace" "$app_name" "$release" "$repo"
    echo "Source Namespace: $source_namespace"
    echo "Snapshot: $snapshot_id"
    echo "Target PVC: ${target_pvc:-<none - will list snapshots>}"
    echo "Source path: $restore_source_path"
    echo ""

    echo "Available snapshots for $source_namespace/$app_name:"
    echo ""
    echo "Checking for available snapshots..."
    if restic_cronjob_exists "$namespace" "$release"; then
        restic_exec_repo "$namespace" "$repo" "$release" -- snapshots --host "$source_namespace" 2>/dev/null || {
            echo "Note: No snapshots available yet for $source_namespace/$app_name"
            echo ""
            echo "Repository may not be initialized yet. First backup will create it."
        }
    else
        echo "Note: $release not deployed yet"
        echo ""
        echo "To deploy $release:"
        echo "  helmfile -l name=$release apply -e $namespace"
        if [ -n "$target_pvc" ]; then
            return 1
        fi
    fi

    if [ -z "$target_pvc" ]; then
        echo ""
        echo "========================================="
        echo "Restore Instructions"
        echo "========================================="
        echo ""
        echo "No target PVC specified. Use one of these commands:"
        echo ""
        echo "  $script $namespace $app_name $snapshot_id ${namespace}-${app_name}-pvc $source_namespace $release $restore_source_path    # Restore to PVC"
        echo ""
        return 0
    fi

    echo ""
    echo "========================================="
    echo "Starting Restore"
    echo "========================================="
    echo ""

    local lib_dir template_file pod_name temp_file
    lib_dir=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    template_file=${RESTIC_RESTORE_TEMPLATE_FILE:-$lib_dir/../../templates/restic-restore-job.yaml}
    pod_name="restic-restore-$(date +%s)-$$"

    if [ ! -f "$template_file" ]; then
        echo "Error: Template file not found: $template_file"
        return 1
    fi

    temp_file=$(mktemp)
    trap "rm -f '$temp_file'" EXIT

    sed -e "s/{{RESTORE_POD_NAME}}/$pod_name/g" \
        -e "s/{{NAMESPACE}}/$namespace/g" \
        -e "s|{{RESTIC_IMAGE}}|$RESTIC_IMAGE|g" \
        -e "s|{{RESTIC_REPOSITORY}}|$repo|g" \
        -e "s/{{SNAPSHOT_ID}}/$snapshot_id/g" \
        -e "s/{{TARGET_PVC}}/$target_pvc/g" \
        -e "s|{{RESTORE_SOURCE_PATH}}|$restore_source_path|g" \
        -e "s/{{RESTIC_HOST}}/$source_namespace/g" \
        -e "s/{{APP_NAME}}/$app_name/g" \
        -e "s/{{SCRIPTS_CONFIGMAP}}/$scripts_configmap/g" \
        -e "s/{{CREDENTIALS_SECRET}}/$credentials_secret/g" \
        "$template_file" > "$temp_file"

    if [ "${RESTIC_CLI_DRY_RUN:-}" = "1" ]; then
        echo "would_apply=$temp_file"
        return 0
    fi

    echo "Creating restore pod: $pod_name"
    kubectl apply -f "$temp_file"

    echo ""
    echo "Waiting for restore to complete..."
    echo "Following logs:"
    echo ""

    kubectl wait --for=condition=Ready pod/"$pod_name" -n "$namespace" --timeout=60s 2>/dev/null || true
    kubectl logs -f "$pod_name" -n "$namespace" 2>/dev/null || true

    echo ""
    echo "========================================="
    echo "Restore Complete"
    echo "========================================="
    echo ""
    echo "To clean up the restore pod:"
    echo "  kubectl delete pod $pod_name -n $namespace"
}

restic_self_check_render() {
    local expected_repo rendered_repo chart_dir

    if ! command -v helm >/dev/null 2>&1; then
        echo "helm is required for --with-render" >&2
        return 127
    fi

    expected_repo=$(restic_fallback_repository dev vaultwarden)
    chart_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../../helm/charts/restic-backup" && pwd)"
    rendered_repo=$(helm template restic-backup "$chart_dir" \
        --namespace dev \
        --set repository.appName=vaultwarden \
        --set 'pvcs[0].name=dev-vaultwarden-pvc' \
        --set 'pvcs[0].mountPath=/backup/vaultwarden' \
        | sed -n '/name: RESTIC_REPOSITORY/{n;s/^[[:space:]]*value: *//;s/^"//;s/"$//;p;q;}')

    [[ "$rendered_repo" == "$expected_repo" ]]
}

restic_self_check() {
    local with_render=${1:-}
    local out expected_repo expected_secret expected_keys banner
    expected_repo="b2:rpi-data:/kubernetes-pvcs/dev/vaultwarden"
    expected_secret=$(restic_credentials_secret restic-backup)
    expected_keys="$RESTIC_PASSWORD_KEY,$RESTIC_B2_ACCOUNT_ID_KEY,$RESTIC_B2_ACCOUNT_KEY_KEY"

    [[ "$(restic_fallback_repository dev vaultwarden)" == "$expected_repo" ]]

    out=$(RESTIC_LIB_NO_CLUSTER=1 RESTIC_EXEC_DRY_RUN=1 restic_exec dev vaultwarden -- snapshots --host dev)
    [[ "$out" == *"image=$RESTIC_IMAGE"* ]]
    [[ "$out" == *"RESTIC_REPOSITORY=$expected_repo"* ]]
    [[ "$out" == *"credential_secret=$expected_secret"* ]]
    [[ "$out" == *"credential_keys=$expected_keys"* ]]
    [[ "$out" == *"command=restic snapshots --host dev"* ]]

    banner=$(restic_cli_banner "Restic Snapshots" dev vaultwarden restic-backup "$expected_repo")
    [[ "$banner" == *"Restic Snapshots"* ]]
    [[ "$banner" == *"Repository: $expected_repo"* ]]

    out=$(RESTIC_CLI_DRY_RUN=1 restic_cli_require_cronjob dev restic-backup)
    [[ "$out" == "cronjob=restic-backup namespace=dev" ]]

    if out=$( ( restic_cronjob_exists() { return 1; }; restic_cli_backup ./restic-backup.sh dev vaultwarden ) 2>&1 ); then
        return 1
    fi
    [[ "$out" == *"Error: CronJob restic-backup not found in namespace dev"* ]]

    out=$(RESTIC_LIB_NO_CLUSTER=1 RESTIC_CLI_DRY_RUN=1 restic_cli_backup ./restic-backup.sh dev vaultwarden)
    [[ "$out" == *"Repository: $expected_repo"* ]]
    [[ "$out" == *"would_create_job=restic-backup-manual-"* ]]

    if [ "$with_render" = "--with-render" ]; then
        restic_self_check_render
    fi

    echo "restic lib self-check passed"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    case "${1:-}" in
        --self-check|--dry-run)
            restic_self_check "${2:-}"
            ;;
        --with-render)
            restic_self_check --with-render
            ;;
        *)
            echo "Usage: $0 --self-check [--with-render]" >&2
            exit 2
            ;;
    esac
fi
