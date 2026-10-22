// Generates and guards the vectors of the lever lab (Phase 1 Task 4e, web preset "rotation",
// "지렛대로 무거운 짐을 들 수 있을까?"), consumed by apps/lab3d/tests/rotation_lab_checks.gd.
// The law is the web's LeverChallenge (src/app/mechanics-challenges.ts): required force
// F = m g r_load / r_effort, lifting when the force on the beam reaches it; the web caps the force at
// the required force (Math.min(requiredForce, drag * rate)) and turns the beam to LEVER_LIFT_ANGLE
// (0.18 rad) when lifting. Torques: rotation.ts torque about the fulcrum. Weight: gravity.ts
// UniformGravity. The 3D lever: a 6 m beam centred at x = 0 whose axis is 1.25 m up, the fulcrum at
// pivot, the load centre at load_x and 0.46 m above the axis (riding with the beam), the effort point
// at fraction x (3 - pivot) right of the fulcrum, the handle a spring scale of 5 N per 2 cm cell.
// Runs in the root `npm test`. Regenerate: UPDATE_ROTATION_VECTORS=1 npx vitest run apps/lab3d
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { LeverChallenge } from "../../../src/app/mechanics-challenges";
import { torque } from "../../../src/physics/laws/rotation";
import { UniformGravity } from "../../../src/physics/laws/gravity";

const G = 9.81;
const BEAM_HALF = 3;
const PIVOT_Y = 1.25;
const LOAD_UP = 0.46;
const LIFT_ANGLE = 0.18;
const FORCE_STEP = 5; // N per handle cell
const CELLS = 50; // 1 m of press
const vectorsPath = fileURLToPath(new URL("../tests/rotation_lab_vectors.json", import.meta.url));
const playgroundPath = fileURLToPath(new URL("../../../src/app/physics-playground.ts", import.meta.url));

const weight = (mass: number) => -new UniformGravity({ x: 0, y: -G }).force({ position: { x: 0, y: 0 }, velocity: { x: 0, y: 0 }, acceleration: { x: 0, y: 0 }, mass }, { time: 0, dt: 1 / 60 }).vector.y;

/** World (x, y) of a point `along` the level beam and `up` above its axis, turned by `angle` about the fulcrum. */
function beamPoint(pivot: number, angle: number, along: number, up: number): [number, number] {
  return [pivot + (along - pivot) * Math.cos(angle) - up * Math.sin(angle), PIVOT_Y + (along - pivot) * Math.sin(angle) + up * Math.cos(angle)];
}

function leverCase(name: string, mass: number, pivot: number, loadX: number, fraction: number) {
  const loadArm = pivot - loadX;
  const effortArm = fraction * (BEAM_HALF - pivot);
  const challenge = new LeverChallenge({ loadMass: mass, gravity: G, loadArm, effortArm });
  const presses = [];
  for (let cells = 0; cells <= CELLS; cells += 1) {
    const hand = cells * FORCE_STEP;
    const attempt = challenge.applyForce(Math.min(challenge.requiredForce, hand));
    const angle = attempt.lifting ? -LIFT_ANGLE : 0;
    const [lx, ly] = beamPoint(pivot, angle, loadX, LOAD_UP);
    const [bx, by] = beamPoint(pivot, angle, 0, 0);
    presses.push({
      cells,
      applied: attempt.appliedForce,
      lifting: attempt.lifting,
      angle,
      load: [lx, ly],
      beam: [bx, by],
      effort_torque: torque({ x: effortArm, y: 0 }, { x: 0, y: -attempt.appliedForce }),
    });
  }
  return {
    name,
    mass,
    pivot,
    load_x: loadX,
    fraction,
    load_arm: loadArm,
    effort_arm: effortArm,
    weight: weight(mass),
    required: challenge.requiredForce,
    advantage: challenge.mechanicalAdvantage,
    load_torque: torque({ x: -loadArm, y: 0 }, { x: 0, y: -weight(mass) }),
    presses,
  };
}

function buildVectors() {
  return {
    source: "src/app/mechanics-challenges.ts LeverChallenge, src/physics/laws/rotation.ts torque, gravity.ts UniformGravity; physics-playground.ts LEVER_LIFT_ANGLE",
    tolerance: 1e-9,
    g: G,
    beam_half: BEAM_HALF,
    pivot_y: PIVOT_Y,
    load_up: LOAD_UP,
    lift_angle: LIFT_ANGLE,
    force_step: FORCE_STEP,
    cases: [
      // The lab's start: the web's 20 kg load, the middle effort point.
      leverCase("start", 20, -0.5, -2.5, 0.6),
      // The near point needs 320 N: more than the handle's 250 N, the beam never lifts.
      leverCase("near", 20, -0.5, -2.5, 0.35),
      leverCase("far", 20, -0.5, -2.5, 0.9),
      // A light load with the fulcrum moved right and the load at the far left (the far point).
      leverCase("light", 5, 1, -2.75, 0.9),
      leverCase("moved", 13, 0.25, -1.25, 0.6),
      // The fulcrum far left, the load close to it: a long effort arm.
      leverCase("long arm", 20, -1.5, -2, 0.9),
    ],
  };
}

describe("rotation lab vectors", () => {
  it("use the web's lift angle and the cap at the required force", () => {
    const source = readFileSync(playgroundPath, "utf8");
    expect(source).toMatch(/const LEVER_LIFT_ANGLE = 0\.18;/);
    expect(source).toMatch(/scene\.appliedForce = Math\.min\(scene\.model\.requiredForce, dy \* LEVER_FORCE_PER_PIXEL\);/);
    expect(source).toMatch(/label: "무거운 짐",[^}]*mass: 20,/);
  });

  it("match the committed JSON generated from the TS core", () => {
    const vectors = buildVectors();
    if (process.env.UPDATE_ROTATION_VECTORS === "1") {
      writeFileSync(vectorsPath, `${JSON.stringify(vectors, null, 2)}\n`);
    }
    const committed = JSON.parse(readFileSync(vectorsPath, "utf8"));
    expect(committed).toEqual(JSON.parse(JSON.stringify(vectors)));
  });

  it("balance the torques when the beam lifts and lift only from the required force on", () => {
    for (const run of buildVectors().cases) {
      expect(Math.abs(run.required * run.effort_arm - run.weight * run.load_arm)).toBeLessThan(1e-9 * run.weight * run.load_arm);
      for (const p of run.presses) {
        expect(p.lifting).toBe(p.cells * FORCE_STEP >= run.required);
        if (p.lifting) expect(Math.abs(run.load_torque + p.effort_torque)).toBeLessThan(1e-9 * Math.abs(run.load_torque));
        // The load rides on the rigid beam: its distance from the fulcrum axis never changes.
        const d = Math.hypot(p.load[0] - run.pivot, p.load[1] - PIVOT_Y);
        expect(Math.abs(d - Math.hypot(run.load_arm, LOAD_UP))).toBeLessThan(1e-12);
      }
    }
    expect(buildVectors().cases.find((c) => c.name === "near")!.presses.some((p) => p.lifting)).toBe(false);
  });
});
