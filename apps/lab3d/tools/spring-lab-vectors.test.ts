// Generates and guards the vectors of the spring lab (Phase 1 Task 4d, web preset "spring",
// "용수철은 에너지를 어떻게 돌려줄까?"), consumed by apps/lab3d/tests/spring_lab_checks.gd.
// The law is the web's: AnchoredSpringLaw (src/physics/laws/world-mechanics.ts, F = -k x - b v_r along
// the spring, k = 5 N/m) on a ball released from rest at extension x0 along a straight rod. The lab
// moves the ball by the law's exact motion at t = k dt (60 Hz):
// - b = 0: oscillation.ts harmonicDisplacement / harmonicVelocity with angularFrequency(k, m);
// - b > 0: x(t) = e^(-g t) (x0 cos wd t + g x0 / wd sin wd t), g = b / 2m, wd = sqrt(w0^2 - g^2)
//   (the TS core has no damped form; it is written here and checked against an RK4 integration of
//   the TS AnchoredSpringLaw.force itself, to 1e-9).
// Energies: mechanics.ts kineticEnergy / springPotentialEnergy; period: periodFromAngularFrequency.
// The web steps the law with world.ts explicit Euler (x += v dt, then v += a dt) at 120 Hz; the
// "web integrator" entry records how far that drifts from the law's motion (why the lab does not
// copy it: without damping its energy grows every period).
// Runs in the root `npm test`. Regenerate: UPDATE_SPRING_VECTORS=1 npx vitest run apps/lab3d
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { AnchoredSpringLaw } from "../../../src/physics/laws/world-mechanics";
import { kineticEnergy, springPotentialEnergy } from "../../../src/physics/laws/mechanics";
import {
  angularFrequency,
  harmonicDisplacement,
  harmonicVelocity,
  periodFromAngularFrequency,
} from "../../../src/physics/laws/oscillation";
import type { BodyState, PhysicsContext } from "../../../src/physics/core";

const STEP_HZ = 60;
const DT = 1 / STEP_HZ;
const STIFFNESS = 5; // physics-playground connectSpring stiffness (N/m; px units cancel: N/px over px)
const WEB_DAMPING = 0.45; // physics-playground connectSpring damping
const REST = 3; // the 3D rod: rest length (m)
const vectorsPath = fileURLToPath(new URL("../tests/spring_lab_vectors.json", import.meta.url));
const playgroundPath = fileURLToPath(new URL("../../../src/app/physics-playground.ts", import.meta.url));
const context: PhysicsContext = { time: 0, dt: DT };

const law = (damping: number) => new AnchoredSpringLaw({ bodyId: "ball", anchor: { x: 0, y: 0 }, restLength: REST, stiffness: STIFFNESS, damping });

/** Force of the TS law on a ball at extension e moving at v along the rod (+x). */
function lawForce(spring: AnchoredSpringLaw, mass: number, e: number, v: number): number {
  const state: BodyState = { position: { x: REST + e, y: 0 }, velocity: { x: v, y: 0 }, acceleration: { x: 0, y: 0 }, mass };
  return spring.force(state, context).vector.x;
}

/** The law's motion released from rest at x0 (exact form; TS functions when b = 0). */
function motion(mass: number, damping: number, x0: number, t: number): { x: number; v: number } {
  const w0 = angularFrequency(STIFFNESS, mass);
  if (damping === 0) return { x: harmonicDisplacement(x0, w0, t), v: harmonicVelocity(x0, w0, t) };
  const g = damping / (2 * mass);
  const wd = Math.sqrt(w0 * w0 - g * g);
  const decay = Math.exp(-g * t);
  return {
    x: decay * (x0 * Math.cos(wd * t) + (g * x0 / wd) * Math.sin(wd * t)),
    v: -decay * x0 * (w0 * w0 / wd) * Math.sin(wd * t),
  };
}

/** RK4 of the TS law from rest at x0 to time `t` (steps of h): the reference the exact form must meet. */
function integrateLaw(mass: number, damping: number, x0: number, t: number, h = 1 / 6000): { x: number; v: number } {
  const spring = law(damping);
  const a = (x: number, v: number) => lawForce(spring, mass, x, v) / mass;
  let x = x0;
  let v = 0;
  const n = Math.round(t / h);
  for (let i = 0; i < n; i += 1) {
    const k1x = v;
    const k1v = a(x, v);
    const k2x = v + 0.5 * h * k1v;
    const k2v = a(x + 0.5 * h * k1x, v + 0.5 * h * k1v);
    const k3x = v + 0.5 * h * k2v;
    const k3v = a(x + 0.5 * h * k2x, v + 0.5 * h * k2v);
    const k4x = v + h * k3v;
    const k4v = a(x + h * k3x, v + h * k3v);
    x += (h / 6) * (k1x + 2 * k2x + 2 * k3x + k4x);
    v += (h / 6) * (k1v + 2 * k2v + 2 * k3v + k4v);
  }
  return { x, v };
}

/** One release: samples every `every` steps up to `steps` (m, m/s, N, J). */
function springCase(name: string, mass: number, damping: number, x0: number, steps: number, every: number) {
  const spring = law(damping);
  const samples: Record<string, number>[] = [];
  for (let k = 0; k <= steps; k += every) {
    const t = k * DT;
    const { x, v } = motion(mass, damping, x0, t);
    const kinetic = kineticEnergy(mass, { x: v, y: 0 });
    const potential = springPotentialEnergy(STIFFNESS, x);
    samples.push({ step: k, x, v, force: lawForce(spring, mass, x, v), kinetic, potential, total: kinetic + potential });
  }
  const w0 = angularFrequency(STIFFNESS, mass);
  const g = damping / (2 * mass);
  return {
    name,
    mass,
    damping,
    x0,
    steps,
    period: damping === 0 ? periodFromAngularFrequency(w0) : periodFromAngularFrequency(Math.sqrt(w0 * w0 - g * g)),
    release_energy: springPotentialEnergy(STIFFNESS, x0),
    samples,
  };
}

/** The web's own stepping (world.ts explicit Euler, 120 Hz) against the law's motion over 10 s. */
function webIntegrator(mass: number, damping: number, x0: number) {
  const spring = law(damping);
  const h = 1 / 120;
  let x = x0;
  let v = 0;
  let worst = 0;
  for (let k = 1; k <= 1200; k += 1) {
    const a = lawForce(spring, mass, x, v) / mass;
    x += v * h;
    v += a * h;
    worst = Math.max(worst, Math.abs(x - motion(mass, damping, x0, k * h).x));
  }
  return {
    mass,
    damping,
    x0,
    max_position_error_10s: worst,
    energy_ratio_10s: (kineticEnergy(mass, { x: v, y: 0 }) + springPotentialEnergy(STIFFNESS, x)) / springPotentialEnergy(STIFFNESS, x0),
  };
}

function buildVectors() {
  return {
    source: "src/physics/laws/world-mechanics.ts AnchoredSpringLaw, oscillation.ts angularFrequency / harmonicDisplacement / harmonicVelocity / periodFromAngularFrequency, mechanics.ts kineticEnergy / springPotentialEnergy",
    tolerance: 1e-9,
    step_hz: STEP_HZ,
    stiffness: STIFFNESS,
    web_damping: WEB_DAMPING,
    rest_length: REST,
    cases: [
      // The lab's start: 1 kg (the web's), no damping, pulled 1.2 m.
      springCase("start", 1, 0, 1.2, 1200, 6),
      // Pushed in 1 m, light ball.
      springCase("light pushed", 0.5, 0, -1, 1200, 6),
      // Heavy ball pulled far: a longer period.
      springCase("heavy", 3, 0, 2, 1200, 6),
      // The web's damping 0.45 N s/m.
      springCase("web damping", 1, WEB_DAMPING, 1.2, 1200, 6),
      springCase("heavy damped", 5, WEB_DAMPING, 2.5, 1200, 6),
      // A long run (60 s) without damping: the motion past the graph and history window.
      springCase("long", 1, 0, 1.2, 3600, 30),
    ],
    web_integrator: [webIntegrator(1, 0, 1.2), webIntegrator(1, WEB_DAMPING, 1.2)],
  };
}

describe("spring lab vectors", () => {
  it("use the web's spring constants", () => {
    const source = readFileSync(playgroundPath, "utf8");
    expect(source).toMatch(/stiffness: 5,\n\s+damping: 0\.45,/);
  });

  it("match the committed JSON generated from the TS core", () => {
    const vectors = buildVectors();
    if (process.env.UPDATE_SPRING_VECTORS === "1") {
      writeFileSync(vectorsPath, `${JSON.stringify(vectors, null, 2)}\n`);
    }
    const committed = JSON.parse(readFileSync(vectorsPath, "utf8"));
    expect(committed).toEqual(JSON.parse(JSON.stringify(vectors)));
  });

  it("are the TS law's motion (RK4 of AnchoredSpringLaw.force) and keep energy without damping", () => {
    for (const [mass, damping, x0] of [[1, 0, 1.2], [0.5, 0, -1], [1, WEB_DAMPING, 1.2], [5, WEB_DAMPING, 2.5]]) {
      for (const t of [0.5, 2.7, 9.95]) {
        const exact = motion(mass, damping, x0, t);
        const rk4 = integrateLaw(mass, damping, x0, t);
        expect(Math.abs(exact.x - rk4.x)).toBeLessThan(1e-9);
        expect(Math.abs(exact.v - rk4.v)).toBeLessThan(1e-9);
      }
    }
    const { cases } = buildVectors();
    for (const run of cases.filter((c) => c.damping === 0)) {
      for (const s of run.samples) expect(Math.abs(s.total - run.release_energy)).toBeLessThan(1e-12 * Math.max(1, run.release_energy));
    }
    for (const run of cases.filter((c) => c.damping > 0)) {
      for (let i = 1; i < run.samples.length; i += 1) expect(run.samples[i].total).toBeLessThanOrEqual(run.samples[i - 1].total + 1e-12);
    }
  });

  it("show why the lab does not copy the web's explicit Euler stepping", () => {
    const [free] = buildVectors().web_integrator;
    expect(free.energy_ratio_10s).toBeGreaterThan(1.05);
    expect(free.max_position_error_10s).toBeGreaterThan(1e-2);
  });
});
