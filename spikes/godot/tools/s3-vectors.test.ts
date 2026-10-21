// Generates and guards the S3 parity vectors consumed by the GDScript port (tests/run_tests.gd).
// The TS formula core is the oracle: values come from SurfaceContactFrictionModifier and
// constantAccelerationDisplacement, not from re-typed formulas.
// Run from the repo root: npm run test:spikes (root vitest excludes spikes/**).
// Regenerate: UPDATE_S3_VECTORS=1 npm run test:spikes
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { constantAccelerationDisplacement } from "../../../src/physics/laws/mechanics";
import { SurfaceContactFrictionModifier } from "../../../src/physics/laws/world-mechanics";
import type { Body } from "../../../src/physics/world";

const G = 9.81;
const MU_S = 0.5;
const MU_K = 0.4;
const MASS = 1;
const DT = 1 / 60;
const ANGLES = [10, 20, 26, 26.5, 26.6, 27, 30, 35, 40];
const SPEEDS = [0, 1];
const vectorsPath = fileURLToPath(new URL("../tests/s3_vectors.json", import.meta.url));

/** Downhill tangential acceleration of a 1 kg body on a fixed ramp, from the TS friction modifier. */
function tangentialAcceleration(thetaDeg: number, downhillSpeed: number): number {
  const friction = new SurfaceContactFrictionModifier({ floorY: 1e6, normalAcceleration: G });
  const angle = -thetaDeg * Math.PI / 180;
  const downhill = { x: -Math.cos(angle), y: -Math.sin(angle) };
  const body: Body = {
    id: "box",
    radius: 10,
    staticFriction: MU_S,
    kineticFriction: MU_K,
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
    staticFriction: MU_S,
    kineticFriction: MU_K,
    fixed: true,
    state: { position: { x: 50, y: 100 }, velocity: { x: 0, y: 0 }, acceleration: { x: 0, y: 0 }, mass: 1 },
  };
  const result = friction.modifyForce(body, [body, ramp], { vector: { x: 0, y: MASS * G } }, { time: 0, dt: DT });
  return (result.vector.x * downhill.x + result.vector.y * downhill.y) / MASS;
}

function buildVectors() {
  const cases = ANGLES.flatMap((theta) => SPEEDS.map((speed) => ({
    theta_deg: theta,
    speed,
    tangential_accel: tangentialAcceleration(theta, speed),
  })));
  const a35 = tangentialAcceleration(35, 0);
  return {
    source: "src/physics/laws (SurfaceContactFrictionModifier, constantAccelerationDisplacement)",
    g: G,
    mu_s: MU_S,
    mu_k: MU_K,
    mass: MASS,
    dt: DT,
    critical_angle_deg: Math.atan(MU_S) * 180 / Math.PI,
    accel_35: a35,
    displacement_35: [1, 2].map((t) => ({ t, s: constantAccelerationDisplacement({ x: 0, y: 0 }, { x: a35, y: 0 }, t).x })),
    cases,
  };
}

describe("S3 parity vectors for the Godot spike", () => {
  it("match the committed JSON generated from the TS core", () => {
    const vectors = buildVectors();
    if (process.env.UPDATE_S3_VECTORS === "1") {
      writeFileSync(vectorsPath, `${JSON.stringify(vectors, null, 2)}\n`);
    }
    const committed = JSON.parse(readFileSync(vectorsPath, "utf8"));
    expect(committed).toEqual(vectors);
    expect(vectors.accel_35).toBeCloseTo(2.412, 3);
    expect(vectors.displacement_35[0].s).toBeCloseTo(1.206, 3);
  });
});
