// Leak probe: opens the web spike in headless Chromium and samples memory over time.
// Usage: node probe.mjs <url> <seconds> [label]
import { chromium } from "playwright-core";
import { execSync } from "node:child_process";
import { homedir } from "node:os";

const [url, seconds = "60", label = "run"] = process.argv.slice(2);
const browser = await chromium.launch({
  executablePath: `${homedir()}/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome`,
  args: ["--enable-unsafe-webgpu", "--use-angle=swiftshader", "--enable-precise-memory-info", "--js-flags=--expose-gc"],
});
const page = await browser.newPage({ viewport: { width: 400, height: 700 } });
const cdp = await page.context().newCDPSession(page);
await cdp.send("Performance.enable");
await page.goto(url);
await page.waitForTimeout(5000);

const browserPid = browser.process?.()?.pid;
function rssByType() {
  // Sum RSS (MB) of chromium child processes grouped by --type.
  const out = execSync("ps -eo pid,ppid,rss,args --no-headers").toString().split("\n");
  const groups = {};
  for (const line of out) {
    if (!line.includes("chromium-1243")) continue;
    const m = line.match(/--type=([\w-]+)/);
    const type = m ? m[1] : "browser";
    const rss = Number(line.trim().split(/\s+/)[2]) / 1024;
    groups[type] = (groups[type] ?? 0) + rss;
  }
  return Object.fromEntries(Object.entries(groups).map(([k, v]) => [k, Math.round(v)]));
}

const start = Date.now();
const samples = [];
while ((Date.now() - start) / 1000 < Number(seconds)) {
  await page.evaluate(() => (globalThis.gc ? gc() : 0));
  const { metrics } = await cdp.send("Performance.getMetrics");
  const m = Object.fromEntries(metrics.map((x) => [x.name, x.value]));
  const extra = await page.evaluate(() => ({ overlay: document.querySelector("[data-stats], .stats")?.textContent ?? document.body.innerText.split("\n").find((l) => l.includes("fps")) }));
  const sample = {
    t: Math.round((Date.now() - start) / 1000),
    jsHeapMB: Math.round(m.JSHeapUsedSize / 1048576),
    ...extra,
    rss: rssByType(),
  };
  samples.push(sample);
  console.log(JSON.stringify(sample));
  await page.waitForTimeout(5000);
}
const first = samples[1] ?? samples[0];
const last = samples.at(-1);
const total = (s) => Object.values(s.rss).reduce((a, b) => a + b, 0);
console.log(`RESULT ${label}: jsHeap ${first.jsHeapMB}->${last.jsHeapMB} MB, rssTotal ${total(first)}->${total(last)} MB over ${last.t - first.t}s`);
await browser.close();
