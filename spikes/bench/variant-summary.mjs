#!/usr/bin/env node
// One Markdown table row per godot-variant.sh capture: fps, p95, GPU time, GPU clock, GPU Mcycles,
// physics / render CPU time, draw calls, primitives.
// Usage: node spikes/bench/variant-summary.mjs <log> <name> [clk]   (header: --header)
import { readFileSync, existsSync } from "node:fs";

if (process.argv[2] === "--header") {
  console.log("| 변형 | FPS | p95 ms | GPU ms | GPU MHz | GPU Mcycle | 물리 ms | 렌더 CPU ms | 드로우콜 | 프리미티브 |");
  console.log("|---|---|---|---|---|---|---|---|---|---|");
  process.exit(0);
}
const [file, name, clk] = process.argv.slice(2);
const lines = readFileSync(file, "utf8").split("\n").filter((l) => l.startsWith("{")).flatMap((l) => {
  try {
    return [JSON.parse(l)];
  } catch {
    return []; // last line cut off when `timeout` stops logcat
  }
});
const frames = lines.filter((l) => "fps" in l);
const perf = lines.filter((l) => !("fps" in l));
const mean = (xs, key) => {
  const values = xs.map((x) => x[key]).filter((x) => typeof x === "number"); // null: no GPU time in that window
  return values.length ? values.reduce((a, x) => a + x, 0) / values.length : NaN;
};
const fmt = (x, d = 1) => (Number.isFinite(x) ? x.toFixed(d) : "—");
const clock = clk && existsSync(clk)
  ? readFileSync(clk, "utf8").trim().split("\n").map((l) => l.trim().split(/\s+/).map(Number)).filter((c) => c.length === 2 && c[0] > 0) // "<kHz> <°C>"; a failed clock read leaves one field
  : [];
const mhz = clock.length ? clock.reduce((a, c) => a + c[0], 0) / clock.length / 1000 : NaN;
const gpu = mean(perf, "gpu_ms");
console.log(
  `| ${name} | ${fmt(mean(frames, "fps"))} | ${fmt(mean(frames, "p95ms"))} | ${fmt(gpu)} | ${fmt(mhz, 0)} | ${fmt((gpu * mhz) / 1000)} | ${fmt(mean(perf, "physics_ms"))} | ${fmt(mean(perf, "render_cpu_ms"))} | ${fmt(mean(perf, "draws"), 0)} | ${Number.isFinite(mean(perf, "prims")) ? `${fmt(mean(perf, "prims") / 1000, 0)}k` : "—"} |`,
);
