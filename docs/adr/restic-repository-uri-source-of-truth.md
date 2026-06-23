# ADR: Restic repository URI source of truth

## Status

Accepted (2026-06-22)

## Context

The repository URI shape `b2:<bucket>:/<basePath>/<namespace>/<appName>` was
authored independently in ~6 places: the chart CronJob env, the chart configmap
log echoes, the chart values, the bash builder in `lib/restic.sh`, and the host
helper scripts. `restic-backup.sh` recomputed the URI in bash and **aborted on
mismatch** against the live CronJob — a guard that only existed because two
authorities (the templated string and the bash formula) could silently drift.

For the current repo all copies resolve to the same string (no release overrides
`bucket`/`basePath`, and `app` is passed to match `repository.appName`), so the
copies are equivalent today. The risk is future drift, and this is the
backup/restore (data-loss) seam: a silently-wrong URI on a restore points at the
wrong or empty repo.

## Decision

- The **live CronJob `RESTIC_REPOSITORY` env is the authority** for any deployed
  release. Helm computes it once at deploy time; host scripts read it back via
  `restic_cronjob_repository` (through `restic_repository`).
- The bash builder is **fallback-only**, used in exactly one case with no
  reachable CronJob: cross-namespace restore
  (`restic-restore.sh <ns> <app> ... <source-namespace> ...`). It is renamed
  `restic_default_repository` -> `restic_fallback_repository` so the name signals
  "no-CronJob path only".
- The mismatch-warn branch in `restic-backup.sh` is **deleted** — once the
  CronJob is authoritative there is nothing to warn against.
- The configmap log echoes print `$RESTIC_REPOSITORY` instead of re-authoring the
  shape.

## Consequences

- The shape is still literally authored in two places that bridge the bash↔Helm
  boundary (chart env, bash fallback) because Helm cannot call bash. A
  `restic_self_check` assertion pins them so they cannot silently diverge.
- Host tooling cannot compute a wrong repo for a deployed release; it reads what
  is actually deployed.
- Trade-off accepted: one extra `kubectl get` per host invocation in exchange for
  removing the drift class on the restore path.
