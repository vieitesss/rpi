#!/usr/bin/env python3
"""Merge the git-tracked Backrest repos and plans into the live config.json.

Backrest owns config.json: it rewrites it and keeps the login, the instance id
and its sync identity there. So only `repos` and `plans` come from the
template; every other key keeps its live value (the template only fills keys
the live config lacks, e.g. on a first deploy).

${B2_BUCKET} in the template is filled from the environment (.env).

Usage: backrest-config.py TEMPLATE < live.json > merged.json
Empty stdin means there is no live config yet. Exits 3, printing nothing,
when the merge would change nothing. Never prints the live config otherwise:
it holds secrets.
"""

import json
import os
import sys

FROM_TEMPLATE = ("repos", "plans")
# Other ${...} (e.g. RPI_RESTIC_PASSWORD) are left for Backrest to expand.
FROM_ENV = ("B2_BUCKET",)
UNCHANGED = 3


def main() -> int:
    with open(sys.argv[1]) as f:
        text = f.read()
    for var in FROM_ENV:
        text = text.replace("${%s}" % var, os.environ[var])
    template = json.loads(text)
    raw = sys.stdin.read()
    live = json.loads(raw) if raw.strip() else {}

    merged = {**template, **live}
    for key in FROM_TEMPLATE:
        merged[key] = template[key]

    if merged == live:
        return UNCHANGED
    json.dump(merged, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
