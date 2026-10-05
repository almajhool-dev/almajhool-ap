// Headless Chromium for server-side rendering (PDF pages and generated diagrams).
let factory = null;
/** Tests can inject their own launcher (e.g. a local Chromium). */
export function setBrowserFactory(fn) { factory = fn; }

export async function launchBrowser() {
  if (factory) return factory();
  const chromium = (await import("@sparticuz/chromium")).default;
  const puppeteer = (await import("puppeteer-core")).default;
  return puppeteer.launch({ args: chromium.args, executablePath: await chromium.executablePath(), headless: true });
}

/** A page that may only load inline data (no network, no scripts). */
export async function lockedPage(browser) {
  const page = await browser.newPage();
  await page.setJavaScriptEnabled(false);
  await page.setRequestInterception(true);
  page.on("request", (req) => (req.url().startsWith("data:") || req.url() === "about:blank" ? req.continue() : req.abort()));
  return page;
}

/** One browser shared by every step of a request (diagrams + PDF), launched only if needed. */
export function sharedBrowser() {
  let b = null;
  return {
    get: async () => (b ||= await launchBrowser()),
    close: async () => { if (b) { const x = b; b = null; await x.close().catch(() => {}); } },
  };
}
