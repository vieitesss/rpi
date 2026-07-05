<!-- child-of: Self-hosted private git server (Forgejo on Tailscale) -->
# Expose Forgejo SSH over Tailscale and verify a clone

- label: wayfinder:prototype
- status: closed
- assignee: Daniel
- blocked-by: Deploy Forgejo web UI to dev on Tailscale

## Question

Expose Forgejo's git-SSH (port 22) on a Tailscale-exposed `LoadBalancer`
service (e.g. `forgejo-git-dev`), persisting the SSH host key across restarts,
and set Forgejo's SSH domain/port config so clone URLs are correct.

Investigate first: does the generic chart emit a second `LoadBalancer` service
and persist a host key, or is a small bespoke manifest needed? (Resolves the
"generic chart / SSH service" fog.)

Verify: add a public key to the admin user and `git clone git@<name>:...`
succeeds from the Pi.

## Resolution

**Investigation:** The generic chart emitted only a single ClusterIP `-svc`
(no second service). Forgejo's built-in SSH server already listens on port 22
and writes its host keys to `/data/ssh/ssh_host_*` — already persisted by the
existing 10Gi `/data` PVC, so no extra host-key handling was needed.

**Change:** Extended `generic/templates/service.yaml` with an optional second
tailscale `LoadBalancer` service (`loadBalancerClass: tailscale`), gated by
`lbService.enabled` (default absent/off, so no other release changes). Enabled
it for forgejo (`lbService`: name `ssh`, port 22, tag `tag:private`) in
`values/forgejo/values.yaml`; hostname `forgejo-git-dev` + `SSH_DOMAIN` in
`dev.yaml`.

**Verified (dev):**
- `dev-forgejo-lb` LoadBalancer got tailnet `forgejo-git-dev.burro-ph.ts.net`
  (100.97.75.90), port 22 → 22.
- Registered an ephemeral key on admin `daniel` and
  `git clone git@forgejo-git-dev.burro-ph.ts.net:daniel/<repo>.git` succeeded
  from the Pi. Test repo/key/token all cleaned up afterward.

**Gotcha:** the generic chart's `envFrom` configMap has no checksum
annotation, so cm-only changes don't restart the pod — `SSH_DOMAIN` needed a
manual `kubectl rollout restart` to apply. (New fog on the map.)

**Clone URL form:** `git@forgejo-git-dev.burro-ph.ts.net:<owner>/<repo>.git`
