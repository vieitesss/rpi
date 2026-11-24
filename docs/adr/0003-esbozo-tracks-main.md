# esbozo is built from origin/main on the host

esbozo (`ez serve`, a folder of hand-drawn Scenes) runs in `pro`, but it has to
be the latest `origin/main` rather than a pinned version, so it is the one
Source-tracked service. A host systemd timer fetches a root-owned mirror clone
and, when a new commit lands, runs `pnpm install --frozen-lockfile` and
`node scripts/build.mjs` inside a `MemoryMax=512M` scope, writing a Build per
commit under `/srv/rpi/pro/esbozo/dist/<sha>` and repointing `current`. The
container itself is a pinned `node:22-slim` that mounts `dist/` read-only and is
restarted to pick up the new Build.

## Considered Options

- **Pinned image tag**, the rule for every other Service: no image exists to pin
  (esbozo's CI builds with `push: false`), and a tag puts a human between `main`
  and the running app.
- **CI publishes `ghcr.io/vieitesss/esbozo:main`**, the Pi only pulls: a registry
  and a rolling tag between the source and the container, and a timer is still
  needed to pull.
- **`docker build` per commit on the Pi**: BuildKit builds run under `dockerd`,
  so a systemd `MemoryMax` cannot bound them — the one thing this Pi, which
  already locked up from memory exhaustion, needs bounded.
- **Rebuild inside the running container**: no `node`/`pnpm` on the host, but the
  image then carries a toolchain and the build competes with the app's own
  `mem_limit`.

## Consequences

- `pro`'s rule becomes: every **runtime** image is pinned to an exact tag; a
  Source-tracked service pins only the image it runs in.
- `node` and `pnpm` (through corepack) become host dependencies of the deploy.
- Measured cost: the app build is 2.0 s and 86 MiB; install plus build stay under
  `MemoryMax=512M` in about 4 s against a warm pnpm store.
- A broken `main` can reach `pro` by design. The guard starts the candidate on a
  scratch port and requires `/api/health` to report the new sha before the swap;
  the previous three Builds stay on disk for a manual revert, and a failed build
  or guard keeps the running container.
- esbozo spends the tenth and last Tailscale Service slot.
