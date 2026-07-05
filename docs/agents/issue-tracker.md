# Issue tracker (Wayfinding operations)

This repo's Wayfinder maps and tickets live as **GitHub issues** on
`vieitesss/rpi`, driven with the `gh` CLI. (There is no local `.wayfinder/`
markdown tracker — it was migrated to GitHub.)

- **Map** — an issue labelled `wayfinder:map`. Body holds `## Notes`,
  `## Decisions so far` (one line per closed ticket, linking its issue URL by
  name), and `## Fog`.
- **Tickets** — issues labelled `wayfinder:<type>` (`research`, `prototype`,
  `grilling`, `task`). Body is `## Question`, followed by a footer:
  `**Parent map:** #<map>` and, when blocked, `**Blocked by:** #<a>, #<b>`.
- **Blocking** — body convention (`**Blocked by:** #N`), since the pinned `gh`
  here predates native issue dependencies. A ticket is **unblocked** when every
  issue it lists is closed.
- **Claim** — assign the issue to yourself (`gh issue edit <n> --add-assignee`)
  before working it. An open, unassigned frontier ticket is unclaimed.
- **Frontier** — open + unassigned + all `Blocked by` issues closed.
  Find open tickets: `gh issue list -l wayfinder:map` for maps;
  child tickets carry their type label and a `Parent map: #<map>` footer.
- **Resolve** — post the answer as a **comment**, `gh issue close` it, then
  append a one-line gist + issue link to the map's `## Decisions so far`.
