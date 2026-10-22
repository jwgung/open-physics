// Generates and guards the vectors of the orbit lab (Phase 1 Task 4d, web preset "orbit", "조금만
//다르게 쏘면 궤도를 벗어날까?"), consumed by apps/lab3d/tests/orbit_lab_checks.gd.
// The force is the web's: PointGravityField.forceAt (src/physics/fields.ts, G = 1, source mass
// GM = 27 m^3/s^2: 3 m/s circular speed at the 3 m start radius) on a 1 kg planet, a = F / m
// (core.ts accelerationFromForce), in the 3D lab's level plane ((x, z) here as the field's (x, y)).
// The lab steps it at 60 Hz with 8 velocity Verlet substeps; the run ends on the collision radius
// (star 0.9 m + planet 0.3 m = 1.2 m, the web's 38 + 21 px idea) or 12 m from the star.
// Displays: orbit.ts circularOrbitSpeed / circularOrbitPeriod / escapeSpeed, and the web's launch
// prediction OrbitChallenge.analyze (mechanics-challenges.ts: outcome, path, speeds).
// The "web integrator" entry steps the same field the web's way (world.ts explicit Euler, 120 Hz) to
// record why the lab does not copy it (a circular orbit spirals out).
// Runs in the root `npm test`. Regenerate: UPDATE_ORBIT_VECTORS=1 npx vitest run apps/lab3d
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { vectorMismatch } from "./ts-oracle";
import { OrbitChallenge } from "../../../src/app/mechanics-challenges";
import { PointGravityField } from "../../../src/physics/fields";
import type { BodyState } from "../../../src/physics/core";
import { circularOrbitPeriod, circularOrbitSpeed, escapeSpeed } from "../../../src/physics/laws/orbit";

const STEP_HZ = 60;
const DT = 1 / STEP_HZ;
const SUBSTEPS = 8;
const MU = 27;
const MASS = 1;
const CRASH = 1.2;
const FAR = 12;
const vectorsPath = fileURLToPath(new URL("../tests/orbit_lab_vectors.json", import.meta.url));
const playgroundPath = fileURLToPath(new URL("../../../src/app/physics-playground.ts", import.meta.url));
const field = new PointGravityField({ x: 0, y: 0 }, MU, 1);

/** a = F / m of the TS field at (x, z) (core.ts accelerationFromForce scales by 1 / m). */
function acceleration(x: number, z: number): [number, number] {
  const state: BodyState = { position: { x, y: z }, velocity: { x: 0, y: 0 }, acceleration: { x: 0, y: 0 }, mass: MASS };
  const force = field.forceAt(state).vector;
  const inverse = 1 / MASS;
  return [force.x * inverse, force.y * inverse];
}

class Planet {
  x: number;
  z: number;
  vx: number;
  vz: number;
  steps = 0;
  swept = 0;
  firstLap = -1;
  outcome = "";
  private a: [number, number];

  constructor(radius: number, vx: number, vz: number) {
    this.x = radius;
    this.z = 0;
    this.vx = vx;
    this.vz = vz;
    this.a = acceleration(this.x, this.z);
  }

  radius(): number {
    return Math.sqrt(this.x * this.x + this.z * this.z);
  }

  step(): void {
    this.steps += 1;
    if (this.outcome) return;
    const h = DT / SUBSTEPS;
    for (let i = 0; i < SUBSTEPS; i += 1) {
      const before = Math.atan2(-this.z, this.x);
      this.vx += this.a[0] * (h * 0.5);
      this.vz += this.a[1] * (h * 0.5);
      this.x += this.vx * h;
      this.z += this.vz * h;
      this.a = acceleration(this.x, this.z);
      this.vx += this.a[0] * (h * 0.5);
      this.vz += this.a[1] * (h * 0.5);
      let turned = Math.atan2(-this.z, this.x) - before;
      if (turned > Math.PI) turned -= 2 * Math.PI;
      else if (turned < -Math.PI) turned += 2 * Math.PI;
      this.swept += turned;
      // The first full turn (either way round): interpolated within the substep where the swept angle passes 2 pi.
      if (this.firstLap < 0 && Math.abs(this.swept) >= 2 * Math.PI) {
        this.firstLap = (this.steps - 1) * DT + (i + (2 * Math.PI - Math.abs(this.swept - turned)) / Math.abs(turned)) * h;
      }
      const r = this.radius();
      if (r <= CRASH) {
        this.outcome = "crash";
        this.x = this.x / r * CRASH;
        this.z = this.z / r * CRASH;
        this.vx = 0;
        this.vz = 0;
        return;
      }
      if (r >= FAR) {
        this.outcome = "far";
        return;
      }
    }
  }
}

/** One launch from `radius` east of the star at `speed` and `angle` (deg from outwards, counter-clockwise seen from above). */
function orbitCase(name: string, radius: number, speed: number, angle: number, steps: number, every: number) {
  const a = (angle * Math.PI) / 180;
  const vx = speed * Math.cos(a);
  const vz = -speed * Math.sin(a);
  const planet = new Planet(radius, vx, vz);
  const challenge = new OrbitChallenge({ center: { x: 0, y: 0 }, gravitationalParameter: MU, collisionRadius: CRASH });
  const analysis = challenge.analyze({ x: radius, y: 0 }, { x: vx, y: vz });
  const samples: Record<string, number>[] = [];
  const record = () => {
    const r = planet.radius();
    const v = Math.hypot(planet.vx, planet.vz);
    samples.push({
      step: planet.steps,
      x: planet.x,
      z: planet.z,
      vx: planet.vx,
      vz: planet.vz,
      radius: r,
      speed: v,
      circular_speed: circularOrbitSpeed(MU, r, 1),
      escape_speed: escapeSpeed(MU, r, 1),
      circular_period: circularOrbitPeriod(MU, r, 1),
      swept: planet.swept,
    });
  };
  record();
  for (let k = 1; k <= steps; k += 1) {
    planet.step();
    if (k % every === 0) record();
  }
  return {
    name,
    radius,
    speed,
    angle,
    vx,
    vz,
    steps,
    outcome: planet.outcome,
    first_lap: planet.firstLap,
    predicted: {
      outcome: analysis.outcome,
      speed: analysis.speed,
      circular_speed: analysis.circularSpeed,
      escape_speed: analysis.escapeSpeed,
      path_points: analysis.path.length,
      path_last: analysis.path.at(-1),
    },
    samples,
  };
}

/** The web's own stepping (explicit Euler, 120 Hz) of the circular start for 20 s. */
function webIntegrator() {
  let x = 3;
  let z = 0;
  let vx = 0;
  let vz = -3;
  const h = 1 / 120;
  for (let k = 0; k < 2400; k += 1) {
    const [ax, az] = acceleration(x, z);
    x += vx * h;
    z += vz * h;
    vx += ax * h;
    vz += az * h;
  }
  return { radius: 3, seconds: 20, radius_after: Math.hypot(x, z), energy_after: (vx * vx + vz * vz) / 2 - MU / Math.hypot(x, z), energy_start: 9 / 2 - MU / 3 };
}

function buildVectors() {
  return {
    source: "src/physics/fields.ts PointGravityField, core.ts accelerationFromForce, orbit.ts circularOrbitSpeed / circularOrbitPeriod / escapeSpeed, src/app/mechanics-challenges.ts OrbitChallenge",
    tolerance: 1e-9,
    step_hz: STEP_HZ,
    substeps: SUBSTEPS,
    mu: MU,
    mass: MASS,
    crash_radius: CRASH,
    far_radius: FAR,
    cases: [
      // The lab's start: 3 m, 3 m/s counter-clockwise = the circular speed.
      orbitCase("circular", 3, 3, 90, 1200, 6),
      // Slower: an ellipse inside the start radius.
      orbitCase("ellipse", 3, 2.4, 90, 1200, 6),
      // Much slower: it falls onto the star.
      orbitCase("crash", 3, 1, 90, 600, 6),
      // Faster than the escape speed (4.24 m/s): it leaves.
      orbitCase("escape", 3, 4.3, 90, 600, 6),
      // Launched outwards at 60 deg.
      orbitCase("angled", 3, 3.4, 60, 1200, 6),
      // Kepler: the circular orbit at 5 m takes (5 / 3)^1.5 times as long.
      orbitCase("circular 5 m", 5, circularOrbitSpeed(MU, 5, 1), 90, 1200, 6),
      // Clockwise.
      orbitCase("clockwise", 4, 2.5, 270, 1200, 6),
      // 60 s of the start: past the graph and history window.
      orbitCase("long", 3, 3, 90, 3600, 30),
    ],
    web_integrator: webIntegrator(),
  };
}

describe("orbit lab vectors", () => {
  it("follow the web's orbit preset (point gravity field, OrbitChallenge with the collision radius)", () => {
    const source = readFileSync(playgroundPath, "utf8");
    expect(source).toMatch(/new PointGravityField\(center, 1, orbitalSpeed \*\* 2 \* radius\)/);
    expect(source).toMatch(/collisionRadius: 38 \+ 21,/);
  });

  it("match the committed JSON generated from the TS core", () => {
    const vectors = buildVectors();
    if (process.env.UPDATE_ORBIT_VECTORS === "1") {
      writeFileSync(vectorsPath, `${JSON.stringify(vectors, null, 2)}\n`);
    }
    const committed = JSON.parse(readFileSync(vectorsPath, "utf8"));
    expect(vectorMismatch(committed, JSON.parse(JSON.stringify(vectors)))).toBeNull();
  });

  it("orbit as Newton and Kepler say", () => {
    const byName = Object.fromEntries(buildVectors().cases.map((c) => [c.name, c]));
    // Circular: radius kept, one turn in 2 pi sqrt(r^3 / GM); Kepler's third law at 5 m.
    for (const s of byName.circular.samples) expect(Math.abs(s.radius - 3)).toBeLessThan(1e-5);
    expect(Math.abs(byName.circular.first_lap - circularOrbitPeriod(MU, 3, 1))).toBeLessThan(1e-5);
    expect(Math.abs(byName["circular 5 m"].first_lap - circularOrbitPeriod(MU, 5, 1))).toBeLessThan(1e-5);
    // The predictor and the motion agree on the outcome.
    expect(byName.crash.outcome).toBe("crash");
    expect(byName.crash.predicted.outcome).toBe("crash");
    expect(byName.escape.outcome).toBe("far");
    expect(byName.escape.predicted.outcome).toBe("escape");
    for (const name of ["circular", "ellipse", "angled", "circular 5 m", "clockwise", "long"]) {
      expect(byName[name].outcome).toBe("");
      expect(byName[name].predicted.outcome).toBe("orbit");
    }
    // Energy and angular momentum are kept (velocity Verlet).
    for (const run of Object.values(byName)) {
      if (run.outcome) continue;
      const e = run.samples.map((s: Record<string, number>) => s.speed * s.speed / 2 - MU / s.radius);
      const l = run.samples.map((s: Record<string, number>) => s.z * s.vx - s.x * s.vz);
      for (const value of e) expect(Math.abs(value - e[0])).toBeLessThan(2e-4 * Math.abs(e[0]));
      for (const value of l) expect(Math.abs(value - l[0])).toBeLessThan(1e-9 * Math.abs(l[0]));
    }
    expect(byName.clockwise.samples.at(-1).swept).toBeLessThan(-2 * Math.PI);
    expect(byName.clockwise.first_lap).toBeGreaterThan(0);
  });

  it("show why the lab does not copy the web's explicit Euler stepping", () => {
    const web = buildVectors().web_integrator;
    expect(web.radius_after).toBeGreaterThan(3.1);
    expect(web.energy_after).toBeGreaterThan(web.energy_start + 0.1);
  });
});
