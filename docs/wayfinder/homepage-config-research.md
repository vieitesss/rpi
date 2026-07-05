# Research: Homepage config model + generic-chart file mounting

Resolves [Research: Homepage config model + generic-chart file mounting](https://github.com/vieitesss/rpi/issues/13)
(child of [Map: home dashboard for pro apps](https://github.com/vieitesss/rpi/issues/12)).

## Homepage config contract

- Image: `ghcr.io/gethomepage/homepage`. HTTP listens on **port 3000** (`service.targetPort: 3000`).
- Reads all config from **`/app/config`**. Relevant files: `settings.yaml`, `services.yaml`,
  `bookmarks.yaml`, `widgets.yaml` (plus `docker.yaml`, `kubernetes.yaml`, `custom.css`, `custom.js`
  which we can omit).
- For **bare links only** (the locked-in depth), we need just two files:
  - `services.yaml` — the 6 pro app tiles (name + `href` + `icon`), optionally grouped.
  - `settings.yaml` — title/theme (optional; can stay minimal or be skipped).
  - `bookmarks.yaml` / `widgets.yaml` — not needed; provide empty `{}`/`[]` if the image complains.
- **Two gotchas:**
  1. **`HOMEPAGE_ALLOWED_HOSTS` is required** (since v1.0). Requests are rejected with a host-validation
     error unless the served host is listed. Set it to `home.burro-ph.ts.net`. This is a plain **env var**,
     so it goes in the chart's existing `cm.data`.
  2. On startup Homepage tries to **seed any missing config file into `/app/config`**. If that path is a
     read-only mount, seeding logs errors. Avoid this by **providing every file Homepage looks for as its own
     ConfigMap key** — with all keys present it does not attempt to write.

## Can the generic chart deliver it?

The chart (`kubernetes/helm/charts/generic`) already has the two pieces needed:

- `cm.data` → renders a ConfigMap consumed via **`envFrom`** — perfect for `HOMEPAGE_ALLOWED_HOSTS`
  and any other env, but **not** for mounting YAML files (keys like `services.yaml` contain a `.`,
  which is an invalid env-var name; kubelet would skip them and emit warning events).
- `deployment.extraVolumes` / `deployment.extraVolumeMounts` → arbitrary volumes, including a
  `configMap:` volume source, mounted anywhere. This is how config **files** get into the pod.

**Missing piece:** the chart only renders the *env* ConfigMap (`<fullName>-cm`). It has no template for a
separate file-oriented ConfigMap, so today there is nothing to point an `extraVolumes` `configMap:` source at
without either abusing `cm.data` (env warnings) or hand-applying an out-of-chart ConfigMap.

## Chosen mount mechanism (lazy, reusable)

Add a **small `configFiles` block** to the generic chart:

- New template `configmap-files.yaml`: renders a ConfigMap `<fullName>-files` from `.Values.configFiles`
  (a `filename: contents` map), only when non-empty. ~10 lines, mirrors the existing `configmap.yaml`.
- Homepage's values then set `configFiles.services.yaml`, `configFiles.settings.yaml`, etc., and wire the
  mount through the **existing** `extraVolumes`/`extraVolumeMounts`:

```yaml
deployment:
  extraVolumes:
    - name: homepage-config
      configMap:
        name: home-files          # <release>-files
  extraVolumeMounts:
    - name: homepage-config
      mountPath: /app/config
cm:
  data:
    HOMEPAGE_ALLOWED_HOSTS: home.burro-ph.ts.net
configFiles:
  services.yaml: |
    ...
  settings.yaml: |
    ...
service:
  targetPort: 3000
ingress:
  hostname: home
```

Why this over the alternatives:

- **Reuse `cm.data` for files** → invalid env keys, skipped-with-warning events. Ugly.
- **initContainer writing files** (like anythingllm's MCP seed) → more moving parts than a ConfigMap,
  and worse for hand-maintained static YAML.
- **`configFiles` ConfigMap** → cleanest, reuses the already-present `extraVolumes` plumbing, one tiny
  reusable template, no writes to a read-only mount, and future services get file-mount support for free.

Provide every file Homepage seeks (at minimum `services.yaml`; add empty `settings.yaml`/`bookmarks.yaml`/
`widgets.yaml` if the image warns) so nothing is written at runtime and the mount can stay read-only.
