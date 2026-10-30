// Generates and guards the vectors of the buoyancy lab (Phase 1 Task 4d, web preset "buoyancy",
// "물체는 언제 물에 뜰까?"), consumed by apps/lab3d/tests/buoyancy_lab_checks.gd.
// Forces come from the TS core itself: BuoyancyRegionLaw.forceOnBody (src/physics/laws/
// world-mechanics.ts; the web's y-down axes, so up = -y; a body of radius h / 2 gives the linear
// submerged fraction of an upright drum of height h) and UniformGravity (gravity.ts). The 3D drum
// (water 1000 kg/m^3, 100 L or 50 L) is stepped at 60 Hz with 4 semi-implicit Euler substeps
// (v += a h, then y += v h) and the web's floor rule (resolveWorldBounds bottom: put on the floor, a
// downward velocity rebounds with e = 0.5 (wood) unless the rebound is slower than 48 px/s = 1 m/s).
// Displays: fluid.ts floatingSubmergedFraction (rho_object / rho_water), mechanics.ts density /
// buoyantForce. The "web integrator" entry steps the same law the web's way (world.ts explicit
// Euler, y += v h then v += a h, 120 Hz) to record why the lab does not copy it.
// Runs in the root `npm test`. Regenerate: UPDATE_BUOYANCY_VECTORS=1 npx vitest run apps/lab3d
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import type { PhysicsContext } from "../../../src/physics/core";
import { buoyantForce, density } from "../../../src/physics/laws/mechanics";
import { floatingSubmergedFraction } from "../../../src/physics/laws/fluid";
import { UniformGravity } from "../../../src/physics/laws/gravity";
import { BuoyancyRegionLaw } from "../../../src/physics/laws/world-mechanics";
import type { Body } from "../../../src/physics/world";

const STEP_HZ = 60;
const DT = 1 / STEP_HZ;
const SUBSTEPS = 4;
const G = 9.81; // the 3D app's engine gravity (project default)
const WATER = 1000; // kg/m^3
const DRAG = 1.8; // BuoyancyRegionLaw default (1/s)
const WATERLINE = 1.5; // the 3D tank (m, up)
const FLOOR = 0.2;
const RESTITUTION = 0.5; // physics-playground buoyancy ball material "wood"
const REBOUND_MIN = 1; // physics-playground RESTING_REBOUND_SPEED = 48 px/s
const HIT_SPEED = 0.05; // m/s: a floor contact faster than this is a hit (resting on the floor is not)
const BIG = { volume: 0.1, height: 0.5 }; // 100 L drum
const SMALL = { volume: 0.05, height: 0.4 }; // 50 L drum
const vectorsPath = fileURLToPath(new URL("../tests/buoyancy_lab_vectors.json", import.meta.url));
const context: PhysicsContext = { time: 0, dt: DT };

type Drum = { volume: number; height: number };

/** The drum's state as a TS world body (y down) and the forces on it (N, up +). */
class DrumLab {
  readonly law: BuoyancyRegionLaw;
  readonly gravity = new UniformGravity({ x: 0, y: -G });
  y: number;
  vy = 0;

  constructor(readonly drum: Drum, readonly mass: number, centre: number) {
    this.law = new BuoyancyRegionLaw({ bodyId: "drum", waterline: -WATERLINE, displacedMass: WATER * drum.volume, gravityAcceleration: G, drag: DRAG });
    this.y = centre;
  }

  private body(): Body {
    return {
      id: "drum",
      radius: this.drum.height / 2,
      state: { position: { x: 0, y: -this.y }, velocity: { x: 0, y: -this.vy }, acceleration: { x: 0, y: 0 }, mass: this.mass },
    };
  }

  lawForce(): number {
    return -this.law.forceOnBody(this.body(), [], context).vector.y;
  }

  net(): number {
    const state = this.body().state;
    return this.lawForce() + this.gravity.force({ ...state, position: { x: 0, y: this.y } }, context).vector.y;
  }

  fraction(): number {
    return Math.max(0, Math.min(1, (WATERLINE - (this.y - this.drum.height / 2)) / this.drum.height));
  }

  /** One 60 Hz step of the 3D lab. */
  step(): { hit: boolean; entered: boolean } {
    const h = DT / SUBSTEPS;
    let hit = false;
    let entered = false;
    for (let i = 0; i < SUBSTEPS; i += 1) {
      const wasDry = this.y - this.drum.height / 2 >= WATERLINE;
      this.vy += this.net() / this.mass * h;
      this.y += this.vy * h;
      if (wasDry && this.y - this.drum.height / 2 < WATERLINE && this.vy < 0) entered = true;
      if (this.y - this.drum.height / 2 < FLOOR) {
        this.y = FLOOR + this.drum.height / 2;
        if (this.vy < 0) {
          if (-this.vy > HIT_SPEED) hit = true;
          const rebound = -this.vy * RESTITUTION;
          this.vy = rebound < REBOUND_MIN ? 0 : rebound;
        }
      }
    }
    return { hit, entered };
  }
}

function buoyancyCase(name: string, drum: Drum, mass: number, centre: number, steps: number, every: number) {
  const lab = new DrumLab(drum, mass, centre);
  const samples: Record<string, number | boolean>[] = [];
  let hits = 0;
  let entries = 0;
  const record = (step: number) => {
    const f = lab.fraction();
    samples.push({
      step,
      y: lab.y,
      vy: lab.vy,
      fraction: f,
      depth: f * drum.height,
      buoyant: buoyantForce(WATER, G, drum.volume * f),
      weight: -lab.gravity.force({ position: { x: 0, y: lab.y }, velocity: { x: 0, y: 0 }, acceleration: { x: 0, y: 0 }, mass }, context).vector.y,
      net: lab.net(),
    });
  };
  record(0);
  for (let k = 1; k <= steps; k += 1) {
    const { hit, entered } = lab.step();
    if (hit) hits += 1;
    if (entered) entries += 1;
    if (k % every === 0) record(k);
  }
  const ratio = floatingSubmergedFraction(density(mass, drum.volume), WATER);
  return {
    name,
    volume: drum.volume,
    height: drum.height,
    displaced_mass: WATER * drum.volume,
    mass,
    centre,
    steps,
    density: density(mass, drum.volume),
    density_ratio: ratio,
    floating_depth: Math.min(1, ratio) * drum.height,
    judgement: ratio < 1 - 1e-9 ? "floats" : ratio > 1 + 1e-9 ? "sinks" : "neutral",
    floor_hits: hits,
    entries,
    samples,
  };
}

/** The web's own stepping of the same law (explicit Euler at 120 Hz): distance from the floating depth after 10 s. */
function webIntegrator(drum: Drum, mass: number, centre: number) {
  const lab = new DrumLab(drum, mass, centre);
  const h = 1 / 120;
  let semiWorst = 0;
  const reference = new DrumLab(drum, mass, centre);
  for (let k = 1; k <= 1200; k += 1) {
    const a = lab.net() / mass;
    lab.y += lab.vy * h;
    lab.vy += a * h;
    if (k % 2 === 0) {
      reference.step();
      semiWorst = Math.max(semiWorst, Math.abs(lab.y - reference.y));
    }
  }
  const settled = WATERLINE - floatingSubmergedFraction(mass, WATER * drum.volume) * drum.height + drum.height / 2;
  return { mass, volume: drum.volume, max_difference_10s: semiWorst, web_distance_from_floating_10s: Math.abs(lab.y - settled), lab_distance_from_floating_10s: Math.abs(reference.y - settled) };
}

const above = (drum: Drum) => WATERLINE + 0.3 + drum.height / 2;

function buildVectors() {
  return {
    source: "src/physics/laws/world-mechanics.ts BuoyancyRegionLaw, gravity.ts UniformGravity, fluid.ts floatingSubmergedFraction, mechanics.ts density / buoyantForce; physics-playground resolveWorldBounds floor rule",
    tolerance: 1e-9,
    step_hz: STEP_HZ,
    substeps: SUBSTEPS,
    g: G,
    water_density: WATER,
    drag: DRAG,
    waterline: WATERLINE,
    floor: FLOOR,
    restitution: RESTITUTION,
    rebound_min: REBOUND_MIN,
    cases: [
      // The lab's start: 100 L drum of 70 kg (rho 700, the web's 1 / 1.45 = 0.69), dropped from 0.3 m above the water.
      buoyancyCase("start", BIG, 70, above(BIG), 600, 6),
      // A light drum floats high.
      buoyancyCase("light", BIG, 20, above(BIG), 600, 6),
      // Denser than water: it sinks to the floor.
      buoyancyCase("heavy", BIG, 150, above(BIG), 600, 6),
      // As dense as water: neutral, never pushed back up.
      buoyancyCase("neutral", BIG, 100, above(BIG), 600, 6),
      // A 50 L drum of the same density as the start floats at the same fraction.
      buoyancyCase("small same density", SMALL, 35, above(SMALL), 600, 6),
      // Pushed to the floor and let go: it rises, jumps out a little and settles.
      buoyancyCase("pushed under", BIG, 70, FLOOR + BIG.height / 2, 600, 6),
      // 60 s of the start: the motion past the graph and history window.
      buoyancyCase("long", BIG, 70, above(BIG), 3600, 30),
    ],
    web_integrator: [webIntegrator(BIG, 20, above(BIG)), webIntegrator(BIG, 70, above(BIG))],
  };
}

describe("buoyancy lab vectors", () => {
  it("match the committed JSON generated from the TS core", () => {
    const vectors = buildVectors();
    if (process.env.UPDATE_BUOYANCY_VECTORS === "1") {
      writeFileSync(vectorsPath, `${JSON.stringify(vectors, null, 2)}\n`);
    }
    const committed = JSON.parse(readFileSync(vectorsPath, "utf8"));
    expect(committed).toEqual(JSON.parse(JSON.stringify(vectors)));
  });

  it("float, sink and stay as Archimedes says", () => {
    const byName = Object.fromEntries(buildVectors().cases.map((c) => [c.name, c]));
    const last = (name: string) => byName[name].samples.at(-1) as Record<string, number>;
    // Floating drums settle where the buoyant force equals the weight, at rho_object / rho_water of
    // their height (the light one bobs longest: the drag acts on its small submerged part only).
    for (const name of ["start", "small same density", "pushed under"]) {
      expect(Math.abs((last(name).depth as number) - byName[name].floating_depth)).toBeLessThan(2e-3);
    }
    expect(Math.abs((last("light").depth as number) - byName.light.floating_depth)).toBeLessThan(0.05);
    expect(Math.abs((last("long").depth as number) - byName.long.floating_depth)).toBeLessThan(1e-9);
    expect(Math.abs((last("long").buoyant as number) - (last("long").weight as number))).toBeLessThan(1e-6);
    expect(byName.start.density_ratio).toBeCloseTo(0.7, 12);
    expect(byName["small same density"].floating_depth / SMALL.height).toBeCloseTo(byName.start.floating_depth / BIG.height, 12);
    // The heavy drum ends on the floor, fully under water.
    expect(last("heavy").y).toBeCloseTo(FLOOR + BIG.height / 2, 12);
    expect(last("heavy").fraction).toBe(1);
    expect(byName.heavy.judgement).toBe("sinks");
    // Neutral: once under water no net force is left but the water's drag.
    expect(byName.neutral.judgement).toBe("neutral");
    expect(Math.abs(last("neutral").net as number)).toBeLessThan(1e-6);
  });

  it("show why the lab does not copy the web's explicit Euler stepping", () => {
    const [light] = buildVectors().web_integrator;
    expect(light.web_distance_from_floating_10s).toBeGreaterThan(0.5);
    expect(light.web_distance_from_floating_10s).toBeGreaterThan(10 * light.lab_distance_from_floating_10s);
  });
});
