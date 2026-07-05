// LinkedIn scraper feasibility spike (#24).
// Cheapest possible probe: Playwright + a saved session cookie (storageState).
// (a) enumerate last-month post URLs from the profile's recent activity,
// (b) open one post's analytics and capture its XLSX export.
//
// Run:  node scrape.mjs           # enumerate + download one export
//       node scrape.mjs --list    # enumerate only
// Prereqs (see README.md): `npm i playwright`, then `node login.mjs` once to
// create storageState.json from a manual login.
//
// ponytail: single-file spike, no retries/backoff/queueing. That resilience is
// map Fog ("Scraper resilience") and only earns code once feasibility is proven.
// Selectors below are UNVERIFIED starting points — LinkedIn's DOM shifts; the
// human's first run locks the real ones in. Treat every selector as suspect.

import { chromium } from "playwright";
import { mkdirSync } from "node:fs";

const PROFILE = process.env.LI_PROFILE ?? "daniel-vieites";
const OUT = new URL("./out/", import.meta.url).pathname;
const LIST_ONLY = process.argv.includes("--list");
const MONTH_MS = 30 * 24 * 60 * 60 * 1000;

const jitter = (min, max) => min + Math.random() * (max - min);
const pause = (min, max) => new Promise((r) => setTimeout(r, jitter(min, max)));

// LinkedIn activity URNs are snowflake ids: the top 41 bits are epoch-ms of
// post creation, so we can date-filter without scraping a DOM timestamp.
const urnTime = (urn) => Number(BigInt((urn.match(/\d+/) || [0])[0]) >> 22n);

async function enumeratePosts(page) {
  // Recent-activity feed of the target profile.
  await page.goto(
    `https://www.linkedin.com/in/${PROFILE}/recent-activity/all/`,
    { waitUntil: "domcontentloaded" }
  );
  await pause(2000, 4000);

  // Auth check: an invalid/expired cookie bounces to a login/authwall.
  const url = page.url();
  if (/\/(login|authwall|checkpoint)/.test(url)) {
    throw new Error(`not authenticated — landed on ${url}. Refresh li_at via cookie.mjs.`);
  }

  // Candidate selectors for a post container (LinkedIn's DOM drifts — try several
  // and use whichever matches). Report every count so a zero result is debuggable.
  const candidates = [
    "div[data-urn^='urn:li:activity:']",
    "[data-urn*='urn:li:activity:']",
    "div.feed-shared-update-v2[data-urn]",
    "div.fie-impression-container[data-urn]",
    "[data-id^='urn:li:activity:']",
  ];

  const urns = new Set();
  for (let round = 0; round < 12; round++) {
    for (const sel of candidates) {
      const found = await page.$$eval(sel, (els) =>
        els.map((e) => e.getAttribute("data-urn") || e.getAttribute("data-id")).filter(Boolean)
      ).catch(() => []);
      found.forEach((u) => urns.add(u));
    }
    await page.mouse.wheel(0, 3000);
    await pause(1500, 3500); // human-ish pacing; slow is safer than banned
  }

  if (urns.size === 0) {
    // First-run selector-locking aid: dump what actually loaded so we can read
    // the real container class/attribute and fix `candidates` above.
    const counts = {};
    for (const sel of candidates) counts[sel] = await page.$$(sel).then((n) => n.length).catch(() => "err");
    console.error("selector counts:", counts);
    await page.screenshot({ path: `${OUT}debug.png`, fullPage: false }).catch(() => {});
    const { writeFileSync } = await import("node:fs");
    writeFileSync(`${OUT}debug.html`, await page.content());
    console.error(`0 posts. url=${page.url()} — wrote ${OUT}debug.png + debug.html; inspect for the real post-container attribute.`);
  }

  const cutoff = Date.now() - MONTH_MS;
  return [...urns]
    .map((u) => (u.match(/urn:li:activity:\d+/) || [])[0])
    .filter(Boolean)
    .filter((urn) => urnTime(urn) >= cutoff) // last-month window, from the URN id
    .sort((a, b) => urnTime(b) - urnTime(a)) // newest first
    .map((urn) => `https://www.linkedin.com/feed/update/${urn}/`);
}

async function downloadExport(page, postUrl) {
  const urn = (postUrl.match(/urn:li:activity:\d+/) || [])[0];
  if (!urn) throw new Error(`no activity urn in post URL: ${postUrl}`);

  // The debug dump showed LinkedIn's real owner analytics URL; skip the flaky
  // feed-page selector and go straight there.
  await page.goto(`https://www.linkedin.com/analytics/post-summary/${urn}/`, {
    waitUntil: "domcontentloaded",
  });
  await pause(2000, 4000);

  // Export opens a confirmation modal; the actual XLSX starts after Confirm.
  const exportBtn = [
    () => page.getByRole("link", { name: /^export$/i }).first(),
    () => page.getByRole("button", { name: /^export$/i }).first(),
    () => page.locator("a:has-text('Export')").first(),
    () => page.locator("button:has-text('Export')").first(),
  ];
  if (!(await clickFirst(page, exportBtn, "export-button"))) return null;
  await pause(1000, 2000);

  const confirmBtn = [
    () => page.getByRole("button", { name: /^confirm$/i }).first(),
    () => page.locator("button:has-text('Confirm')").first(),
  ];
  const download = await Promise.all([
    page.waitForEvent("download", { timeout: 15000 }),
    clickFirst(page, confirmBtn, "export-confirm"),
  ]).then(([d]) => d).catch(async (e) => {
    await dump(page, "export");
    console.error(`export failed: ${e.message} — wrote ${OUT}debug-export.html/png`);
    return null;
  });
  if (!download) return null;
  const dest = `${OUT}${download.suggestedFilename()}`;
  await download.saveAs(dest);
  return dest;
}

// Click the first candidate that actually clicks; dump the page if none work.
async function clickFirst(page, candidates, label) {
  for (const make of candidates) {
    const loc = make();
    if (!(await loc.count().then((n) => n > 0).catch(() => false))) continue;
    try {
      await loc.click({ timeout: 5000 });
      return true;
    } catch {}
  }
  await dump(page, label);
  console.error(`no '${label}' element clicked — wrote ${OUT}debug-${label}.html/png`);
  return false;
}

async function dump(page, label) {
  const { writeFileSync } = await import("node:fs");
  try { await page.screenshot({ path: `${OUT}debug-${label}.png` }); } catch {}
  try { writeFileSync(`${OUT}debug-${label}.html`, await page.content()); } catch {}
  // Surface any analytics links so we can read the real URL/selector to lock in.
  const links = await page
    .$$eval("a", (as) =>
      as
        .filter((a) => /analytics/i.test(a.href) || /analytics/i.test(a.textContent || ""))
        .map((a) => `${(a.textContent || "").trim().slice(0, 40)} -> ${a.href}`)
    )
    .catch(() => []);
  if (links.length) console.error("analytics links:", links);
  const controls = await page
    .$$eval("a,button,[role='button']", (els) =>
      els
        .filter((e) => /export|download/i.test(`${e.textContent || ""} ${e.getAttribute("aria-label") || ""} ${e.href || ""}`))
        .map((e) => `${e.tagName} ${(e.textContent || e.getAttribute("aria-label") || "").trim().slice(0, 60)} -> ${e.href || ""}`)
    )
    .catch(() => []);
  if (controls.length) console.error("export controls:", controls);
}

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({
  storageState: new URL("./storageState.json", import.meta.url).pathname,
  acceptDownloads: true,
});
try {
  mkdirSync(OUT, { recursive: true });
  const page = await ctx.newPage();
  const posts = await enumeratePosts(page);
  console.log(`enumerated ${posts.length} post(s):`);
  posts.forEach((p) => console.log("  " + p));

  if (!LIST_ONLY) {
    for (const post of posts) {
      const file = await downloadExport(page, post);
      console.log(`${post} -> ${file}`);
    }
  }
} finally {
  await ctx.close();
  await browser.close();
}
