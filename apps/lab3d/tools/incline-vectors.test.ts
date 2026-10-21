// Generates and guards the incline friction parity vectors consumed by the GDScript port
// (apps/lab3d/tests/run_tests.gd). The TS formula core is the oracle: values come from
// SurfaceContactFrictionModifier and constantAccelerationDisplacement, not from re-typed formulas.
// Coefficient sets: the benchmark spec's S3 pair (mu_s 0.5 / mu_k 0.4) and the web app's surface
// materials (MATERIALS: mu_s = friction + 0.18, mu_k = friction), which the experiment content
// (content/experiments/incline-friction.json) must repeat exactly.
// Runs in the root `npm test`. Regenerate: UPDATE_INCLINE_VECTORS=1 npx vitest run apps/lab3d
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { MATERIALS, type PlaygroundMaterial } from "../../../src/app/physics-playground";
import { constantAccelerationDisplacement } from "../../../src/physics/laws/mechanics";
import { SurfaceContactFrictionModifier } from "../../../src/physics/laws/world-mechanics";
import type { Body } from "../../../src/physics/world";

const G = 9.81;
const MASS = 1;
const DT = 1 / 60;
const SPEEDS = [0, 1];
const STATIC_OFFSET = 0.18; // physics-playground.ts: staticFriction = friction + 0.18
const MATERIAL_ORDER: PlaygroundMaterial[] = ["steel", "wood", "rubber", "clay"];
const vectorsPath = fileURLToPath(new URL("../tests/incline_vectors.json", import.meta.url));
const contentPath = fileURLToPath(new URL("../content/experiments/incline-friction.json", import.meta.url));

/** Downhill tangential acceleration of a 1 kg body on a fixed ramp of the same material. */
function tangentialAcceleration(thetaDeg: number, downhillSpeed: number, muS: number, muK: number): number {
  const friction = new SurfaceContactFrictionModifier({ floorY: 1e6, normalAcceleration: G });
  const angle = -thetaDeg * Math.PI / 180;
  const downhill = { x: -Math.cos(angle), y: -Math.sin(angle) };
  const body: Body = {
    id: "box",
    radius: 10,
    staticFriction: muS,
    kineticFriction: muK,
    state: {
      position: { x: 50 + Math.sin(angle) * 15, y: 100 - Math.cos(angle) * 15 },
      velocity: { x: downhill.x * downhillSpeed, y: downhill.y * downhillSpeed },
      acceleration: { x: 0, y: 0 },
      mass: MASS,
    },
  };
  const ramp: Body = {
    id: "ramp",
    collider: { kind: "box", halfWidth: 50, halfHeight: 5, angle },
    staticFriction: muS,
    kineticFriction: muK,
    fixed: true,
    state: { position: { x: 50, y: 100 }, velocity: { x: 0, y: 0 }, acceleration: { x: 0, y: 0 }, mass: 1 },
  };
  const result = friction.modifyForce(body, [body, ramp], { vector: { x: 0, y: MASS * G } }, { time: 0, dt: DT });
  return (result.vector.x * downhill.x + result.vector.y * downhill.y) / MASS;
}

function coefficientSet(id: string, muS: number, muK: number) {
  const critical = Math.atan(muS) * 180 / Math.PI;
  const angles = [...new Set([10, 20, critical - 0.5, critical + 0.5, 30, 35, 40, 45].map((a) => Math.round(a * 10) / 10))]
    .sort((a, b) => a - b);
  const accel = (theta: number) => tangentialAcceleration(theta, 0, muS, muK);
  return {
    id,
    mu_s: muS,
    mu_k: muK,
    critical_angle_deg: critical,
    accel_35: accel(35),
    accel_40: accel(40),
    displacement_40: [1, 2].map((t) => ({ t, s: constantAccelerationDisplacement({ x: 0, y: 0 }, { x: accel(40), y: 0 }, t).x })),
    cases: angles.flatMap((theta) => SPEEDS.map((speed) => ({
      theta_deg: theta,
      speed,
      tangential_accel: tangentialAcceleration(theta, speed, muS, muK),
    }))),
  };
}

function buildVectors() {
  return {
    source: "src/physics/laws (SurfaceContactFrictionModifier, constantAccelerationDisplacement), src/app/physics-playground.ts MATERIALS",
    g: G,
    mass: MASS,
    dt: DT,
    sets: [
      coefficientSet("spec-s3", 0.5, 0.4),
      ...MATERIAL_ORDER.map((id) => coefficientSet(id, MATERIALS[id].friction + STATIC_OFFSET, MATERIALS[id].friction)),
    ],
  };
}

describe("incline friction parity vectors for the 3D app", () => {
  it("match the committed JSON generated from the TS core", () => {
    const vectors = buildVectors();
    if (process.env.UPDATE_INCLINE_VECTORS === "1") {
      writeFileSync(vectorsPath, `${JSON.stringify(vectors, null, 2)}\n`);
    }
    const committed = JSON.parse(readFileSync(vectorsPath, "utf8"));
    expect(committed).toEqual(vectors);
    const spec = vectors.sets[0];
    expect(spec.critical_angle_deg).toBeCloseTo(26.565, 3);
    expect(spec.accel_35).toBeCloseTo(2.412, 3);
  });

  it("experiment content uses the TS surface materials", () => {
    const content = JSON.parse(readFileSync(contentPath, "utf8"));
    const material = content.controls.find((control: { id: string }) => control.id === "material");
    expect(material.options.map((option: { id: string }) => option.id)).toEqual(MATERIAL_ORDER);
    for (const option of material.options) {
      const friction = MATERIALS[option.id as PlaygroundMaterial].friction;
      expect(option.mu_s).toBeCloseTo(friction + STATIC_OFFSET, 12);
      expect(option.mu_k).toBeCloseTo(friction, 12);
    }
  });
});
