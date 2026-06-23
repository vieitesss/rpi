# ADR: Keep three named restic entrypoints over one dispatcher

## Status

Accepted (2026-06-22)

## Context

`restic-backup.sh`, `restic-list.sh`, and `restic-restore.sh` are shallow host
wrappers that duplicate ceremony (arg parse, usage, CronJob guard, banner)
around one lib call each. Deepening (decision C) could either collapse them into
a single `restic.sh <verb>` dispatcher (fewest files) or keep the three names
and push the shared ceremony down into `lib/restic.sh`.

The three names are a public interface: AGENTS.md and `docs/ops.md` invoke them
by name with positional args. These are run by hand, often under pressure during
a restore.

## Decision

Keep the three named entrypoints with unchanged positional arg order. Move the
duplicated ceremony into lib helpers (`restic_cli_*`); each script becomes a thin
dispatcher that sources the lib and calls one helper.

## Consequences

- Zero call-site churn for the supported backup/list/restore entrypoints.
- Three discoverable verbs survive; the duplication behind them is removed.
- Trade-off accepted: one more file than a single dispatcher, in exchange for a
  stable interface on a tool used during incident recovery.
