// Build storageState.json from a session cookie you copied out of your REAL
// browser — sidesteps LinkedIn's login-page bot-detection ("browser may not be
// secure"), which fires on Playwright's automated login but not on scraping
// with an already-valid session.
//
// Get the cookie: log into linkedin.com in your normal browser, open DevTools →
// Application → Cookies → https://www.linkedin.com → copy the `li_at` value.
//
// Run:  LI_AT='paste-value' node cookie.mjs
//
// ponytail: li_at alone is the session bearer; JSESSIONID is optional and only
// needed if a request 403s on a CSRF check — add it then, not before.
import { writeFileSync } from "node:fs";

const li_at = process.env.LI_AT?.trim();
if (!li_at) {
  console.error("set LI_AT to your li_at cookie value, e.g. LI_AT='AQED...' node cookie.mjs");
  process.exit(1);
}

const cookie = (name, value) => ({
  name, value, domain: ".linkedin.com", path: "/",
  httpOnly: true, secure: true, sameSite: "None",
  expires: Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 30,
});

const cookies = [cookie("li_at", li_at)];
if (process.env.JSESSIONID) cookies.push(cookie("JSESSIONID", process.env.JSESSIONID.trim()));

writeFileSync(
  new URL("./storageState.json", import.meta.url),
  JSON.stringify({ cookies, origins: [] }, null, 2)
);
console.log(`wrote storageState.json (${cookies.length} cookie(s))`);
