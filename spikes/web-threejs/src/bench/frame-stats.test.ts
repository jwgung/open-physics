import { describe, expect, it } from "vitest";
import { FrameStats, formatOpbench, summarizeWindow, type OpbenchLine } from "./frame-stats";

describe("OPBENCH line", () => {
  it("matches the spec key order", () => {
    const line = summarizeWindow(12, "S2", Array.from({ length: 60 }, () => 1000 / 60), 1000);
    expect(formatOpbench(line)).toBe('{"t":12,"scene":"S2","fps":60,"p50ms":16.7,"p95ms":16.7,"p99ms":16.7,"frames":60,"long":0}');
  });

  it("counts frames over 33 ms as long", () => {
    const line = summarizeWindow(1, "S1", [16, 16, 40, 50], 122);
    expect(line.long).toBe(2);
    expect(line.p99ms).toBe(50);
  });

  it("emits once per elapsed second", () => {
    const lines: OpbenchLine[] = [];
    const stats = new FrameStats((line) => lines.push(line));
    for (let i = 0; i <= 180; i += 1) stats.frame(i * 1000 / 60, "S3");
    expect(lines.map((line) => line.t)).toEqual([1, 2, 3]);
    expect(lines[0].frames).toBe(60);
  });
});
