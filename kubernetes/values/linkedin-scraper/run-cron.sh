#!/usr/bin/env bash
set -euo pipefail

notify_failure() {
  local code=$?
  if [ "${NOTIFICATIONS_ENABLED:-false}" = "true" ] && [ -n "${NTFY_TOPIC:-}" ]; then
    curl -fsS -d "LinkedIn scraper failed in ${NAMESPACE:-unknown} (exit ${code})" \
      "${NTFY_URL:-https://ntfy.sh}/${NTFY_TOPIC}" >/dev/null || true
  fi
  exit "$code"
}
trap notify_failure ERR

apt_get_install() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends postgresql-client ca-certificates
  rm -rf /var/lib/apt/lists/*
}

command -v psql >/dev/null 2>&1 || apt_get_install

rm -rf /work
mkdir -p /work/out
cp /scripts/scrape.mjs /scripts/parse_xlsx.py /work/
cd /work

npm init -y >/dev/null
npm install --omit=dev --no-audit --no-fund "playwright@${PLAYWRIGHT_VERSION:-1.53.0}" >/dev/null

python3 parse_xlsx.py --self-test
node scrape.mjs

shopt -s nullglob
files=(out/*.xlsx)
if [ "${#files[@]}" -eq 0 ]; then
  echo "no XLSX exports downloaded" >&2
  exit 1
fi

python3 parse_xlsx.py "${files[@]}" --psql "psql -h ${PGHOST} -p ${PGPORT:-5432} -U ${PGUSER:-postgres} -d ${PGDATABASE:-linkedin} -v ON_ERROR_STOP=1"
