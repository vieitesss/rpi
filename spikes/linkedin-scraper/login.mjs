// One-time helper: open a real browser, log in by hand, save the session.
// ponytail: manual login beats scripting credentials — no password handling,
// no MFA automation, and it mirrors exactly what the CronJob cookie will be.
// Re-run whenever the cookie expires (map Fog: "cookie-expiry detection").
import { chromium } from "playwright";

const ctx = await chromium.launchPersistentContext("", { headless: false });
const page = await ctx.newPage();
await page.goto("https://www.linkedin.com/login");
console.log("Log in manually, complete any MFA, then press Enter here...");
await new Promise((r) => process.stdin.once("data", r));
await ctx.storageState({
  path: new URL("./storageState.json", import.meta.url).pathname,
});
console.log("saved storageState.json");
await ctx.close();
process.exit(0);
