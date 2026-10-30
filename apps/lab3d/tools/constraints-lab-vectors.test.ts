// Generates and guards the vectors of the string / rod pendulum lab (Phase 1 Task 4e, web preset
// "constraints", "줄과 막대는 움직임을 어떻게 제한할까?"), consumed by apps/lab3d/tests/constraints_lab_checks.gd.
// The law is the web's: PendulumModel (src/physics/mechanics-scenes.ts), angular acceleration
// alpha = -(g / L) sin(angle) - damping * omega, a bob at anchor + L (sin angle, cos angle) (fixed length).
// The web preset hangs a rope bob (0.62 rad, damping 0.06 /s) and a rod bob (-0.5 rad, 0.03 /s) of
// the same length. The lab steps that equation (the acceleration is read from the TS PendulumModel
// itself) with classic RK4, SUBSTEPS per 60 Hz fixed step, and measures the period from the model's
// zero crossings. Tension: m g cos(angle) + centripetalForce(m, tangentialSpeed(L, omega), L)
// (mechanics.ts). The web steps the model with semi-implicit Euler at 60 Hz; the "web integrator"
// entry records how far that is from the law's motion (why the lab does not copy it).
// Runs in the root `npm test`. Regenerate: UPDATE_CONSTRAINTS_VECTORS=1 npx vitest run apps/lab3d
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { PendulumModel } from "../../../src/physics/mechanics-scenes";
import { centripetalForce, tangentialSpeed } from "../../../src/physics/laws/mechanics";
import { pendulumPeriod } from "../../../src/physics/laws/oscillation";

const STEP_HZ = 60;
const DT = 1 / STEP_HZ;
const SUBSTEPS = 4;
const BOB_MASS = 1; // physics-playground constraints preset: both bobs 1 kg
const WEB_ROPE = { angle: 0.62, damping: 0.06 };
const WEB_ROD = { angle: -0.5, damping: 0.03 };
const vectorsPath = fileURLToPath(new URL("../tests/constraints_lab_vectors.json", import.meta.url));

/** alpha of the TS PendulumModel at (angle, omega): one step of 0 s computes it without moving. */
function tsAcceleration(length: number, damping: number, g: number, angle: number, omega: number): number {
  const model = new PendulumModel({ x: 0, y: 0 }, length, angle, damping);
  model.angularVelocity = omega;
  model.step(0, g);
  return model.angularAcceleration;
}

interface Pendulum { angle: number; omega: number }

/** One RK4 step of h seconds of the TS PendulumModel's equation (the GDScript model does the same operations). */
function rk4(p: Pendulum, h: number, length: number, damping: number, g: number): void {
  const acc = (a: number, w: number) => tsAcceleration(length, damping, g, a, w);
  const a = p.angle;
  const w = p.omega;
  const k1a = w;
  const k1w = acc(a, w);
  const k2a = w + 0.5 * h * k1w;
  const k2w = acc(a + 0.5 * h * k1a, w + 0.5 * h * k1w);
  const k3a = w + 0.5 * h * k2w;
  const k3w = acc(a + 0.5 * h * k2a, w + 0.5 * h * k2w);
  const k4a = w + h * k3w;
  const k4w = acc(a + h * k3a, w + h * k3w);
  p.angle = a + (h / 6) * (k1a + 2 * k2a + 2 * k3a + k4a);
  p.omega = w + (h / 6) * (k1w + 2 * k2w + 2 * k3w + k4w);
}

/** The lab's pendulum: RK4 substeps per fixed step and the period from same-direction zero crossings. */
class LabPendulum {
  state: Pendulum;
  steps = 0;
  period = 0;
  private lastUp = -1;
  private lastDown = -1;

  constructor(readonly length: number, readonly damping: number, readonly g: number, angle: number) {
    this.state = { angle, omega: 0 };
  }

  step(): void {
    const before = this.state.angle;
    for (let i = 0; i < SUBSTEPS; i += 1) rk4(this.state, DT / SUBSTEPS, this.length, this.damping, this.g);
    this.steps += 1;
    const after = this.state.angle;
    const up = before < 0 && after >= 0;
    const down = before > 0 && after <= 0;
    if (up || down) {
      const t = (this.steps - 1 + before / (before - after)) * DT;
      const last = up ? this.lastUp : this.lastDown;
      if (last >= 0) this.period = t - last;
      if (up) this.lastUp = t;
      else this.lastDown = t;
    }
  }

  sample() {
    const { angle, omega } = this.state;
    const pose = new PendulumModel({ x: 0, y: 0 }, this.length, angle, this.damping).pose();
    return {
      angle,
      omega,
      x: pose.position.x,
      y: pose.position.y,
      tension: BOB_MASS * this.g * Math.cos(angle) + centripetalForce(BOB_MASS, tangentialSpeed(this.length, omega), this.length),
      period: this.period,
    };
  }
}

/** Period of an undamped pendulum released from rest at theta0: 2 pi sqrt(L / g) / AGM(1, cos(theta0 / 2)). */
function largeAnglePeriod(length: number, g: number, theta0: number): number {
  let a = 1;
  let b = Math.cos(theta0 / 2);
  for (let i = 0; i < 40; i += 1) [a, b] = [(a + b) / 2, Math.sqrt(a * b)];
  return pendulumPeriod(length, g) / a;
}

interface Side { angle: number; damping: number }

function pendulumCase(name: string, g: number, length: number, rope: Side, rod: Side, steps: number, every: number) {
  const pendulums = { rope: new LabPendulum(length, rope.damping, g, rope.angle), rod: new LabPendulum(length, rod.damping, g, rod.angle) };
  const samples: Record<string, unknown>[] = [];
  for (let k = 0; k <= steps; k += 1) {
    if (k % every === 0) samples.push({ step: k, rope: pendulums.rope.sample(), rod: pendulums.rod.sample() });
    if (k < steps) {
      pendulums.rope.step();
      pendulums.rod.step();
    }
  }
  const largeAngle = (side: Side) => (side.damping === 0 && g > 0 ? largeAnglePeriod(length, g, Math.abs(side.angle)) : null);
  return {
    name,
    g,
    length,
    rope,
    rod,
    steps,
    small_angle_period: g > 0 ? pendulumPeriod(length, g) : null,
    large_angle_period: { rope: largeAngle(rope), rod: largeAngle(rod) },
    samples,
  };
}

/** The angle of an RK4 run with `sub` substeps per fixed step after each fixed step. */
function rk4Run(length: number, damping: number, g: number, angle: number, steps: number, sub: number): number[] {
  const p = { angle, omega: 0 };
  const out: number[] = [];
  for (let k = 0; k < steps; k += 1) {
    for (let i = 0; i < sub; i += 1) rk4(p, DT / sub, length, damping, g);
    out.push(p.angle);
  }
  return out;
}

/** The web's own stepping (PendulumModel.step, semi-implicit Euler, 60 Hz) against the law's motion. */
function webIntegrator(length: number, side: Side, g = 9.81) {
  const model = new PendulumModel({ x: 0, y: 0 }, length, side.angle, side.damping);
  const reference = rk4Run(length, side.damping, g, side.angle, 1200, 100);
  let worst = 0;
  for (let k = 0; k < 1200; k += 1) {
    model.step(DT, g);
    worst = Math.max(worst, Math.abs(model.angle - reference[k]) * length);
  }
  return { length, ...side, max_bob_error_20s: worst };
}

const deg = (d: number) => (d * Math.PI) / 180;

function buildVectors() {
  return {
    source: "src/physics/mechanics-scenes.ts PendulumModel (step's angular acceleration, pose), oscillation.ts pendulumPeriod, mechanics.ts centripetalForce / tangentialSpeed",
    tolerance: 1e-9,
    step_hz: STEP_HZ,
    substeps: SUBSTEPS,
    bob_mass: BOB_MASS,
    web: { rope: WEB_ROPE, rod: WEB_ROD },
    cases: [
      // The lab's start: the web's two pendulums (angles and damping), 2 m, earth.
      pendulumCase("start", 9.81, 2, WEB_ROPE, WEB_ROD, 1200, 6),
      pendulumCase("no damping", 9.81, 2, { angle: 0.62, damping: 0 }, { angle: -0.5, damping: 0 }, 1200, 12),
      pendulumCase("moon", 1.62, 2, WEB_ROPE, WEB_ROD, 1200, 12),
      pendulumCase("jupiter short", 24.79, 1, WEB_ROPE, WEB_ROD, 1200, 12),
      // Small swings: the period is the small-angle 2 pi sqrt(L / g).
      pendulumCase("small", 9.81, 1.5, { angle: deg(5), damping: 0 }, { angle: deg(-5), damping: 0 }, 1200, 12),
      // A long run (60 s) from the widest drag (75 deg) on the longest string, past the graph window.
      pendulumCase("long", 9.81, 3.5, { angle: deg(75), damping: 0 }, { angle: deg(-40), damping: 0 }, 3600, 30),
      // No gravity: released from rest, the bobs stay where they are.
      pendulumCase("zero g", 0, 2, WEB_ROPE, WEB_ROD, 120, 6),
    ],
    web_integrator: [webIntegrator(2, WEB_ROPE), webIntegrator(2, { angle: 0.62, damping: 0 })],
  };
}

describe("constraints lab vectors", () => {
  it("match the committed JSON generated from the TS core", () => {
    const vectors = buildVectors();
    if (process.env.UPDATE_CONSTRAINTS_VECTORS === "1") {
      writeFileSync(vectorsPath, `${JSON.stringify(vectors, null, 2)}\n`);
    }
    const committed = JSON.parse(readFileSync(vectorsPath, "utf8"));
    expect(committed).toEqual(JSON.parse(JSON.stringify(vectors)));
  });

  it("are the law's motion: RK4 x4 per step = RK4 x100 per step (TS PendulumModel acceleration) over 60 s", () => {
    for (const [length, damping, g, angle] of [[2, 0.06, 9.81, 0.62], [1, 0, 24.79, deg(75)], [3.5, 0, 9.81, deg(75)], [2, 0.03, 1.62, -0.5]]) {
      const lab = rk4Run(length, damping, g, angle, 3600, SUBSTEPS);
      const fine = rk4Run(length, damping, g, angle, 3600, 100);
      let worst = 0;
      for (let k = 0; k < lab.length; k += 1) worst = Math.max(worst, Math.abs(lab[k] - fine[k]));
      expect(worst).toBeLessThan(1e-6);
    }
  });

  it("keep the length, the energy without damping, a taut string, and the pendulum's period", () => {
    for (const run of buildVectors().cases) {
      for (const side of ["rope", "rod"] as const) {
        const start = run[side];
        const e0 = BOB_MASS * run.g * run.length * (1 - Math.cos(start.angle));
        let previous = Infinity;
        for (const s of run.samples) {
          const v = s[side] as ReturnType<LabPendulum["sample"]>;
          expect(Math.abs(Math.hypot(v.x, v.y) - run.length)).toBeLessThan(1e-12);
          if (run.g > 0) expect(v.tension).toBeGreaterThan(0);
          const e = BOB_MASS * run.g * run.length * (1 - Math.cos(v.angle)) + 0.5 * BOB_MASS * (run.length * v.omega) ** 2;
          if (start.damping === 0) expect(Math.abs(e - e0)).toBeLessThan(1e-7 * Math.max(1, e0));
          else expect(e).toBeLessThanOrEqual(previous + 1e-12);
          previous = e;
        }
        const last = run.samples[run.samples.length - 1][side] as ReturnType<LabPendulum["sample"]>;
        const want = run.large_angle_period[side];
        if (want !== null) expect(Math.abs(last.period - want) / want).toBeLessThan(1e-4);
      }
    }
    const small = buildVectors().cases.find((c) => c.name === "small")!;
    const lastSmall = small.samples[small.samples.length - 1].rope as ReturnType<LabPendulum["sample"]>;
    expect(Math.abs(lastSmall.period - small.small_angle_period!) / small.small_angle_period!).toBeLessThan(5e-4);
  });

  it("show why the lab does not copy the web's 60 Hz semi-implicit Euler stepping", () => {
    for (const run of buildVectors().web_integrator) expect(run.max_bob_error_20s).toBeGreaterThan(1e-2);
  });
});
