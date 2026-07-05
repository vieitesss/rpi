<!-- child-of: Self-hosted private git server (Forgejo on Tailscale) -->
# Back up the Forgejo PVC with restic (dev)

- label: wayfinder:task
- status: closed
- assignee:
- blocked-by: Deploy Forgejo web UI to dev on Tailscale

## Question

Add a `restic-backup-forgejo` release following the existing `restic-backup-*`
pattern: its own B2 service repo, scheduled CronJob (staggered UTC time),
ntfy failure alert, `refreshInterval: "0"` on any ExternalSecret. Run once and
verify a snapshot exists and lists the Forgejo data path.

Answer records: repo name, schedule time, first snapshot id.
