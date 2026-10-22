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

/** First t > 0 with constantAccelerationDisplacement(v0, a, t) = -drop (a < 0), from the TS function. */
export function tsLandingTime(v0: number, a: number, drop: number): number {
  if (!(a < 0)) throw new RangeError(`tsLandingTime needs a < 0 (got ${a}): the body never comes down`);
  const s = (t: number) => constantAccelerationDisplacement({ x: 0, y: v0 }, { x: 0, y: a }, t).y + drop;
  let hi = 1;
  while (s(hi) > 0) hi *= 2;
  const apex = v0 > 0 ? tsApexTime(v0, a) : 0;
  return bisect(s, apex, hi);
}

/** t with constantAccelerationVelocity(v0, a, t) = 0 for a rising body (a < 0), from the TS function. */
export function tsApexTime(v0: number, a: number): number {
  if (!(a < 0)) throw new RangeError(`tsApexTime needs a < 0 (got ${a}): the body never stops rising`);
  const v = (t: number) => constantAccelerationVelocity({ x: 0, y: v0 }, { x: 0, y: a }, t).y;
  let hi = 1;
  while (v(hi) > 0) hi *= 2;
  return bisect(v, 0, hi);
}

