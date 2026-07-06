// Build storageState.json from the FULL cookie set exported out of your REAL
// browser — sidesteps LinkedIn's "this browser may not be secure" bot-detection,
// which fires on an automated login (login.mjs) but never on the browser you're
// already signed into.
//
// Get the cookies: log into linkedin.com in your normal browser, install the
// "Cookie-Editor" extension (or any exporter), open it on linkedin.com, and
// Export → JSON. Save that as cookies.json next to this file.
//
// Run:  node from-cookies.mjs   # reads cookies.json → writes storageState.json
//
// ponytail: this is the real full jar (li_at, bcookie, bscookie, li_rm, lidc,
// JSESSIONID...), NOT a fabricated single-cookie session — that fabrication was
// the sign-out bug. localStorage is omitted; cookies carry LinkedIn's session +
// device recognition. Add origins/localStorage only if a run proves it's needed.
import { readFileSync, writeFileSync } from "node:fs";

// Cookie-Editor's sameSite strings → Playwright's enum.
const sameSite = (v) => {
  const s = String(v || "").toLowerCase();
  if (s === "strict") return "Strict";
  if (s === "lax") return "Lax";
  return "None"; // no_restriction / unspecified / none
};

if (process.argv.includes("--self-test")) {
  const { strictEqual } = await import("node:assert");
  strictEqual(sameSite("no_restriction"), "None");
  strictEqual(sameSite("Lax"), "Lax");
  strictEqual(sameSite("strict"), "Strict");
  strictEqual(sameSite(undefined), "None");
  console.log("self-test ok");
  process.exit(0);
}

const src = new URL("./cookies.json", import.meta.url).pathname;
const raw = JSON.parse(readFileSync(src, "utf8"));
const list = Array.isArray(raw) ? raw : raw.cookies;
if (!Array.isArray(list)) {
  console.error("cookies.json must be a Cookie-Editor JSON export (array of cookies)");
  process.exit(1);
}

const cookies = list
  .filter((c) => c.name && c.value)
  .map((c) => ({
    name: c.name,
    value: c.value,
    domain: c.domain?.startsWith(".") ? c.domain : `.${(c.domain || "linkedin.com").replace(/^\./, "")}`,
    path: c.path || "/",
    expires: Math.floor(c.expirationDate ?? c.expires ?? Date.now() / 1000 + 60 * 60 * 24 * 30),
    httpOnly: !!c.httpOnly,
    secure: c.secure !== false,
    sameSite: sameSite(c.sameSite),
  }));

if (!cookies.some((c) => c.name === "li_at")) {
  console.error("no li_at cookie found — export while logged in to linkedin.com");
  process.exit(1);
}

writeFileSync(
  new URL("./storageState.json", import.meta.url).pathname,
  JSON.stringify({ cookies, origins: [] }, null, 2)
);
console.log(`wrote storageState.json (${cookies.length} cookie(s))`);
