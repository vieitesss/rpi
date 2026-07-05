<!-- label: wayfinder:map -->
# Self-hosted private git server (Forgejo on Tailscale)

The map. Low-resolution index of the whole effort. Open tickets are the files
in `tickets/` with `status: open`; find the frontier by query (see below).

## Notes

**Domain:** Stand up a private git forge on the K3s homelab so private repos
can be pushed/pulled from the Mac and the Pi over Tailscale.

**Locked-in shape (from grilling):**
- **Software:** Forgejo (community Gitea fork), SQLite backend — single user.
- **Transport:** SSH primary + HTTPS web UI.
- **Reach:** Tailscale-only. No Cloudflare, nothing internet-facing.
- **Path:** `dev` first, then `pro`, per repo convention.
- **Fit existing patterns:** generic Helm chart via Helmfile, HTTPS on the
  `tailscale` Ingress, secrets via ExternalSecrets/GCP Secret Manager only if
  needed, PVC backed up by a `restic-backup-*` release to B2.

**Skills every session should consult:** `/grilling` + `/domain-modeling` for
open decisions; ponytail is active — lean solutions, reuse the generic chart
and existing values patterns before writing anything new.

**Standing preferences:** small declarative changes; validate in `dev` before
`pro`; never commit secrets; never commit without explicit request.

## Decisions so far

<!-- one line per closed ticket: gist + link. Empty until tickets resolve. -->

- [Deploy Forgejo web UI to dev on Tailscale](tickets/01-deploy-forgejo-web-ui-to-dev.md) — `forgejo` release (generic chart) live in dev at `forgejo-dev.burro-ph.ts.net`, image `forgejo:11`, 10Gi PVC at `/data`, install-locked; admin bootstrapped via one `forgejo admin user create` exec (must-change-password), not an ExternalSecret.
- [Expose Forgejo SSH over Tailscale and verify a clone](tickets/02-expose-forgejo-ssh-via-tailscale.md) — added optional tailscale `LoadBalancer` service to the generic chart (`lbService`, default off); forgejo git-SSH live at `forgejo-git-dev.burro-ph.ts.net:22`, host keys persist on the `/data` PVC; clone verified from the Pi. Clone URL form `git@forgejo-git-dev.burro-ph.ts.net:<owner>/<repo>.git`.
- [Back up the Forgejo PVC with restic (dev)](tickets/03-restic-backup-forgejo-dev.md) — `restic-backup-forgejo` release (values dev/pro + helmfile block, `appName: forgejo`, `<env>-forgejo-pvc`→`/backup/forgejo`, scaleDown off / SQLite WAL, schedule `45 23 * * *`); dev snapshot `0f29c4d3` verified, restore drill into scratch PVC confirmed the DB restores. Mirrors the GitHub backup map [#17](https://github.com/vieitesss/rpi/issues/17).
- [Push a real private repo from the Mac end-to-end](tickets/04-push-real-repo-from-mac.md) — Mac SSH checklist delivered (Tailscale + `ssh-keygen` + upload pubkey in web UI); clone URL form `git@forgejo-git.burro-ph.ts.net:<owner>/<repo>.git`, optional `~/.ssh/config` alias, host key `SHA256:gPtXP9qsgsuxBeu50LApJHqyCrTpXIEd2hXN+guCG8g`. Human runs the final push.
- [Promote Forgejo to pro](tickets/05-promote-forgejo-to-pro.md) — Forgejo live in pro (`values/forgejo/pro.yaml`, hostnames `forgejo`/`forgejo-git`), admin `vieitesss` bootstrapped, `restic-backup-forgejo` synced in pro, first snapshot `67783871` verified. Effort complete.

## Fog

- **Generic chart configMap has no checksum annotation** — cm-only value
  changes don't restart the pod, so config edits need a manual
  `kubectl rollout restart` to apply (hit while setting `SSH_DOMAIN`). Consider
  adding a `checksum/config` annotation to the generic deployment template;
  affects all releases, so weigh before doing it.
- **Migrating existing repos** in from GitHub/elsewhere (bulk import vs. manual
  push) — deferred until the server works end-to-end.
- **Public web UI via Cloudflare** (`git.<domain>`) — explicitly deferred;
  Tailscale-only for now. Revisit only if browsing without the tailnet is ever
  wanted.

## Frontier query (local-markdown tracker)

Frontier = `tickets/*.md` where `status: open`, `assignee:` empty, and every
title in `blocked-by:` maps to a ticket with `status: closed`.
