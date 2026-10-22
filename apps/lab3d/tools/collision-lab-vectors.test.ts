// Generates and guards the display vectors of the collision lab (Phase 1 Task 4c, web preset
// "collision", "충돌하면 움직임은 어디로 갈까?"), consumed by apps/lab3d/tests/collision_lab_checks.gd.
// Every value comes from the web's own physics: two circle bodies in the web's PhysicsSimulation
// (src/physics/simulation.ts = world.ts MultiBodyWorld: explicit Euler integration, then
// resolveCollisions with the restitution rule min(eA, eB), e = 0 below 48 px/s, penetration push-out)
// in the web's px units (48 px = 1 m), stepped at the app's 60 Hz, with the collision preset's per
// frame rules of src/app/physics-playground.ts after each step (advance): applyPresetDamping
// (v *= exp(-0.15 dt), a body slower than 2 px/s stops) and resolveWorldBounds (a body past a wall
// is put on it and, moving outwards, reflected with v *= -e of its material). The two rule constants
// are private in physics-playground.ts; the "web constants" test reads them from its source so a web
// change breaks this file first. The walls are the 3D rail's (its ends), not the web canvas edges.
// Displayed values: momentum / kineticEnergy (mechanics.ts) and coefficientOfRestitution of the
// first collision (the first step whose collision resolution changed a velocity: an impulse; the
// web's own result only counts closings >= 1 m/s, the 3D lab shows slower ones too, with e = 0).
// Runs in the root `npm test`. Regenerate: UPDATE_COLLISION_VECTORS=1 npx vitest run apps/lab3d
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { MATERIALS, type PlaygroundMaterial } from "../../../src/app/physics-playground";
import type { Body } from "../../../src/physics/world";
import { coefficientOfRestitution, kineticEnergy, momentum } from "../../../src/physics/laws/mechanics";
import { PhysicsSimulation } from "../../../src/physics/simulation";
import { vectorMismatch } from "./ts-oracle";

const STEP_HZ = 60;
const DT = 1 / STEP_HZ;
const PX = 48;
const THRESHOLD_PX = 48; // physics-playground RESTING_REBOUND_SPEED (px/s): restitution threshold 1 m/s
const DAMPING = 0.15; // physics-playground COLLISION_WORLD_DAMPING (1/s)
const SLEEP_PX = 2; // physics-playground MOTION_SLEEP_SPEED (px/s)
// The 3D rail (apps/lab3d/experiments/collision/collision.gd): walls (bumper faces) at x = +-7 m,
// ball radii 0.4 m (A) and 0.5 m (B; the web's 32 / 40 px balls, scaled).
const WALL = 7;
const RADIUS_A = 0.4;
const RADIUS_B = 0.5;
const playgroundPath = fileURLToPath(new URL("../../../src/app/physics-playground.ts", import.meta.url));
const vectorsPath = fileURLToPath(new URL("../tests/collision_lab_vectors.json", import.meta.url));

type Ball = { x: number; v: number; mass: number; material: PlaygroundMaterial | number };

/** PhysicsSimulation that reports whether the last collision resolution changed a velocity. */
class CollisionLab extends PhysicsSimulation {
  impulse = false;
  protected resolveCollisions(): void {
    const before = this.allBodies.map((body) => body.state.velocity.x);
    super.resolveCollisions();
    this.impulse = this.allBodies.some((body, i) => body.state.velocity.x !== before[i]);
  }
}

const restitutionOf = (material: PlaygroundMaterial | number) => (typeof material === "number" ? material : MATERIALS[material].restitution);

function body(id: string, ball: Ball, radius: number): Body {
  return {
    id,
    radius: radius * PX,
    collider: { kind: "circle", radius: radius * PX },
    restitution: restitutionOf(ball.material),
    state: { position: { x: ball.x * PX, y: 300 }, velocity: { x: ball.v * PX, y: 0 }, acceleration: { x: 0, y: 0 }, mass: ball.mass },
  };
}

/** One run of `steps` fixed steps; samples every `every` steps (m, m/s, kg m/s, J). */
function collisionCase(name: string, a: Ball, b: Ball, steps: number, every = 6) {
  const lab = new CollisionLab({ restitutionVelocityThreshold: THRESHOLD_PX });
  const bodyA = body("a", a, RADIUS_A);
  const bodyB = body("b", b, RADIUS_B);
  lab.addBody(bodyA);
  lab.addBody(bodyB);
  const bodies = [bodyA, bodyB];
  const radii = [RADIUS_A, RADIUS_B];
  const ms = [a.mass, b.mass];
  const v = () => bodies.map((x) => x.state.velocity.x / PX);
  let first: Record<string, unknown> | null = null;
  let collisions = 0;
  const samples: Record<string, unknown>[] = [];
  for (let step = 1; step <= steps; step += 1) {
    const before = v();
    lab.step(DT);
    if (lab.impulse) {
      collisions += 1;
      if (!first) {
        const after = v();
        const pa = momentum(ms[0], { x: before[0], y: 0 }).x;
        const pb = momentum(ms[1], { x: before[1], y: 0 }).x;
        const qa = momentum(ms[0], { x: after[0], y: 0 }).x;
        const qb = momentum(ms[1], { x: after[1], y: 0 }).x;
        first = {
          step,
          before,
          after,
          restitution: coefficientOfRestitution(after[1] - after[0], before[0] - before[1]),
          impulse: [qa - pa, qb - pb],
          momentum: [pa + pb, qa + qb],
          kinetic: [
            kineticEnergy(ms[0], { x: before[0], y: 0 }) + kineticEnergy(ms[1], { x: before[1], y: 0 }),
            kineticEnergy(ms[0], { x: after[0], y: 0 }) + kineticEnergy(ms[1], { x: after[1], y: 0 }),
          ],
        };
      }
    }
    // physics-playground advance(): applyPresetDamping, then resolveWorldBounds (x only: y is fixed).
    const damping = Math.exp(-DAMPING * DT);
    bodies.forEach((x, i) => {
      x.state.velocity.x *= damping;
      x.state.velocity.y *= damping;
      if (Math.hypot(x.state.velocity.x, x.state.velocity.y) < SLEEP_PX) x.state.velocity = { x: 0, y: 0 };
      const left = (-WALL + radii[i]) * PX;
      const right = (WALL - radii[i]) * PX;
      if (x.state.position.x < left) {
        x.state.position.x = left;
        if (x.state.velocity.x < 0) x.state.velocity.x *= -(x.restitution ?? 0.6);
      } else if (x.state.position.x > right) {
        x.state.position.x = right;
        if (x.state.velocity.x > 0) x.state.velocity.x *= -(x.restitution ?? 0.6);
      }
    });
    if (step % every === 0) {
      const now = v();
      samples.push({
        step,
        x: bodies.map((x) => x.state.position.x / PX),
        v: now,
        p: now.map((value, i) => momentum(ms[i], { x: value, y: 0 }).x),
        collisions,
      });
    }
  }
  return {
    name,
    a: { ...a, restitution: restitutionOf(a.material), radius: RADIUS_A },
    b: { ...b, restitution: restitutionOf(b.material), radius: RADIUS_B },
    steps,
    first,
    collisions,
    samples,
  };
}

function buildVectors() {
  return {
    source: "src/physics/simulation.ts PhysicsSimulation (world.ts resolveCollisions), src/app/physics-playground.ts collision preset damping / bounds, src/physics/laws/mechanics.ts",
    tolerance: 1e-9,
    step_hz: STEP_HZ,
    threshold: THRESHOLD_PX / PX,
    damping: DAMPING,
    sleep_speed: SLEEP_PX / PX,
    wall: WALL,
    cases: [
      // The web's start: A 1 kg rubber at 3.4 m/s, B 2 kg rubber at -1.7 m/s (8 m apart).
      collisionCase("web start", { x: -4, v: 3.4, mass: 1, material: "rubber" }, { x: 4, v: -1.7, mass: 2, material: "rubber" }, 600),
      // Equal masses, e = 1 (ideal elastic, set by the test): the velocities are exchanged.
      collisionCase("equal elastic", { x: -4, v: 3, mass: 1, material: 1 }, { x: 2, v: 0, mass: 1, material: 1 }, 240),
      // Equal masses, rubber: nearly exchanged.
      collisionCase("equal rubber", { x: -4, v: 3, mass: 1, material: "rubber" }, { x: 2, v: 0, mass: 1, material: "rubber" }, 240),
      // Clay with steel: e = min = 0.08, heavy A pushes light B on.
      collisionCase("clay heavy", { x: -5, v: 4, mass: 5, material: "clay" }, { x: 1, v: 0, mass: 0.5, material: "steel" }, 600),
      // Wood: e = 0.5, the light A comes back.
      collisionCase("wood light", { x: -3, v: 5, mass: 0.5, material: "wood" }, { x: 3, v: -1, mass: 3, material: "wood" }, 600),
      // Slow closing (0.8 m/s < 1 m/s): e = 0, they move on together.
      collisionCase("slow", { x: -2, v: 0.5, mass: 1, material: "rubber" }, { x: 1, v: -0.3, mass: 2, material: "rubber" }, 480),
      // Same direction: steel A catches the slower B.
      collisionCase("catch up", { x: -6, v: 6, mass: 2, material: "steel" }, { x: -1, v: 1.5, mass: 1, material: "steel" }, 600),
    ],
  };
}

describe("collision lab display vectors", () => {
  it("use the web's collision preset constants", () => {
    const source = readFileSync(playgroundPath, "utf8");
    expect(source).toMatch(/const COLLISION_WORLD_DAMPING = 0\.15;/);
    expect(source).toMatch(/const MOTION_SLEEP_SPEED = 2;/);
    expect(source).toMatch(/const RESTING_REBOUND_SPEED = PIXELS_PER_METER;/);
    expect(source).toMatch(/const PIXELS_PER_METER = 48;/);
    expect(source).toMatch(/body\.state\.velocity\.x \*= -restitution;/);
  });

  it("match the committed JSON generated from the TS core", () => {
    const vectors = buildVectors();
    if (process.env.UPDATE_COLLISION_VECTORS === "1") {
      writeFileSync(vectorsPath, `${JSON.stringify(vectors, null, 2)}\n`);
    }
    const committed = JSON.parse(readFileSync(vectorsPath, "utf8"));
    expect(vectorMismatch(committed, JSON.parse(JSON.stringify(vectors)))).toBeNull();
  });

  it("are self-consistent", () => {
    const { cases } = buildVectors();
    for (const run of cases) {
      const first = run.first as { momentum: number[]; kinetic: number[]; restitution: number; before: number[]; after: number[] };
      expect(first).not.toBeNull();
      // Momentum is conserved in the collision; kinetic energy never grows.
      expect(first.momentum[1]).toBeCloseTo(first.momentum[0], 12);
      expect(first.kinetic[1]).toBeLessThanOrEqual(first.kinetic[0] + 1e-12);
    }
    const byName = Object.fromEntries(cases.map((run) => [run.name, run.first as { before: number[]; after: number[]; restitution: number }]));
    expect(byName["equal elastic"].after[0]).toBeCloseTo(byName["equal elastic"].before[1], 12);
    expect(byName["equal elastic"].after[1]).toBeCloseTo(byName["equal elastic"].before[0], 12);
    expect(byName["web start"].restitution).toBeCloseTo(0.88, 12);
    expect(byName["clay heavy"].restitution).toBeCloseTo(0.08, 12);
    expect(byName["slow"].restitution).toBeCloseTo(0, 12);
    expect(byName["slow"].after[0]).toBeCloseTo(byName["slow"].after[1], 12);
  });
});
