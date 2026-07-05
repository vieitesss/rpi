<!-- child-of: Self-hosted private git server (Forgejo on Tailscale) -->
# Promote Forgejo to pro

- label: wayfinder:task
- status: closed
- assignee:
- blocked-by: Push a real private repo from the Mac end-to-end, Back up the Forgejo PVC with restic (dev)

## Question

Once dev is proven end-to-end and backed up, replicate to `pro`: pro values
overlay (hostname `forgejo`, `forgejo-git`), pro PVC, pro restic release with
its own B2 repo and schedule. Deploy, verify web UI + SSH clone over Tailscale,
and confirm the pro backup produces a snapshot.

This is the final ticket; the effort is done when pro serves and backs up.
