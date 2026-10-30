// Generates and guards the display vectors of the push friction lab (Phase 1 Task 4b, web preset
// "friction"), consumed by apps/lab3d/tests/friction_lab_checks.gd. For the lab's conditions (the
// web's four materials, its mass buttons and its 8 kg start box) and a schedule of applied forces it
// records what the panel must show after given fixed steps, every value from the TS core:
// PushFrictionLaw (src/physics/laws/world-mechanics.ts: status, force, maximumStaticForce) and
// mechanics.ts (work, kineticEnergy).
// Stepping rule (the app's discretisation, the same as the contact force corrector and the lab's
// formula model, apps/lab3d/docs/formula-correction.md): per fixed step the law gives the net force
// on the box state before the step; on the step that leaves rest only half of it acts (leapfrog
// start); then v += F/m dt, x += v dt (symplectic Euler, as Jolt). Friction = net - applied (the
// web's force breakdown), heat = -sum work(friction, step displacement).
// Unit rule (formula-vectors.test.ts "friction"): PushFrictionLaw runs in the web's px units (48 px =
// 1 m, "nearly stopped" below 0.01 px/s), so lengths, speeds, forces and the normal acceleration go
// in multiplied by PX and come back divided by PX (energies by PX^2).
// Runs in the root `npm test`. Regenerate: UPDATE_FRICTION_VECTORS=1 npx vitest run apps/lab3d
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { MATERIALS, type PlaygroundMaterial } from "../../../src/physics/materials";
import type { BodyState } from "../../../src/physics/core";
import { kineticEnergy, work } from "../../../src/physics/laws/mechanics";
import { PushFrictionLaw } from "../../../src/physics/laws/world-mechanics";

const G = 9.81;
const STEP_HZ = 60;
const DT = 1 / STEP_HZ;
const PX = 48;
// The lab's "mass" options: the web's mass buttons (가벼움 / 보통 / 무거움) and its 8 kg start box.
const MASSES: Record<string, number> = { light: 0.5, normal: 1, heavy: 3, start: 8 };
const vectorsPath = fileURLToPath(new URL("../tests/friction_lab_vectors.json", import.meta.url));

type Segment = [force: number, steps: number];

const state = (x: number, vx: number, mass: number): BodyState => ({
  position: { x, y: 0 },
  velocity: { x: vx, y: 0 },
  acceleration: { x: 0, y: 0 },
  mass,
});

function coefficients(material: PlaygroundMaterial) {
  const muK = MATERIALS[material].friction;
  return { muS: muK + 0.18, muK }; // physics-playground: staticFriction = friction + 0.18
}

function frictionCase(material: PlaygroundMaterial, massId: string, schedule: Segment[], every = 15) {
  const mass = MASSES[massId];
  const { muS, muK } = coefficients(material);
  const law = new PushFrictionLaw({ bodyId: "box", surfaceY: 0, staticCoefficient: muS, kineticCoefficient: muK, normalAcceleration: G * PX });
  let x = 0; // px
  let v = 0; // px/s
  let heat = 0; // J
  let path = 0; // m slid (sum of |dx|)
  let wasHolding = true;
  let step = 0;
  const samples: Record<string, number | string>[] = [];
  for (const [force, count] of schedule) {
    law.setAppliedForce(force * PX);
    for (let i = 0; i < count; i += 1) {
      const before = state(x, v, mass);
      const holding = law.status(before) === "holding";
      const net = law.force(before, { time: step * DT, dt: DT }).vector.x;
      const starting = wasHolding && !holding && Math.abs(v) < 0.01;
      v += (starting ? 0.5 * net : net) / mass * DT;
      const dx = v * DT;
      x += dx;
      const friction = net - force * PX;
      heat -= work({ x: friction, y: 0 }, { x: dx, y: 0 }) / (PX * PX);
      path += Math.abs(dx) / PX;
      wasHolding = holding;
      step += 1;
      if (step % every === 0) {
        samples.push({
          step,
          applied: force,
          state: holding ? "holding" : "sliding",
          friction: friction / PX,
          speed: Math.abs(v) / PX,
          displacement: x / PX,
          heat,
          path,
          kinetic: kineticEnergy(mass, { x: v / PX, y: 0 }),
        });
      }
    }
  }
  return {
    material,
    mass_id: massId,
    mass,
    mu_s: muS,
    mu_k: muK,
    max_static: law.maximumStaticForce(state(0, 0, mass)) / PX,
    kinetic_friction: muK * mass * G,
    schedule,
    samples,
  };
}

/** The holding status of the TS law at rest for forces just below / at / above the maximum static friction. */
function thresholdCase(material: PlaygroundMaterial, massId: string) {
  const mass = MASSES[massId];
  const { muS, muK } = coefficients(material);
  const law = new PushFrictionLaw({ bodyId: "box", surfaceY: 0, staticCoefficient: muS, kineticCoefficient: muK, normalAcceleration: G * PX });
  const maxStatic = law.maximumStaticForce(state(0, 0, mass)) / PX;
  const forces = [maxStatic - 0.01, maxStatic, maxStatic + 0.01];
  return {
    material,
    mass_id: massId,
    max_static: maxStatic,
    forces,
    holding: forces.map((force) => {
      law.setAppliedForce(force * PX);
      return law.status(state(0, 0, mass)) === "holding";
    }),
  };
}

function buildVectors() {
  return {
    source: "src/physics/laws/world-mechanics.ts PushFrictionLaw, src/physics/laws/mechanics.ts work / kineticEnergy",
    tolerance: 1e-9,
    step_hz: STEP_HZ,
    g: G,
    masses: MASSES,
    push: [
      frictionCase("wood", "start", [[31, 30], [32, 60], [0, 90]]),
      frictionCase("steel", "light", [[1, 30], [2, 30], [0, 150]]),
      frictionCase("rubber", "normal", [[5, 30], [6, 30], [0, 30], [-8, 30], [0, 60]]),
      frictionCase("clay", "heavy", [[22, 30], [23, 60], [0, 60]]),
    ],
    thresholds: [
      thresholdCase("wood", "start"),
      thresholdCase("steel", "light"),
      thresholdCase("rubber", "normal"),
      thresholdCase("clay", "heavy"),
    ],
  };
}

describe("push friction lab display vectors", () => {
  it("match the committed JSON generated from the TS core", () => {
    const vectors = buildVectors();
    if (process.env.UPDATE_FRICTION_VECTORS === "1") {
      writeFileSync(vectorsPath, `${JSON.stringify(vectors, null, 2)}\n`);
    }
    const committed = JSON.parse(readFileSync(vectorsPath, "utf8"));
    expect(committed).toEqual(JSON.parse(JSON.stringify(vectors)));
  });

  it("are self-consistent", () => {
    const { push, thresholds } = buildVectors();
    for (const run of push) {
      // Below the maximum static friction nothing moves; the case ends at rest.
      const first = run.samples[0];
      expect(first.state).toBe("holding");
      expect(first.displacement).toBe(0);
      const last = run.samples[run.samples.length - 1];
      expect(last.speed as number).toBeCloseTo(0, 12);
      // Heat = kinetic friction x distance slid (the clamped stopping step adds no distance).
      expect(last.heat as number).toBeCloseTo(run.kinetic_friction * (last.path as number), 9);
      expect(run.samples.some((sample) => sample.state === "sliding")).toBe(true);
    }
    for (const threshold of thresholds) expect(threshold.holding).toEqual([true, true, false]);
  });
});
