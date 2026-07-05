# LinkedIn scraper feasibility spike (#24)

Cheapest probe of the load-bearing question: can a headless browser,
authenticated with a **saved session cookie**, (a) enumerate every post from the
last month on the profile and (b) trigger + capture each post's analytics XLSX
export (same file as `example-data.xlsx`)?

## Files

- `cookie.mjs` — build `storageState.json` from a `li_at` cookie copied out of
  your real browser. **Preferred** — LinkedIn bot-detects the automated login.
- `login.mjs` — one-time in-browser manual login → writes `storageState.json`.
  Often blocked by *"This browser or app may not be secure"*; use `cookie.mjs`.
- `scrape.mjs` — enumerate last-month posts, download one post's XLSX export.
- `.gitignore` — keeps `storageState.json` and `out/` out of git (session cookie
  is a credential; never commit it).

## Run it (the human's single verification pass)

```bash
cd spikes/linkedin-scraper
npm i playwright && npx playwright install chromium
# Preferred: log into linkedin.com in your normal browser, then DevTools →
# Application → Cookies → https://www.linkedin.com → copy the `li_at` value.
LI_AT='paste-li_at-value' node cookie.mjs   # writes storageState.json
# (fallback, often bot-blocked: `node login.mjs`)
node scrape.mjs --list    # step (a): list last-month post URLs
node scrape.mjs           # step (b): download one post's export into out/
```

## What is empirically established vs. unverified

**Established (high confidence, no run needed):**
- Personal profiles have a per-post analytics view with an **Export** button that
  produces the XLSX — that is how `example-data.xlsx` was obtained.
- Playwright + `storageState` cookie auth is a standard, working pattern for
  driving an authenticated LinkedIn session headlessly.
- The recent-activity feed (`/in/<profile>/recent-activity/all/`) lazy-loads
  posts and each carries a stable `urn:li:activity:*` id → enumeration is doable.

**Unverified — needs the human's one run (I have no authenticated session):**
- Exact current **selectors**: the "View analytics" control, the "Export"
  button, and the post-container `data-urn` attribute. These are best-guess
  starting points; expect to fix 1–3 of them on first run.
- Whether Export downloads directly or opens an intermediate dialog.
- A reliable **per-post timestamp** to bound the 1-month window precisely. The
  spike currently bounds by scroll rounds and dedupes URNs; tightening to a real
  date cutoff is a follow-up once the timestamp element is identified.

## Fragility & ban-risk (honest note — the ticket's real deliverable)

- **DOM fragility:** every selector is a maintenance liability. LinkedIn ships UI
  changes without notice; a silent selector break yields empty runs. Any
  production version needs "0 posts / no download" to alert loudly, not pass.
- **Ban risk:** this violates LinkedIn ToS (accepted knowingly per the map).
  Mitigations baked into the spike: real logged-in cookie (not credential
  replay), human-like jittered pacing, headless single session. Cadence is
  **weekly**, low volume — the lowest-footprint shape. Risk is real but bounded;
  worst case is an account restriction on a throwaway/personal profile.
- **Cookie expiry:** `storageState.json` expires (days–weeks). Re-run `login.mjs`
  to refresh. Detecting expiry mid-run (redirect to /login) and alerting is map
  Fog ("cookie-expiry detection + re-auth flow"), deferred until after this gate.

## Verdict

**Feasible.** The approach is standard and the export exists; the only open risk
is selector drift, which the human's first `node scrape.mjs` run resolves. No
fall-back to manual export drops is warranted. Downstream: #25 parses the
captured XLSX into DB rows; #26 schedules the weekly CronJob; resilience
(retry/alert/re-auth) stays in Fog until it earns its own tickets.
