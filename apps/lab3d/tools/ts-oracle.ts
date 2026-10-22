// Values the TS formula core has no closed form for, found from the TS functions themselves
// (Phase 1 Task 4a: landing time and apex of free fall / projectiles). Used by the vector generators
// (formula-vectors.test.ts, uniform-labs-vectors.test.ts) so the expected values still come from
// src/physics/laws/mechanics.ts, not from re-typed formulas. The GDScript port (PhysicsLaws
// landing_time / apex_time / apex_rise) uses the closed forms; parity compares the two.
import { constantAccelerationDisplacement, constantAccelerationVelocity } from "../../../src/physics/laws/mechanics";

/** Root of f in [lo, hi] by bisection (f(lo), f(hi) of opposite sign; 200 halvings = float64 resolution). */
function bisect(f: (t: number) => number, lo: number, hi: number): number {
  for (let i = 0; i < 200; i += 1) {
    const mid = 0.5 * (lo + hi);
    if (f(lo) * f(mid) <= 0) hi = mid;
    else lo = mid;
  }
  return 0.5 * (lo + hi);
}

/** Upper end of the search for a landing (s): a root beyond it counts as none (INF). */
const NEVER = 2 ** 40;

/**
 * First t > 0 with constantAccelerationDisplacement(v0, a, t) = -drop (any signs; drop < 0: the
 * level is above the start), from the TS function; t = 0 for a start on the level (drop = 0) that
 * moves below it at once; Infinity when the level is never reached. The displacement is monotone on
 * each side of its turning point (the root of the TS velocity), so each side is bisected for a sign
 * change, the earlier side first.
 */
export function tsLandingTime(v0: number, a: number, drop: number): number {
  if (drop === 0 && (v0 < 0 || (v0 === 0 && a < 0))) return 0;
  const s = (t: number) => constantAccelerationDisplacement({ x: 0, y: v0 }, { x: 0, y: a }, t).y + drop;
  const v = (t: number) => constantAccelerationVelocity({ x: 0, y: v0 }, { x: 0, y: a }, t).y;
  // Turning point: the velocity changes sign at t > 0 (v0 and a of opposite signs).
  let turn: number | undefined;
  if (v0 * a < 0) {
    let hi = 1;
    while (v(hi) * v0 > 0) hi *= 2;
    turn = bisect(v, 0, hi);
  }
  // Monotone sides [lo, hi] (hi undefined: unbounded). A start on the level (drop = 0) moves away
  // from it until the turning point, so only the side after it can hold a root t > 0.
  const sides: [number, number | undefined][] = turn === undefined
    ? (drop === 0 ? [] : [[0, undefined]])
    : (drop === 0 ? [[turn, undefined]] : [[0, turn], [turn, undefined]]);
  for (const [lo, end] of sides) {
    let hi = end ?? Math.max(2 * lo, 1);
    if (end === undefined) while (s(lo) * s(hi) > 0 && hi < NEVER) hi *= 2;
    if (s(lo) * s(hi) <= 0) return bisect(s, lo, hi);
  }
  return Infinity;
}

/** t with constantAccelerationVelocity(v0, a, t) = 0 for a rising body (a < 0), from the TS function. */
export function tsApexTime(v0: number, a: number): number {
  if (!(a < 0)) throw new RangeError(`tsApexTime needs a < 0 (got ${a}): the body never stops rising`);
  const v = (t: number) => constantAccelerationVelocity({ x: 0, y: v0 }, { x: 0, y: a }, t).y;
  let hi = 1;
  while (v(hi) > 0) hi *= 2;
  return bisect(v, 0, hi);
}


/**
 * Deep comparison of generated vectors with the committed JSON: same shape and strings, numbers
 * equal within `tolerance` (relative, absolute near zero). Long trigonometric runs (the orbit's
 * atan2 sweep) differ in the last bits between Node/V8 versions, so they cannot be compared exactly.
 */
export function vectorMismatch(a: unknown, b: unknown, tolerance = 1e-12, path = "$"): string | null {
  if (typeof a === "number" && typeof b === "number") {
    const scale = Math.max(1, Math.abs(a), Math.abs(b));
    return Math.abs(a - b) <= tolerance * scale ? null : `${path}: ${a} vs ${b}`;
  }
  if (Array.isArray(a) && Array.isArray(b)) {
    if (a.length !== b.length) return `${path}: length ${a.length} vs ${b.length}`;
    for (let i = 0; i < a.length; i++) {
      const m = vectorMismatch(a[i], b[i], tolerance, `${path}[${i}]`);
      if (m) return m;
    }
    return null;
  }
  if (a && b && typeof a === "object" && typeof b === "object") {
    const ka = Object.keys(a).sort();
    const kb = Object.keys(b).sort();
    if (ka.join() !== kb.join()) return `${path}: keys ${ka.join()} vs ${kb.join()}`;
    for (const k of ka) {
      const m = vectorMismatch((a as Record<string, unknown>)[k], (b as Record<string, unknown>)[k], tolerance, `${path}.${k}`);
      if (m) return m;
    }
    return null;
  }
  return a === b ? null : `${path}: ${String(a)} vs ${String(b)}`;
}
