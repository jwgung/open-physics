// Generates and guards the formula parity vectors for the 10 guided mechanics experiments, consumed
// by the GDScript port (apps/lab3d/scripts/core/physics_laws.gd, checked in tests/run_tests.gd).
// The TS core is the oracle: every expected value comes from the TS law function or model class
// named next to it (src/physics/laws, src/physics/world.ts, src/app/mechanics-scenes.ts,
// src/app/mechanics-challenges.ts), never from re-typed formulas.
// - experiments: lab id -> the PhysicsLaws functions that lab uses (all 10 labs of MECHANICS_LABS).
// - cases: { law, args, expect } where law is the PhysicsLaws function name; args are scalars in SI
//   units (the web app uses 48 px = 1 m; the formulas are the same).
// - scenes: TS-computed targets for the representative headless scenes of each correction method
//   (apps/lab3d/tests/formula_checks.gd).
// Runs in the root `npm test`. Regenerate: UPDATE_FORMULA_VECTORS=1 npx vitest run apps/lab3d
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { LeverChallenge, OrbitChallenge, PulleyAdvantageChallenge, type SupportStrands } from "../../../src/app/mechanics-challenges";
import { MECHANICS_LABS } from "../../../src/app/mechanics-labs";
import { PendulumModel } from "../../../src/app/mechanics-scenes";
import { MATERIALS, type PlaygroundMaterial } from "../../../src/app/physics-playground";
import { collisionContact, MultiBodyWorld, type Body } from "../../../src/physics/world";
import type { BodyState } from "../../../src/physics/core";
import { elasticCollision1D } from "../../../src/physics/laws/collision";
import { buoyancyNetForce, buoyantForce, floatingSubmergedFraction } from "../../../src/physics/laws/fluid";
import { PointGravity, UniformGravity } from "../../../src/physics/laws/gravity";
import {
  constantAccelerationDisplacement,
  constantAccelerationVelocity,
  gravitationalPotentialEnergy,
  kineticEnergy,
  momentum,
  postCollisionVelocity1D,
  postCollisionVelocity1DSecond,
  springPotentialEnergy,
  work,
} from "../../../src/physics/laws/mechanics";
import { KineticFriction } from "../../../src/physics/laws/basic";
import { circularOrbitPeriod, circularOrbitSpeed, escapeSpeed } from "../../../src/physics/laws/orbit";
import {
  angularFrequency,
  harmonicDisplacement,
  harmonicEnergy,
  harmonicVelocity,
  pendulumAngularFrequency,
  pendulumPeriod,
  periodFromAngularFrequency,
} from "../../../src/physics/laws/oscillation";
import { rollingSpeed, torque } from "../../../src/physics/laws/rotation";
import { tsApexTime, tsLandingTime } from "./ts-oracle";
import { AnchoredSpringLaw, BuoyancyRegionLaw, PushFrictionLaw } from "../../../src/physics/laws/world-mechanics";

type Value = number | boolean | string | number[] | { [key: string]: Value };
interface Case { law: string; args: number[]; expect: Value }

const G = 9.81;
const DT = 1 / 60;
const PX = 48; // web app pixels per metre
const GRAVITIES = [1.62, 9.81, 24.79]; // web app gravity buttons (moon, earth, jupiter)
const MASSES = [0.5, 1, 3]; // web app mass buttons
const RESTITUTION_THRESHOLD = 48 / PX; // physics-playground RESTING_REBOUND_SPEED (48 px/s) in m/s
const vectorsPath = fileURLToPath(new URL("../tests/formula_vectors.json", import.meta.url));

const state = (x: number, y: number, vx: number, vy: number, mass: number): BodyState => ({
  position: { x, y },
  velocity: { x: vx, y: vy },
  acceleration: { x: 0, y: 0 },
  mass,
});

/** world.ts resolveCollisions as the oracle for a two-body contact (circles touching along n). */
class CollisionProbe extends MultiBodyWorld {
  resolve(): void { this.resolveCollisions(); }
}

function worldCollision(ma: number, mb: number, va: [number, number], vb: [number, number], angle: number, ea: number, eb: number): Case {
  const world = new CollisionProbe([], undefined, [], RESTITUTION_THRESHOLD);
  const ra = 0.6;
  const rb = 0.8;
  const gap = ra + rb - 1e-3; // just touching
  const a: Body = { id: "a", radius: ra, restitution: ea, state: state(0, 0, va[0], va[1], ma) };
  const b: Body = { id: "b", radius: rb, restitution: eb, state: state(gap * Math.cos(angle), gap * Math.sin(angle), vb[0], vb[1], mb) };
  const contact = collisionContact(a, b);
  if (!contact) throw new Error("collision probe bodies must touch");
  world.addBody(a);
  world.addBody(b);
  world.resolve();
  return {
    law: "world_collision_velocities",
    args: [ma, mb, va[0], va[1], vb[0], vb[1], contact.normal.x, contact.normal.y, ea, eb, RESTITUTION_THRESHOLD],
    expect: [a.state.velocity.x, a.state.velocity.y, b.state.velocity.x, b.state.velocity.y],
  };
}

function freeFall(): Case[] {
  const cases: Case[] = [];
  for (const g of GRAVITIES) {
    for (const t of [0.25, 0.5, 1, 1.3]) {
      cases.push({ law: "constant_acceleration_displacement", args: [0, -g, t], expect: constantAccelerationDisplacement({ x: 0, y: 0 }, { x: 0, y: -g }, t).y });
      cases.push({ law: "constant_acceleration_velocity", args: [0, -g, t], expect: constantAccelerationVelocity({ x: 0, y: 0 }, { x: 0, y: -g }, t).y });
    }
    for (const m of MASSES) {
      cases.push({ law: "uniform_gravity_force", args: [m, g], expect: -new UniformGravity({ x: 0, y: -g }).force(state(0, 0, 0, 0, m), { time: 0, dt: DT }).vector.y });
      cases.push({ law: "gravitational_potential_energy", args: [m, g, 8.3], expect: gravitationalPotentialEnergy(m, g, 8.3) });
      cases.push({ law: "kinetic_energy", args: [m, g * 1.3], expect: kineticEnergy(m, { x: g * 1.3, y: 0 }) });
      cases.push({ law: "momentum", args: [m, -g * 1.3], expect: momentum(m, { x: -g * 1.3, y: 0 }).x });
    }
    // Task 4a: time to reach the floor from the drop height (sqrt(2h/g) with no closed form in TS).
    for (const drop of [0.5, 2.5, 5, 8]) {
      cases.push({ law: "landing_time", args: [0, -g, drop], expect: tsLandingTime(0, -g, drop) });
    }
  }
  return cases;
}

function projectile(): Case[] {
  const cases: Case[] = [];
  const v0 = { x: 5.6, y: 7.2 }; // web preset launch (y up here)
  for (const g of GRAVITIES) {
    for (const t of [0.2, 0.5, 0.9, 1.4]) {
      const s = constantAccelerationDisplacement(v0, { x: 0, y: -g }, t);
      const v = constantAccelerationVelocity(v0, { x: 0, y: -g }, t);
      cases.push({ law: "constant_acceleration_displacement", args: [v0.x, 0, t], expect: s.x });
      cases.push({ law: "constant_acceleration_displacement", args: [v0.y, -g, t], expect: s.y });
      cases.push({ law: "constant_acceleration_velocity", args: [v0.y, -g, t], expect: v.y });
      cases.push({ law: "kinetic_energy", args: [1, Math.hypot(v.x, v.y)], expect: kineticEnergy(1, v) });
    }
    // Task 4a: flight time to a landing level `drop` below the launch, apex time and rise.
    for (const [speed, degrees, drop] of [[9, 45, 0.5], [7, 30, 0], [9, 60, 1.5], [5, 15, 3], [6, 90, 0.5], [8, 0, 2]]) {
      const angle = degrees * Math.PI / 180;
      const vy = speed * Math.sin(angle);
      cases.push({ law: "landing_time", args: [vy, -g, drop], expect: tsLandingTime(vy, -g, drop) });
      cases.push({ law: "apex_time", args: [vy, -g], expect: vy > 0 ? tsApexTime(vy, -g) : 0 });
      cases.push({ law: "apex_rise", args: [vy, -g], expect: vy > 0 ? constantAccelerationDisplacement({ x: 0, y: vy }, { x: 0, y: -g }, tsApexTime(vy, -g)).y : 0 });
    }
  }
  // Task 4f: the landed ball rolls without slipping, v = r omega (ball radius 0.25 m).
  for (const omega of [0, 4, 18.18, -25.71]) {
    cases.push({ law: "rolling_speed", args: [0.25, omega], expect: rollingSpeed(0.25, omega) });
  }
  // landing_time outside the labs' everyday range (review of PR #9): the first root t > 0 for any
  // signs, t = 0 for a start on the level moving below it, INF ("inf") when the level is never met.
  for (const [v0, a, drop] of [
    [7.2, -G, -0.5], // level above the start, reached on the way up
    [1, -G, -0.5], // level above the apex: never
    [-5, -G, -0.5], // level above, moving away: never
    [0, -G, 0], [-1, -G, 0], [3, -G, 0], // on the level: at once / at once / after the flight
    [-3, 2, 1], [-1, 2, 1], [0, 2, -1], [0, 2, 0], // field upwards: first root, never, rising, never
    [-2, 0, 1], [2, 0, 1], [2, 0, -1], [0, 0, 0], // no field: straight line
  ]) {
    cases.push({ law: "landing_time", args: [v0, a, drop], expect: finiteOr(tsLandingTime(v0, a, drop)) });
  }
  return cases;
}

/** JSON has no Infinity: an unbounded expectation is written as the string "inf". */
function finiteOr(value: number): number | string {
  return Number.isFinite(value) ? value : value > 0 ? "inf" : "-inf";
}

function collision(): Case[] {
  const cases: Case[] = [];
  const materials: PlaygroundMaterial[] = ["rubber", "wood", "steel", "clay"];
  for (const material of materials) {
    const e = MATERIALS[material].restitution;
    for (const [m1, u1, m2, u2] of [[1, 3.4, 2, -1.7], [3, 1.2, 0.5, 0], [0.5, 0.4, 1, -0.3]]) {
      cases.push({ law: "post_collision_velocity_1d", args: [m1, u1, m2, u2, e], expect: postCollisionVelocity1D(m1, u1, m2, u2, e) });
      cases.push({ law: "post_collision_velocity_1d_second", args: [m1, u1, m2, u2, e], expect: postCollisionVelocity1DSecond(m1, u1, m2, u2, e) });
    }
  }
  for (const [ma, va, mb, vb] of [[1, 3.4, 2, -1.7], [3, 2, 1, 0]]) {
    const result = elasticCollision1D(ma, va, mb, vb);
    cases.push({ law: "elastic_collision_1d", args: [ma, va, mb, vb], expect: [result.velocityA, result.velocityB] });
  }
  // Web preset (rubber balls 1 kg / 2 kg, 3.4 / -1.7 m/s), oblique hits, mixed materials, and a slow
  // touch below the 1 m/s restitution threshold.
  cases.push(worldCollision(1, 2, [3.4, 0], [-1.7, 0], 0, 0.88, 0.88));
  cases.push(worldCollision(1, 2, [3.4, 0.5], [-1.7, -0.2], 0.3, 0.88, 0.5));
  cases.push(worldCollision(3, 1, [2, 1], [0, 0], -0.7, 0.72, 0.08));
  cases.push(worldCollision(1, 2, [0.4, 0], [-0.3, 0], 0, 0.88, 0.88));
  for (const [ea, eb, closing] of [[0.88, 0.5, 5.1], [0.72, 0.88, 0.7], [0.08, 0.5, 1]]) {
    // world.ts: e = 0 below the threshold, else min(eA, eB) (reproduced through a contact)
    const probe = worldCollision(1, 1, [closing, 0], [0, 0], 0, ea, eb);
    const expected = probe.expect as number[];
    const restitution = (expected[2] - expected[0]) / closing; // separation / approach speed
    cases.push({ law: "collision_restitution", args: [ea, eb, closing, RESTITUTION_THRESHOLD], expect: restitution });
  }
  return cases;
}

function spring(): Case[] {
  const cases: Case[] = [];
  const stiffness = 5;
  for (const [extension, radial, damping] of [[2.4, 0, 0.45], [-0.8, 1.5, 0.45], [1.1, -2, 0], [0.3, 0.7, 0]]) {
    const law = new AnchoredSpringLaw({ bodyId: "ball", anchor: { x: 0, y: 0 }, stiffness, restLength: 5.6, damping });
    const force = law.force(state(5.6 + extension, 0, radial, 0, 1), { time: 0, dt: DT });
    cases.push({ law: "anchored_spring_force", args: [extension, radial, stiffness, damping], expect: force.vector.x });
    cases.push({ law: "spring_potential_energy", args: [stiffness, extension], expect: springPotentialEnergy(stiffness, extension) });
  }
  for (const mass of MASSES) {
    const omega = angularFrequency(stiffness, mass);
    cases.push({ law: "angular_frequency", args: [stiffness, mass], expect: omega });
    cases.push({ law: "period_from_angular_frequency", args: [omega], expect: periodFromAngularFrequency(omega) });
    for (const t of [0.3, 1.1, 2.5]) {
      cases.push({ law: "harmonic_displacement", args: [2.4, omega, t, 0], expect: harmonicDisplacement(2.4, omega, t, 0) });
      cases.push({ law: "harmonic_velocity", args: [2.4, omega, t, 0], expect: harmonicVelocity(2.4, omega, t, 0) });
    }
    cases.push({ law: "kinetic_energy", args: [mass, 1.7], expect: kineticEnergy(mass, { x: 1.7, y: 0 }) });
  }
  cases.push({ law: "harmonic_energy", args: [stiffness, 2.4], expect: harmonicEnergy(stiffness, 2.4) });
  return cases;
}

/**
 * PushFrictionLaw runs in the web app's px units (normalAcceleration = g * 48, "nearly stopped" below
 * 0.01 px/s). Unit rule for these cases: the SI args (N, m/s, m/s^2) go into the TS law multiplied by
 * PX (lengths in px, mass in kg), and the TS force comes back divided by PX. The speeds include both
 * sides of the 0.01 px/s boundary (0.004 and 0.02 px/s) and SI speeds that only a px-unaware port
 * (threshold 0.01 m/s) would treat as stopped.
 */
function friction(): Case[] {
  const cases: Case[] = [];
  const boundary = [0.004 / PX, 0.02 / PX, -0.004 / PX];
  for (const material of ["wood", "rubber", "steel", "clay"] as PlaygroundMaterial[]) {
    const muK = MATERIALS[material].friction;
    const muS = muK + 0.18; // physics-playground: staticFriction = friction + 0.18
    for (const mass of [1, 8]) {
      const pairs = [[10, 0], [40, 0], [80, 0], [80, 0.5], [0, 0.5], [-30, -0.2], [5, 0.004], [0, 0.02], ...boundary.map((speed) => [5, speed]), [0, boundary[1]]];
      for (const [applied, speed] of pairs) {
        const law = new PushFrictionLaw({ bodyId: "box", surfaceY: 0, staticCoefficient: muS, kineticCoefficient: muK, normalAcceleration: G * PX });
        law.setAppliedForce(applied * PX);
        const body = state(0, 0, speed * PX, 0, mass);
        cases.push({ law: "push_friction_force", args: [applied, speed, mass, muS, muK, G, DT], expect: law.force(body, { time: 0, dt: DT }).vector.x / PX });
        cases.push({ law: "push_friction_holding", args: [applied, speed, mass, muS, G], expect: law.status(body) === "holding" });
      }
      const law = new PushFrictionLaw({ bodyId: "box", surfaceY: 0, staticCoefficient: muS, kineticCoefficient: muK, normalAcceleration: G * PX });
      cases.push({ law: "push_max_static_force", args: [muS, mass, G], expect: law.maximumStaticForce(state(0, 0, 0, 0, mass)) / PX });
      // Task 4b: the lab's "운동 마찰력" readout (KineticFriction magnitude on a moving box, N = m g).
      const kinetic = new KineticFriction(mass * G, muK).force(state(0, 0, 1.5, 0, mass), { time: 0, dt: DT }).vector.x;
      cases.push({ law: "kinetic_friction_force", args: [muK, mass * G], expect: -kinetic });
    }
  }
  // Task 4b: friction work turned into heat, one step at a time (mechanics.ts work along x).
  for (const [force, displacement] of [[-17.2656, 0.0123], [4.12, -0.004], [0, 0.5]]) {
    cases.push({ law: "work_1d", args: [force, displacement], expect: work({ x: force, y: 0 }, { x: displacement, y: 0 }) });
  }
  return cases;
}

function lever(): Case[] {
  const cases: Case[] = [];
  const beam = 556.8 / PX; // web lever: beam 0.58 W at 960 px
  const loadArm = 0.22 * beam;
  for (const effortArm of [0.35, 0.6, 0.9].map((k) => 0.52 * beam * k)) {
    for (const mass of [5, 20]) {
      const challenge = new LeverChallenge({ loadMass: mass, gravity: G, loadArm, effortArm });
      cases.push({ law: "lever_required_force", args: [mass, G, loadArm, effortArm], expect: challenge.requiredForce });
      cases.push({ law: "lever_mechanical_advantage", args: [loadArm, effortArm], expect: challenge.mechanicalAdvantage });
      for (const applied of [-5, challenge.requiredForce * 0.9, challenge.requiredForce, challenge.requiredForce + 1]) {
        cases.push({ law: "lever_lifting", args: [applied, challenge.requiredForce], expect: challenge.applyForce(applied).lifting });
      }
      // Torque balance at the required force: load torque (clockwise) + effort torque = 0.
      cases.push({ law: "torque_2d", args: [-loadArm, 0, 0, -mass * G], expect: torque({ x: -loadArm, y: 0 }, { x: 0, y: -mass * G }) });
      cases.push({ law: "torque_2d", args: [effortArm, 0, 0, -challenge.requiredForce], expect: torque({ x: effortArm, y: 0 }, { x: 0, y: -challenge.requiredForce }) });
    }
  }
  return cases;
}

function pendulum(): Case[] {
  const cases: Case[] = [];
  const length = 210 / PX; // web pendulum length 210 px
  for (const g of GRAVITIES) {
    cases.push({ law: "pendulum_period", args: [length, g], expect: pendulumPeriod(length, g) });
    cases.push({ law: "pendulum_angular_frequency", args: [length, g], expect: pendulumAngularFrequency(length, g) });
  }
  // Rope (0.62 rad, damping 0.06) and rod (-0.5 rad, damping 0.03) of the web preset: single steps
  // from TS model states, and a 600-step run (10 s at 60 Hz).
  for (const [angle, damping] of [[0.62, 0.06], [-0.5, 0.03], [0.1, 0]]) {
    const model = new PendulumModel({ x: 0, y: 0 }, length, angle, damping);
    for (let step = 0; step < 600; step += 1) {
      const before = { angle: model.angle, velocity: model.angularVelocity };
      model.step(DT, G);
      if (step % 97 === 0) {
        cases.push({
          law: "pendulum_step",
          args: [before.angle, before.velocity, DT, G, length, damping],
          expect: [model.angle, model.angularVelocity, model.angularAcceleration],
        });
        const pose = model.pose();
        cases.push({ law: "pendulum_offset", args: [length, model.angle], expect: [pose.position.x, pose.position.y] });
      }
    }
    cases.push({ law: "pendulum_run", args: [angle, 0, DT, G, length, damping, 600], expect: [model.angle, model.angularVelocity] });
  }
  return cases;
}

function pulley(): Case[] {
  const cases: Case[] = [];
  for (const strands of [1, 2, 4] as SupportStrands[]) {
    for (const mass of [5, 20]) {
      for (const g of GRAVITIES) {
        const challenge = new PulleyAdvantageChallenge({ loadMass: mass, gravity: g, supportStrands: strands });
        cases.push({ law: "pulley_required_force", args: [mass, g, strands], expect: challenge.requiredForce });
      }
    }
    const challenge = new PulleyAdvantageChallenge({ loadMass: 20, gravity: G, supportStrands: strands });
    for (const distance of [0.5, 1, 200 / PX]) {
      cases.push({ law: "pulley_pull_distance", args: [distance, strands], expect: challenge.pullDistanceForLift(distance) });
      cases.push({ law: "pulley_lift_distance", args: [distance, strands], expect: challenge.liftDistanceForPull(distance) });
    }
  }
  return cases;
}

/** Web orbit preset in metres: r = 178.2 px, circular speed 155 px/s, GM = v^2 r (G = 1, M = GM). */
const ORBIT_RADIUS = 178.2 / PX;
const ORBIT_SPEED = 155 / PX;
const ORBIT_MU = ORBIT_SPEED ** 2 * ORBIT_RADIUS;
const ORBIT_COLLISION = 59 / PX;

function orbit(): Case[] {
  const cases: Case[] = [];
  for (const radius of [ORBIT_RADIUS, 2 * ORBIT_RADIUS, 0.5 * ORBIT_RADIUS]) {
    cases.push({ law: "circular_orbit_speed", args: [ORBIT_MU, radius, 1], expect: circularOrbitSpeed(ORBIT_MU, radius, 1) });
    cases.push({ law: "circular_orbit_period", args: [ORBIT_MU, radius, 1], expect: circularOrbitPeriod(ORBIT_MU, radius, 1) });
    cases.push({ law: "escape_speed", args: [ORBIT_MU, radius, 1], expect: escapeSpeed(ORBIT_MU, radius, 1) });
    const gravity = new PointGravity(ORBIT_MU, { x: 0, y: 0 }, 1);
    cases.push({ law: "point_gravity_acceleration", args: [ORBIT_MU, radius, 1], expect: gravity.force(state(radius, 0, 0, 0, 1), { time: 0, dt: DT }).vector.x * -1 });
  }
  const challenge = new OrbitChallenge({ center: { x: 0, y: 0 }, gravitationalParameter: ORBIT_MU, collisionRadius: ORBIT_COLLISION });
  for (const [vx, vy] of [[0, ORBIT_SPEED], [0, ORBIT_SPEED * 1.5], [-1.5, 1], [0.3, ORBIT_SPEED * 0.8], [0, 0.4]]) {
    const result = challenge.analyze({ x: ORBIT_RADIUS, y: 0 }, { x: vx, y: vy });
    cases.push({
      law: "orbit_analyze",
      args: [ORBIT_RADIUS, 0, vx, vy, 0, 0, ORBIT_MU, ORBIT_COLLISION],
      expect: {
        outcome: result.outcome,
        speed: result.speed,
        circular_speed: result.circularSpeed,
        escape_speed: result.escapeSpeed,
        path: result.path.flatMap((point) => [point.x, point.y]),
      },
    });
  }
  return cases;
}

/** Web buoyancy preset: displaced mass of the fully submerged ball 1.45 kg, drag 1.8 /s. */
const DISPLACED_MASS = 1.45;
const BUOYANCY_DRAG = 1.8;

function buoyancy(): Case[] {
  const cases: Case[] = [];
  const radius = 35 / PX;
  const waterline = 0;
  for (const mass of MASSES) {
    for (const [depth, velocityUp] of [[-0.2, -1], [0.1, -0.5], [0.7, 0.3], [1.0, 0], [2, -0.1]]) {
      // y down in the TS world: centre y = bottom depth - r below the waterline
      const law = new BuoyancyRegionLaw({ bodyId: "ball", waterline, displacedMass: DISPLACED_MASS, gravityAcceleration: G, drag: BUOYANCY_DRAG });
      const body: Body = { id: "ball", radius, state: state(0, depth - radius, 0.4, -velocityUp, mass) };
      const force = law.forceOnBody(body, [body], { time: 0, dt: DT });
      const fraction = Math.max(0, Math.min(1, (body.state.position.y + radius - waterline) / (radius * 2)));
      cases.push({ law: "submerged_fraction", args: [depth, 2 * radius], expect: fraction });
      cases.push({ law: "buoyancy_region_force", args: [DISPLACED_MASS, G, BUOYANCY_DRAG, fraction, mass, velocityUp], expect: -force.vector.y || 0 });
      cases.push({ law: "buoyancy_drag_force", args: [BUOYANCY_DRAG, fraction, mass, 0.4], expect: force.vector.x || 0 });
    }
    const volume = (4 / 3) * Math.PI * radius ** 3;
    const fluidDensity = DISPLACED_MASS / volume;
    cases.push({ law: "floating_submerged_fraction", args: [mass / volume, fluidDensity], expect: floatingSubmergedFraction(mass / volume, fluidDensity) });
    cases.push({ law: "buoyancy_net_force", args: [fluidDensity, mass / volume, G, volume], expect: buoyancyNetForce(fluidDensity, mass / volume, G, volume) });
    cases.push({ law: "buoyant_force", args: [fluidDensity, G, volume], expect: buoyantForce(fluidDensity, G, volume) });
  }
  return cases;
}

/**
 * world.ts MultiBodyWorld with uniform gravity: spheres A (-3, 6) at (3.4, 0) m/s and B (3, 6) at
 * (-1.7, 0) m/s (radii 0.6 / 0.8, e = 0.88) fall side by side and collide in the air (horizontal
 * normal). Returns the velocities [vax, vay, vbx, vby] after `steps` 60 Hz steps (TS world order:
 * integrate, then resolve collisions).
 */
function worldCollisionUnderGravity(steps: number): number[] {
  const gravity = new UniformGravity({ x: 0, y: -G });
  const gravityLaw = { id: gravity.id, force: gravity.force.bind(gravity), forceOnBody: (body: Body, _bodies: readonly Body[], context: { time: number; dt: number }) => gravity.force(body.state, context) };
  const world = new CollisionProbe([gravityLaw], undefined, [], RESTITUTION_THRESHOLD);
  const a: Body = { id: "a", radius: 0.6, restitution: 0.88, state: state(-3, 6, 3.4, 0, 1) };
  const b: Body = { id: "b", radius: 0.8, restitution: 0.88, state: state(3, 6, -1.7, 0, 2) };
  world.addBody(a);
  world.addBody(b);
  for (let step = 0; step < steps; step += 1) world.step(DT);
  return [a.state.velocity.x, a.state.velocity.y, b.state.velocity.x, b.state.velocity.y];
}

/** Targets for the representative Jolt scenes (one per correction method), from the TS core. */
function scenes() {
  const v0 = { x: 3, y: 4 };
  const projectileTimes = [0.25, 0.5, 0.75];
  const pushMass = 8;
  const pushMuK = MATERIALS.wood.friction;
  const pushMuS = pushMuK + 0.18;
  const push = new PushFrictionLaw({ bodyId: "box", surfaceY: 0, staticCoefficient: pushMuS, kineticCoefficient: pushMuK, normalAcceleration: G });
  push.setAppliedForce(50);
  const pushAccel = push.force(state(0, 0, 1, 0, pushMass), { time: 0, dt: DT }).vector.x / pushMass;
  const elastic = worldCollision(1, 2, [3.4, 0], [-1.7, 0], 0, 1, 1).expect as number[];
  const rubber = worldCollision(1, 2, [3.4, 0], [-1.7, 0], 0, 0.88, 0.88).expect as number[];
  const slow = worldCollision(1, 2, [0.4, 0], [-0.3, 0], 0, 0.88, 0.88).expect as number[];
  const springOmega = angularFrequency(5, 1);
  const pendulumLength = 2;
  const pendulumModel = new PendulumModel({ x: 0, y: 0 }, pendulumLength, 0.1, 0);
  const pendulumAngles: number[] = [];
  // Default path: the web scene's constructor default damping (no argument).
  const defaultPendulum = new PendulumModel({ x: 0, y: 0 }, pendulumLength, 0.1);
  const defaultAngles: number[] = [];
  for (let step = 1; step <= 120; step += 1) {
    pendulumModel.step(DT, G);
    defaultPendulum.step(DT, G);
    if (step % 30 === 0) {
      pendulumAngles.push(pendulumModel.angle);
      defaultAngles.push(defaultPendulum.angle);
    }
  }
  const buoyancyVolume = 0.4 ** 3; // 0.4 m cube (an upright prism: the linear fraction is exact)
  const fluidDensity = DISPLACED_MASS / buoyancyVolume;
  return {
    uniform_field: {
      g: G,
      v0: [v0.x, v0.y],
      masses: MASSES,
      samples: projectileTimes.map((t) => {
        const s = constantAccelerationDisplacement(v0, { x: 0, y: -G }, t);
        return { t, x: s.x, y: s.y };
      }),
    },
    contact_force: {
      mass: pushMass,
      mu_s: pushMuS,
      mu_k: pushMuK,
      max_static: push.maximumStaticForce(state(0, 0, 0, 0, pushMass)),
      hold_force: 25,
      push_force: 50,
      accel: pushAccel,
      samples: [1, 2].map((t) => ({ t, s: constantAccelerationDisplacement({ x: 0, y: 0 }, { x: pushAccel, y: 0 }, t).x })),
    },
    collision: {
      masses: [1, 2],
      velocities: [3.4, -1.7],
      threshold: RESTITUTION_THRESHOLD,
      elastic: { e: 1, after: [elastic[0], elastic[2]] },
      rubber: { e: 0.88, after: [rubber[0], rubber[2]] },
      // 0.7 m/s closing: below the 1 m/s threshold, e = 0 (Jolt resolves this over several steps).
      slow: { e: 0.88, velocities: [0.4, -0.3], after: [slow[0], slow[2]] },
      gravity: { e: 0.88, steps: 80, after: worldCollisionUnderGravity(80) },
      momentum: momentum(1, { x: 3.4, y: 0 }).x + momentum(2, { x: -1.7, y: 0 }).x,
    },
    force_injection: {
      spring: { stiffness: 5, mass: 1, amplitude: 0.5, period: periodFromAngularFrequency(springOmega), energy: harmonicEnergy(5, 0.5) },
      orbit: {
        mu: ORBIT_MU,
        radius: ORBIT_RADIUS,
        speed: circularOrbitSpeed(ORBIT_MU, ORBIT_RADIUS, 1),
        period: circularOrbitPeriod(ORBIT_MU, ORBIT_RADIUS, 1),
      },
      buoyancy: {
        displaced_mass: DISPLACED_MASS,
        drag: BUOYANCY_DRAG,
        size: 0.4,
        light: { mass: 1, fraction: floatingSubmergedFraction(1 / buoyancyVolume, fluidDensity) },
        heavy: { mass: 3, fraction: Math.min(1, floatingSubmergedFraction(3 / buoyancyVolume, fluidDensity)) },
      },
    },
    kinematic_model: {
      pendulum: {
        length: pendulumLength,
        angle: 0.1,
        period: pendulumPeriod(pendulumLength, G),
        angles: pendulumAngles,
        default_damping: defaultPendulum.damping,
        default_angles: defaultAngles,
      },
      pulley: [1, 2, 4].map((strands) => {
        const challenge = new PulleyAdvantageChallenge({ loadMass: 20, gravity: G, supportStrands: strands as SupportStrands });
        return { strands, force: challenge.requiredForce, lift_for_pull_1m: challenge.liftDistanceForPull(1) };
      }),
      lever: (() => {
        const challenge = new LeverChallenge({ loadMass: 20, gravity: G, loadArm: 1, effortArm: 2.5 });
        return { load_mass: 20, load_arm: 1, effort_arm: 2.5, required: challenge.requiredForce };
      })(),
    },
  };
}

const GROUPS: Record<string, () => Case[]> = {
  "free-fall": freeFall,
  projectile,
  collision,
  spring,
  friction,
  rotation: lever,
  constraints: pendulum,
  pulley,
  orbit,
  buoyancy,
};

function buildVectors() {
  const experiments: Record<string, string[]> = {};
  const cases: (Case & { experiment: string })[] = [];
  for (const lab of MECHANICS_LABS) {
    const group = GROUPS[lab.id]();
    experiments[lab.id] = [...new Set(group.map((entry) => entry.law))];
    cases.push(...group.map((entry) => ({ experiment: lab.id, ...entry })));
  }
  return {
    source: "src/physics/laws, src/physics/world.ts, src/app/mechanics-scenes.ts, src/app/mechanics-challenges.ts",
    tolerance: 1e-9,
    dt: DT,
    experiments,
    cases,
    scenes: scenes(),
  };
}

describe("formula parity vectors for the 3D guided mechanics experiments", () => {
  it("match the committed JSON generated from the TS core", () => {
    const vectors = buildVectors();
    if (process.env.UPDATE_FORMULA_VECTORS === "1") {
      writeFileSync(vectorsPath, `${JSON.stringify(vectors, null, 2)}\n`);
    }
    const committed = JSON.parse(readFileSync(vectorsPath, "utf8"));
    expect(committed).toEqual(JSON.parse(JSON.stringify(vectors)));
  });

  it("cover all 10 guided mechanics labs with at least one law each", () => {
    const vectors = buildVectors();
    expect(Object.keys(vectors.experiments).sort()).toEqual(MECHANICS_LABS.map((lab) => lab.id).sort());
    expect(MECHANICS_LABS).toHaveLength(10);
    for (const laws of Object.values(vectors.experiments)) expect(laws.length).toBeGreaterThan(0);
    expect(vectors.cases.every((entry) => entry.args.every(Number.isFinite))).toBe(true);
  });

  it("scene targets are self-consistent", () => {
    const { scenes: targets } = buildVectors();
    // Momentum is conserved by both outcomes; the elastic case also conserves kinetic energy.
    for (const outcome of [targets.collision.elastic, targets.collision.rubber]) {
      expect(outcome.after[0] * 1 + outcome.after[1] * 2).toBeCloseTo(targets.collision.momentum, 12);
    }
    const ke = (v: number[]) => 0.5 * v[0] ** 2 + v[1] ** 2;
    expect(ke(targets.collision.elastic.after)).toBeCloseTo(ke([3.4, -1.7]), 12);
    expect(targets.contact_force.hold_force).toBeLessThan(targets.contact_force.max_static);
    expect(targets.contact_force.push_force).toBeGreaterThan(targets.contact_force.max_static);
    expect(targets.force_injection.buoyancy.light.fraction).toBeLessThan(1);
    expect(targets.force_injection.buoyancy.heavy.fraction).toBe(1);
  });
});
