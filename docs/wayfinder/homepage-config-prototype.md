# Prototype: Homepage `services.yaml` + `settings.yaml`

Resolves [Prototype: draft Homepage services.yaml + settings.yaml](https://github.com/vieitesss/rpi/issues/15)
(child of [Map: home dashboard for pro apps](https://github.com/vieitesss/rpi/issues/12)).

Bare links only (name + icon + `href`), one group, pro URLs from
[#14](https://github.com/vieitesss/rpi/issues/14). Drops straight into the
`configFiles` block from the [config research](https://github.com/vieitesss/rpi/blob/main/docs/wayfinder/homepage-config-research.md).

## `services.yaml`

```yaml
- Apps:
    - Vaultwarden:
        href: https://vaultwarden.burro-ph.ts.net
        icon: vaultwarden.png
    - AnythingLLM:
        href: https://ai.burro-ph.ts.net
        icon: anythingllm.png
    - IT-Tools:
        href: https://ittools.burro-ph.ts.net
        icon: it-tools.png
    - Glances:
        href: https://glances.burro-ph.ts.net
        icon: glances.png
    - Backrest:
        href: https://backrest.burro-ph.ts.net
        icon: backrest.png
    - Tandem:
        href: https://tandem-pro.burro-ph.ts.net
        icon: mdi-account-group
```

## `settings.yaml`

```yaml
title: Home
headerStyle: clean
layout:
  Apps:
    style: row
    columns: 3
```

## Icon notes (the one calibration knob)

Icons resolve against [dashboard-icons](https://github.com/homarr-labs/dashboard-icons)
by the `.png` slug, or `mdi-<name>` for Material Design fallbacks. Confirmed-safe
slugs: `vaultwarden`, `anythingllm`, `it-tools`, `glances`. `backrest.png` is
likely present but unverified; if a tile shows a blank icon after deploy, swap to
`mdi-backup-restore`. Tandem has no dashboard-icons entry, so it uses the MDI
fallback `mdi-account-group` — adjust to taste once the dashboard is live.

Everything else (widgets, status pings, bookmarks) stays out per the locked-in
"bare links only" depth. Feeds the ship ticket [#16](https://github.com/vieitesss/rpi/issues/16).
