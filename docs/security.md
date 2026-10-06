# Security

## Secrets

- GCP Secret Manager (project `GCP_PROJECT` in `.env`) is the only source of
  truth for credentials. Nothing secret lives in git.
- `scripts/secrets.sh` pulls them **at deploy time only** (`just deploy pro`,
  `just dev-seed`) into `~/.config/rpi/secrets.env` on the Pi (mode 0600, owned
  by the deploy user). Nothing polls Secret Manager: a rotated secret is picked
  up by the next deploy. Keep it that way; each access is billed.
- The file is user-owned rather than root-only on purpose: the deploy user is
  in the `docker` group, which is root-equivalent, so a root-only file would
  add a sudo prompt without adding protection.
- Compose passes the file to the containers that need it (`env_file`), never
  through the command line, so values do not show up in `ps` or logs.
- Never commit `.env`, `.backup.env`, `secrets.env` or any generated file with
  credentials. Never print secret values in commands or logs.

| Variable              | Secret Manager name    | Used by                    |
| --------------------- | ---------------------- | -------------------------- |
| `B2_ACCOUNT_ID`       | `rpi-b2-account-id`    | Backrest, dev-seed restic  |
| `B2_ACCOUNT_KEY`      | `rpi-b2-account-key`   | Backrest, dev-seed restic  |
| `RPI_RESTIC_PASSWORD` | `restic_password`      | Backrest, dev-seed restic  |
| `NTFY_TOPIC`          | `ntfy_backup_error`    | Backrest failure alerts    |

## Backrest config

Backrest owns `/srv/rpi/pro/backrest/config/config.json` (0600): it holds the
UI login hash and the instance's private sync identity, so it is never
committed. Git only tracks `compose/backrest/config.template.json` (repos and
plans, with `${VAR}` references instead of values); `just deploy pro` merges
those two keys into the live file.

## Network exposure

- Every container port binds to `127.0.0.1`. Nothing listens on the LAN.
- Only the host's tailscaled exposes them: pro as Tailscale Services, dev on
  host ports. Who can reach what is decided by the grants in the tailnet
  policy.
- Tailscale API tokens used by `scripts/tailnet-policy.sh` are short-lived and
  never stored; the script keeps them out of argv and output.

## Images

Container images are pulled from public registries, including
`ghcr.io/vieitesss/*`. Never bake secrets into an image; they are injected at
runtime.
