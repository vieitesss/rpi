#!/usr/bin/env bash
# Tailnet policy and Tailscale Services, through the Tailscale API.
#   tailnet-policy.sh pull <dir>   save the live policy (HuJSON) and its ETag
#   tailnet-policy.sh push <dir>   validate <dir>/policy.new.hujson, show the
#                                  diff, upload after a yes (fails if the live
#                                  policy changed since the pull)
#   tailnet-policy.sh services     create or update the pro Services
# Needs a short-lived API access token: TS_API_KEY, or typed when asked.
# The token never reaches argv or output.
set -euo pipefail

api=https://api.tailscale.com/api/v2/tailnet/-

# service=ports (tags mirror the old operator proxies: tandem was shared)
services=(
  vaultwarden=tcp:443
  tandem=tcp:443
  tandem-backend=tcp:443
  home=tcp:443
  glances=tcp:443
  forgejo=tcp:443
  forgejo-git=tcp:22
  backrest=tcp:443
)
service_tag() {
  case $1 in
    tandem | tandem-backend) echo tag:shared ;;
    *) echo tag:private ;;
  esac
}

auth=$(mktemp)
trap 'rm -f "$auth"' EXIT
chmod 600 "$auth"
if [[ -z ${TS_API_KEY:-} ]]; then
  read -rsp "Tailscale API access token: " TS_API_KEY
  echo
fi
printf 'Authorization: Bearer %s\n' "$TS_API_KEY" >"$auth"
unset TS_API_KEY

call() { curl -fsS -H @"$auth" "$@"; }

cmd=${1:?usage: tailnet-policy.sh <pull|push> <dir> | services}
case $cmd in
  pull)
    dir=${2:?usage: tailnet-policy.sh pull <dir>}
    mkdir -p "$dir"
    call -H 'Accept: application/hujson' -D "$dir/headers" "$api/acl" >"$dir/policy.hujson"
    awk 'tolower($1) == "etag:" { sub(/\r$/, "", $2); print $2 }' "$dir/headers" >"$dir/etag"
    rm "$dir/headers"
    [[ -s $dir/etag ]] || { echo "no ETag in the response" >&2; exit 1; }
    cp -n "$dir/policy.hujson" "$dir/policy.new.hujson" || true
    echo "saved $dir/policy.hujson; edit $dir/policy.new.hujson, then push"
    ;;
  push)
    dir=${2:?usage: tailnet-policy.sh push <dir>}
    new=$dir/policy.new.hujson
    diff -u "$dir/policy.hujson" "$new" && { echo "no changes"; exit 0; }
    # validate answers 200 with a "message" when the policy is invalid
    result=$(call -H 'Content-Type: application/hujson' --data-binary @"$new" "$api/acl/validate")
    if [[ $(jq -r '.message // empty' <<<"$result") ]]; then
      echo "invalid policy: $result" >&2
      exit 1
    fi
    read -rp "Upload this policy? [y/N] " answer
    [[ $answer == y ]] || { echo "not uploaded"; exit 1; }
    call -H 'Content-Type: application/hujson' -H "If-Match: $(<"$dir/etag")" \
      --data-binary @"$new" "$api/acl" >/dev/null
    echo "policy uploaded; pull again before the next edit"
    ;;
  services)
    for pair in "${services[@]}"; do
      name=${pair%%=*}
      body=$(jq -n --arg name "svc:$name" --arg port "${pair#*=}" --arg tag "$(service_tag "$name")" \
        '{name: $name, comment: "rpi pro (docker compose), served by scripts/tailscale-serve.sh", ports: [$port], tags: [$tag]}')
      call -X PUT -H 'Content-Type: application/json' -d "$body" "$api/services/svc:$name" |
        jq -r '"\(.name) \(.addrs | join(" ")) \(.ports | join(","))"'
    done
    ;;
  *)
    echo "unknown command: $cmd" >&2
    exit 1
    ;;
esac
