// Generates and guards the display vectors of the uniform-field labs (Phase 1 Task 4a: free fall,
// projectile), consumed by apps/lab3d/tests/uniform_lab_checks.gd. For the labs' own conditions
// (the web's gravity buttons, drop heights, launch angle / speed / height) it records what the
// panel must show at given fixed steps and at the landing, every value from the TS core
// (src/physics/laws/mechanics.ts; landing time and apex by bisection of the TS functions,
// ./ts-oracle.ts). Runs in the root `npm test`. Regenerate: UPDATE_UNIFORM_VECTORS=1 npx vitest run apps/lab3d
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import {
  constantAccelerationDisplacement,
  constantAccelerationVelocity,
  gravitationalPotentialEnergy,
  kineticEnergy,
  momentum,
  speed,
} from "../../../src/physics/laws/mechanics";
import { tsApexTime, tsLandingTime } from "./ts-oracle";

const STEP_HZ = 60;
// The web's gravity buttons (mechanics: data-gravity) as the labs' "gravity" options.
const GRAVITIES: Record<string, number> = { moon: 1.62, earth: 9.81, jupiter: 24.79 };
const RED_MASS = 3; // "mass" control default (heavy), the web's heavy ball
const vectorsPath = fileURLToPath(new URL("../tests/uniform_labs_vectors.json", import.meta.url));

function freeFallCase(gravity: string, height: number) {
  const g = GRAVITIES[gravity];
  const a = { x: 0, y: -g };
  const rest = { x: 0, y: 0 };
  const landing = tsLandingTime(0, -g, height);
  const at = (t: number) => {
    const v = constantAccelerationVelocity(rest, a, t);
    const h = height + constantAccelerationDisplacement(rest, a, t).y;
    return {
      height: h,
      speed: speed(v),
      momentum: Math.abs(momentum(RED_MASS, v).y),
      kinetic: kineticEnergy(RED_MASS, v),
      potential: gravitationalPotentialEnergy(RED_MASS, g, h),
    };
  };
  const steps = [20, 40, 60, 90].filter((k) => k / STEP_HZ < landing);
  const atLanding = at(landing);
  return {
    gravity,
    g,
    height,
    red_mass: RED_MASS,
    landing_time: landing,
    samples: steps.map((step) => ({ step, t: step / STEP_HZ, ...at(step / STEP_HZ) })),
    landing: { speed: atLanding.speed, momentum: atLanding.momentum, kinetic: atLanding.kinetic },
  };
}

function projectileCase(gravity: string, angleDeg: number, launchSpeed: number, height: number) {
  const g = GRAVITIES[gravity];
  const angle = angleDeg * Math.PI / 180;
  const v0 = { x: launchSpeed * Math.cos(angle), y: launchSpeed * Math.sin(angle) };
  const a = { x: 0, y: -g };
  const flight = tsLandingTime(v0.y, -g, height);
  const apexRise = v0.y > 0 ? constantAccelerationDisplacement({ x: 0, y: v0.y }, a, tsApexTime(v0.y, -g)).y : 0;
  const steps = [15, 30, 45].filter((k) => k / STEP_HZ < flight);
  return {
    gravity,
    g,
    angle: angleDeg,
    speed: launchSpeed,
    height,
    flight_time: flight,
    range: constantAccelerationDisplacement(v0, a, flight).x,
    apex: height + apexRise,
    samples: steps.map((step) => {
      const t = step / STEP_HZ;
      const s = constantAccelerationDisplacement(v0, a, t);
      const v = constantAccelerationVelocity(v0, a, t);
      return { step, t, x: s.x, y: height + s.y, vx: v.x, vy: v.y };
    }),
  };
}

function buildVectors() {
  return {
    source: "src/physics/laws/mechanics.ts (apps/lab3d/tools/ts-oracle.ts for landing time and apex)",
    tolerance: 1e-9,
    step_hz: STEP_HZ,
    free_fall: [
      freeFallCase("earth", 5),
      freeFallCase("earth", 2.5),
      freeFallCase("moon", 5),
      freeFallCase("moon", 2.5),
      freeFallCase("jupiter", 5),
      freeFallCase("jupiter", 8),
    ],
    projectile: [
      projectileCase("earth", 45, 9, 0.5),
      projectileCase("earth", 30, 7, 0),
      projectileCase("moon", 60, 4, 1.5),
      projectileCase("jupiter", 15, 5, 3),
      projectileCase("earth", 90, 6, 0.5),
      projectileCase("earth", 0, 8, 2),
    ],
  };
}

describe("uniform-field lab display vectors (free fall, projectile)", () => {
  it("match the committed JSON generated from the TS core", () => {
    const vectors = buildVectors();
    if (process.env.UPDATE_UNIFORM_VECTORS === "1") {
      writeFileSync(vectorsPath, `${JSON.stringify(vectors, null, 2)}\n`);
    }
    const committed = JSON.parse(readFileSync(vectorsPath, "utf8"));
    expect(committed).toEqual(JSON.parse(JSON.stringify(vectors)));
  });

  it("are self-consistent", () => {
    const { free_fall: drops, projectile: throws } = buildVectors();
    for (const drop of drops) {
      // At the landing the ball has fallen the whole height: y(T) = 0.
      expect(drop.height + constantAccelerationDisplacement({ x: 0, y: 0 }, { x: 0, y: -drop.g }, drop.landing_time).y).toBeCloseTo(0, 9);
      expect(drop.samples.length).toBeGreaterThan(0);
    }
    for (const shot of throws) {
      expect(shot.apex).toBeGreaterThanOrEqual(shot.height);
      expect(shot.range).toBeGreaterThanOrEqual(-1e-12);
    }
  });
});
