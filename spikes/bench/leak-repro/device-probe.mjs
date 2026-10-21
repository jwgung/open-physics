// Device leak probe: drives the Capacitor WebView over CDP and samples dumpsys meminfo.
// Needs a web spike build with android.webContentsDebuggingEnabled and, for raw:/blank, raw-webgpu.html
// copied to spikes/web-threejs/public/debug-leak-raw.html (blank: debug-leak-blank.html). See README.md.
// Usage: node device-probe.mjs <query> <seconds> <label>   e.g. "scene=S2&backend=webgl" 120 s2-webgl
import { chromium } from "playwright-core";
import { execSync } from "node:child_process";
import { readFileSync } from "node:fs";

const PKG = "dev.openphysics.spike.web";
const [query, seconds = "120", label = "run"] = process.argv.slice(2);
const sh = (cmd) => execSync(cmd, { encoding: "utf8" });

sh(`adb shell am force-stop ${PKG}`);
sh(`adb shell input keyevent KEYCODE_WAKEUP`);
sh(`adb shell am start -W -n ${PKG}/.MainActivity`);
await new Promise((r) => setTimeout(r, 4000));
const pid = sh(`adb shell pidof ${PKG}`).trim();
sh(`adb forward --remove-all`);
sh(`adb forward tcp:9333 localabstract:webview_devtools_remote_${pid}`);

const browser = await chromium.connectOverCDP("http://localhost:9333");
const page = browser.contexts()[0].pages()[0];
const base = page.url().split("?")[0];
if (query.startsWith("raw:")) {
  await page.goto(`${base.replace(/[^/]*$/, "")}debug-leak-raw.html#mode=${query.slice(4)}`);
} else if (query === "blank") {
  await page.goto(`${base.replace(/[^/]*$/, "")}debug-leak-blank.html`);
} else {
  await page.goto(`${base}?${query}`);
}
await page.waitForTimeout(8000);
const cdp = await page.context().newCDPSession(page);
await cdp.send("Performance.enable");

const FIELDS = ["Native Heap", "Dalvik Heap", "Gfx dev", "EGL mtrack", "GL mtrack", "Unknown", "Other dev", "TOTAL PSS"];
function meminfo() {
  const out = sh(`adb shell dumpsys meminfo ${PKG}`);
  const result = {};
  for (const f of FIELDS) {
    const line = out.split("\n").find((l) => l.trim().startsWith(f));
    if (!line) continue;
    const n = line.trim().slice(f.length).trim().split(/\s+/)[0].replace(":", "");
    result[f.replace(/\s/g, "")] = Math.round(Number(n || line.match(/(\d+)/)[1]) / 1024);
  }
  return result;
}

const start = Date.now();
const samples = [];
while ((Date.now() - start) / 1000 < Number(seconds)) {
  const { metrics } = await cdp.send("Performance.getMetrics");
  const m = Object.fromEntries(metrics.map((x) => [x.name, x.value]));
  const overlay = await page.evaluate(() => document.body.innerText.split("\n").find((l) => l.includes("fps")) ?? "");
  const s = { t: Math.round((Date.now() - start) / 1000), jsHeapMB: Math.round(m.JSHeapUsedSize / 1048576), overlay, ...meminfo() };
  samples.push(s);
  console.log(JSON.stringify(s));
  await page.waitForTimeout(10000);
}
const a = samples[0];
const b = samples.at(-1);
const dt = (b.t - a.t) / 60;
const rate = (k) => `${k} ${a[k]}->${b[k]} (${((b[k] - a[k]) / dt).toFixed(0)} MB/min)`;
console.log(`RESULT ${label}: ${["TOTALPSS", "NativeHeap", "GLmtrack", "EGLmtrack", "Gfxdev", "Unknown", "jsHeapMB"].filter((k) => k in a).map(rate).join(", ")}`);
await browser.close();
