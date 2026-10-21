/** Per-second frame statistics in the OPBENCH line format (benchmark-spec §6). */

export interface OpbenchLine {
  t: number;
  scene: string;
  fps: number;
  p50ms: number;
  p95ms: number;
  p99ms: number;
  frames: number;
  long: number;
}

export const LONG_FRAME_MS = 33;

const round1 = (value: number): number => Math.round(value * 10) / 10;

/** Nearest-rank percentile of an ascending-sorted array. */
export const percentile = (sorted: readonly number[], p: number): number => {
  if (sorted.length === 0) return 0;
  const rank = Math.ceil(p / 100 * sorted.length);
  return sorted[Math.min(sorted.length - 1, Math.max(0, rank - 1))];
};

export function summarizeWindow(
  t: number,
  scene: string,
  frameTimesMs: readonly number[],
  windowMs: number,
): OpbenchLine {
  const sorted = [...frameTimesMs].sort((a, b) => a - b);
  return {
    t,
    scene,
    fps: round1(windowMs > 0 ? frameTimesMs.length * 1000 / windowMs : 0),
    p50ms: round1(percentile(sorted, 50)),
    p95ms: round1(percentile(sorted, 95)),
    p99ms: round1(percentile(sorted, 99)),
    frames: frameTimesMs.length,
    long: frameTimesMs.filter((ms) => ms > LONG_FRAME_MS).length,
  };
}

/** Exact key order of the spec example. */
export const formatOpbench = (line: OpbenchLine): string => JSON.stringify({
  t: line.t,
  scene: line.scene,
  fps: line.fps,
  p50ms: line.p50ms,
  p95ms: line.p95ms,
  p99ms: line.p99ms,
  frames: line.frames,
  long: line.long,
});

/** Collects requestAnimationFrame intervals and flushes one line per elapsed second. */
export class FrameStats {
  private lastFrame: number | null = null;
  private windowStart: number | null = null;
  private measureStart: number | null = null;
  private frameTimes: number[] = [];
  latest: OpbenchLine | null = null;

  constructor(private readonly emit: (line: OpbenchLine) => void) {}

  /** Restarts measurement (scene switch). */
  reset(): void {
    this.lastFrame = null;
    this.windowStart = null;
    this.measureStart = null;
    this.frameTimes = [];
  }

  frame(now: number, scene: string): void {
    if (this.lastFrame === null || this.windowStart === null || this.measureStart === null) {
      this.lastFrame = now;
      this.windowStart = now;
      this.measureStart = now;
      return;
    }
    this.frameTimes.push(now - this.lastFrame);
    this.lastFrame = now;
    const windowMs = now - this.windowStart;
    if (windowMs >= 1000) {
      const t = Math.round((now - this.measureStart) / 1000);
      this.latest = summarizeWindow(t, scene, this.frameTimes, windowMs);
      this.emit(this.latest);
      this.frameTimes = [];
      this.windowStart = now;
    }
  }
}
