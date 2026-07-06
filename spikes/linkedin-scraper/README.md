# LinkedIn scraper feasibility spike (#24)

Cheapest probe of the load-bearing question: can a headless browser,
authenticated with a **saved session cookie**, (a) enumerate every post from the
last month on the profile and (b) trigger + capture each post's analytics XLSX
export (same file as `example-data.xlsx`)?

## Files

- `login.mjs` — one-time in-browser manual login → writes `storageState.json`.
  Use this to capture the **full** browser session (all cookies + localStorage)
  that seeds the GCP `linkedin_li_at` secret. A bare `li_at`-only cookie looks
  like a stolen token and gets the account signed out.
- `scrape.mjs` — enumerate last-month posts, download one post's XLSX export.
- `parse_xlsx.py` — parse downloaded XLSX exports and emit/load Postgres upserts
  into `post_metrics` + `post_demographics`.
- `.gitignore` — keeps `storageState.json` and `out/` out of git (session cookie
  is a credential; never commit it).

## Run it (the human's single verification pass)

```bash
cd spikes/linkedin-scraper
npm i playwright && npx playwright install chromium
# Capture your FULL browser session once (all cookies + localStorage):
node login.mjs           # writes storageState.json
# That storageState.json is the seed for the GCP `linkedin_li_at` secret.
node scrape.mjs --list    # step (a): list last-month post URLs
node scrape.mjs           # step (b): download one post's export into out/
python3 parse_xlsx.py --self-test
python3 parse_xlsx.py out/SinglePostAnalytics_*.xlsx > out/load.sql
python3 parse_xlsx.py out/SinglePostAnalytics_*.xlsx --psql 'kubectl exec -i -n dev deploy/dev-postgres -- psql -U postgres -d linkedin -v ON_ERROR_STOP=1'
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
- **Cookie expiry:** `storageState.json` rotates on a PVC each run (the cron saves
  `context.storageState()` back after a successful visit), so cookies age like a
  real returning browser. When the session finally dies, re-run `login.mjs` and
  re-seed the `linkedin_li_at` secret with the fresh full storageState.

## Verdict

**Feasible.** The approach is standard and the export exists; the only open risk
is selector drift, which the human's first `node scrape.mjs` run resolves. No
fall-back to manual export drops is warranted. Downstream: #25 parses the
captured XLSX into DB rows; #26 schedules the weekly CronJob; resilience
(retry/alert/re-auth) stays in Fog until it earns its own tickets.
