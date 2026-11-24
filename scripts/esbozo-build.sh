#!/usr/bin/env bash
# Advance esbozo to origin/main: mirror-clone, build in a memory-capped
# systemd scope, guard the candidate in a scratch container, swap current,
# restart the pro container, and prune old Builds.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)

ESBOZO_ROOT=${ESBOZO_ROOT:-/srv/rpi/pro/esbozo}
ESBOZO_REPO=${ESBOZO_REPO:-https://github.com/vieitesss/esbozo.git}
ESBOZO_BRANCH=${ESBOZO_BRANCH:-main}
ESBOZO_KEEP=${ESBOZO_KEEP:-3}
ESBOZO_PORT=${ESBOZO_PORT:-9070}
ESBOZO_NODE_IMAGE=${ESBOZO_NODE_IMAGE:-node:22.22.3-slim}
ESBOZO_SCENES_UID=${ESBOZO_SCENES_UID:-1000}
ESBOZO_SCENES_GID=${ESBOZO_SCENES_GID:-1000}

PROBE_PORT=4399

dry_run=0
prune_only=0
notified=0
probe_name=""
stage_dir=""

usage() {
  cat <<'EOF'
usage: esbozo-build.sh [--dry-run] [--prune-only] [--help]

  --dry-run     Build and guard the candidate, but do not swap or prune.
  --prune-only  Prune old Builds under $ESBOZO_ROOT/dist and exit.
  --help        Show this message and exit.
EOF
}

notify() {
  "$here/notify.sh" "esbozo-build: $*" 2>/dev/null || true
}

die() {
  echo "esbozo-build: $*" >&2
  notified=1
  notify "FAILED: $*"
  exit 1
}

cleanup() {
  if [[ -n "$probe_name" ]]; then
    docker rm -f "$probe_name" >/dev/null 2>&1 || true
    probe_name=""
  fi
  if [[ -n "$stage_dir" && -d "$stage_dir" ]]; then
    rm -rf -- "$stage_dir"
    stage_dir=""
  fi
}

on_err() {
  local line=$1
  if ((notified == 0)); then
    echo "esbozo-build: failed at line $line" >&2
    notified=1
    notify "FAILED at line $line"
  fi
}

trap cleanup EXIT
trap 'on_err $LINENO' ERR

while (($#)); do
  case $1 in
    --dry-run) dry_run=1 ;;
    --prune-only) prune_only=1 ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

health_matches() {
  local port=$1 expected_sha=$2
  local body
  body=$(curl -fsS --connect-timeout 2 --max-time 3 "http://127.0.0.1:${port}/api/health" 2>/dev/null) || return 1
  grep -Eq "\"build\"[[:space:]]*:[[:space:]]*\"${expected_sha}\"" <<<"$body"
}

wait_for_health() {
  local port=$1 expected_sha=$2 attempts=${3:-30}
  local i
  for i in $(seq "$attempts"); do
    if health_matches "$port" "$expected_sha"; then
      return 0
    fi
    if ((i < attempts)); then
      sleep 1
    fi
  done
  return 1
}

prune_builds() {
  [[ "$ESBOZO_KEEP" =~ ^[0-9]+$ ]] \
    || die "invalid ESBOZO_KEEP: $ESBOZO_KEEP (must be a non-negative integer)"

  local dist_dir="$ESBOZO_ROOT/dist"
  [[ -d "$dist_dir" ]] || return 0

  local current_target=""
  if [[ -L "$dist_dir/current" ]]; then
    current_target=$(basename "$(readlink -f "$dist_dir/current")")
  fi

  local -a dirs=()
  mapfile -t dirs < <(
    find "$dist_dir" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -printf '%T@ %f\n' \
      | sort -rn \
      | awk '{print $2}'
  )

  local i=0 name
  for name in "${dirs[@]}"; do
    i=$((i + 1))
    if ((i <= 10#$ESBOZO_KEEP)) || [[ -n "$current_target" && "$name" == "$current_target" ]]; then
      continue
    fi
    if ((dry_run)); then
      echo "esbozo-build: dry-run: would prune $name"
    else
      echo "esbozo-build: pruning $name"
      rm -rf -- "$dist_dir/$name"
    fi
  done

  # Reap stale stage dirs (.<sha>.tmp.<pid>) left behind by a killed run.
  # Test PID liveness with kill -0 so an in-flight concurrent run's stage dir
  # is never deleted out from under it.
  local -a stage_dirs=()
  mapfile -t stage_dirs < <(
    find "$dist_dir" -mindepth 1 -maxdepth 1 -type d -name '.*.tmp.*' -printf '%f\n'
  )

  local stage pid
  for stage in "${stage_dirs[@]}"; do
    pid=${stage##*.tmp.}
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    if kill -0 "$pid" 2>/dev/null; then
      continue
    fi
    if ((dry_run)); then
      echo "esbozo-build: dry-run: would prune stale stage dir $stage"
    else
      echo "esbozo-build: pruning stale stage dir $stage"
      rm -rf -- "$dist_dir/$stage"
    fi
  done
}

if ((prune_only)); then
  prune_builds
  exit 0
fi

# 1. Probe the live container before anything else; warn and continue if down.
if ! curl -fsS --connect-timeout 2 --max-time 3 "http://127.0.0.1:${ESBOZO_PORT}/api/health" >/dev/null 2>&1; then
  echo "esbozo-build: warning: live container unhealthy on 127.0.0.1:${ESBOZO_PORT}" >&2
  notify "live container unhealthy on 127.0.0.1:${ESBOZO_PORT}"
fi

# 2. Mirror clone / advance to origin/$ESBOZO_BRANCH.
src="$ESBOZO_ROOT/src"
dist_root="$ESBOZO_ROOT/dist"
scenes_dir="$ESBOZO_ROOT/scenes"
mkdir -p "$dist_root"
# Create scenes/ owned by the container's node user (uid:gid 1000:1000) so
# dockerd never auto-creates it root-owned on the guard mount. Never chown or
# touch an existing scenes/ so user-owned Scenes keep their ownership and mode.
if [[ ! -d "$scenes_dir" ]]; then
  mkdir -p "$scenes_dir"
  chown "${ESBOZO_SCENES_UID}:${ESBOZO_SCENES_GID}" "$scenes_dir"
fi

if [[ ! -d "$src/.git" ]]; then
  git clone --depth 1 --branch "$ESBOZO_BRANCH" "$ESBOZO_REPO" "$src"
else
  git -C "$src" fetch --depth 1 origin "$ESBOZO_BRANCH"
  git -C "$src" reset --hard FETCH_HEAD
fi

sha=$(git -C "$src" rev-parse --short HEAD)
build="$dist_root/$sha"

if [[ -d "$build" ]]; then
  echo "esbozo-build: $sha already built, reconciling"
else
  # 3. Build in a memory-capped systemd scope.
  export PATH="/home/vieitesrpi/.local/share/pi-node/current/bin:$PATH"
  command -v node >/dev/null 2>&1 || die "node not found on PATH ($PATH)"

  (
    cd "$src"
    systemd-run --scope --quiet --collect \
      -p MemoryMax=512M -p MemorySwapMax=256M \
      -- env "PATH=$PATH" bash -euo pipefail -c \
      'corepack pnpm install --frozen-lockfile && node scripts/build.mjs'
  )

  [[ -d "$src/dist" ]] || die "build succeeded but $src/dist is missing"

  # 4. Stage dist/ into a temporary directory before guarding.
  stage_dir="$dist_root/.${sha}.tmp.$$"
  mkdir -p "$stage_dir"
  cp -a "$src/dist/." "$stage_dir/"

  # 5. Guard: boot candidate on a scratch port and verify health + scenes.
  probe_name="esbozo-probe-$$"
  docker run --rm -d \
    --name "$probe_name" \
    -p "127.0.0.1:${PROBE_PORT}:4320" \
    -v "$stage_dir":/app/dist:ro \
    -v "$ESBOZO_ROOT/scenes":/scenes:ro \
    --entrypoint node "$ESBOZO_NODE_IMAGE" \
    /app/dist/cli.js serve /scenes --host 0.0.0.0 >/dev/null

  wait_for_health "$PROBE_PORT" "$sha" \
    || die "guard failed: /api/health did not report build $sha within 30s"

  curl -fsS --connect-timeout 2 --max-time 3 "http://127.0.0.1:${PROBE_PORT}/api/scenes" >/dev/null \
    || die "guard failed: GET /api/scenes did not return 200"

  docker rm -f "$probe_name" >/dev/null 2>&1 || true
  probe_name=""

  mv "$stage_dir" "$build"
  stage_dir=""
fi

if ((dry_run)); then
  echo "esbozo-build: dry-run passed for $sha (no swap, no prune)"
  exit 0
fi

# 6. Query containers, atomically swap current, and reconcile the pro container.
ps_out=$(
  docker ps -q \
    --filter label=com.docker.compose.project=rpi-pro \
    --filter label=com.docker.compose.service=esbozo
) || die "docker ps failed"

containers=()
if [[ -n "$ps_out" ]]; then
  mapfile -t containers <<<"$ps_out"
fi

((${#containers[@]} <= 1)) || die "expected 1 esbozo container, found ${#containers[@]}"

ln -sfn "$sha" "$dist_root/.current.new"
mv -Tf "$dist_root/.current.new" "$dist_root/current"

if ((${#containers[@]} == 0)); then
  prune_builds
  echo "esbozo-build: current -> $sha; esbozo container not deployed yet, skipping restart"
  exit 0
fi

if ! wait_for_health "$ESBOZO_PORT" "$sha" 4; then
  docker restart "${containers[0]}" >/dev/null

  wait_for_health "$ESBOZO_PORT" "$sha" \
    || die "post-swap health check failed: live container did not report build $sha within 30s"
fi

# 7. Prune old Builds after a successful swap.
prune_builds
echo "esbozo-build: live on $sha"
