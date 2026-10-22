#!/usr/bin/env node
// Summarizes collect.sh results into the benchmark-spec result table (Markdown).
// Usage: node spikes/bench/summarize.mjs [resultsDir]
import { readdirSync, readFileSync, existsSync } from "node:fs";
import { join } from "node:path";

const dir = process.argv[2] ?? join(import.meta.dirname, "results");
const WARMUP_SECONDS = 30;

const readJsonl = (path) =>
  existsSync(path)
    ? readFileSync(path, "utf8").split("\n").filter((l) => l.startsWith("{")).map((l) => JSON.parse(l))
    : [];
const mean = (xs) => xs.reduce((a, b) => a + b, 0) / xs.length;
const median = (xs) => [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)];
const finiteMax = (xs) => Math.max(...xs.filter(Number.isFinite));
const fmt = (x, d = 1) => (Number.isFinite(x) ? x.toFixed(d) : "—");

const runs = new Map();
for (const file of readdirSync(dir)) {
  // Scene = the benchmark spec's S1-S3 or an app experiment's bench id (FF, PJ: Phase 1 Task 4a).
  const match = file.match(/^(.+)-(S\d|[A-Z]{2,})-(\w+)\.jsonl$/);
  if (!match) continue;
  const [, candidate, scene, run] = match;
  const frames = readJsonl(join(dir, file)).filter((f) => f.scene === scene && f.t >= WARMUP_SECONDS);
  const device = readJsonl(join(dir, file.replace(/\.jsonl$/, ".device.jsonl")));
  const key = `${candidate} ${scene}`;
  if (!runs.has(key)) runs.set(key, { candidate, scene, runs: [], sustained: null });
  const entry = { frames, device };
  if (run === "sustained") runs.get(key).sustained = entry;
  else runs.get(key).runs.push(entry);
}

const coldStart = readJsonl(join(dir, "coldstart.jsonl"));
const coldStartMedian = (candidate) => {
  const times = coldStart.filter((c) => c.candidate === candidate).map((c) => c.totalTimeMs);
  return times.length ? median(times) : NaN;
};

console.log("| 후보 | 장면 | 평균 FPS | 1% low* | p95 ms | 최고 온도 °C | PSS MB | 10분 저하 | 10분 최고 °C / PSS MB | 콜드 스타트 ms |");
console.log("|---|---|---|---|---|---|---|---|---|---|");
for (const { candidate, scene, runs: measured, sustained } of [...runs.values()].sort((a, b) =>
  `${a.candidate}${a.scene}`.localeCompare(`${b.candidate}${b.scene}`),
)) {
  const frames = measured.flatMap((r) => r.frames);
  // Short runs and the 10-minute run are reported separately so one row never mixes conditions.
  const device = measured.flatMap((r) => r.device);
  const fps = frames.map((f) => f.fps);
  // Per-second p99 frame times approximate the 1% low; see benchmark-spec section 6.
  const onePercentLow = frames.length ? 1000 / mean(frames.map((f) => f.p99ms)) : NaN;
  let drop = "—";
  let sustainedDevice = "—";
  if (sustained && sustained.frames.length > 120) {
    const s = sustained.frames;
    const first = mean(s.slice(0, 60).map((f) => f.fps));
    const last = mean(s.slice(-60).map((f) => f.fps));
    drop = `${fmt(((first - last) / first) * 100)}%`;
    sustainedDevice = `${fmt(finiteMax(sustained.device.map((d) => d.batteryC)))} / ${fmt(finiteMax(sustained.device.map((d) => d.pssMB)), 0)}`;
  }
  console.log(
    `| ${candidate} | ${scene} | ${fmt(mean(fps))} | ${fmt(onePercentLow)} | ${fmt(median(frames.map((f) => f.p95ms)))} | ${fmt(finiteMax(device.map((d) => d.batteryC)))} | ${fmt(finiteMax(device.map((d) => d.pssMB)), 0)} | ${drop} | ${sustainedDevice} | ${fmt(coldStartMedian(candidate), 0)} |`,
  );
}
console.log("\n\\* 1% low는 초당 p99 프레임 시간(초당 30~60프레임에서는 사실상 그 초의 최악 프레임) 평균의 역수로 근사해, 전체 프레임의 하위 1%보다 보수적이다.");
