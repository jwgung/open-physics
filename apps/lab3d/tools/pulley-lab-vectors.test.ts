// Generates and guards the vectors of the pulley lab (Phase 1 Task 4e, web preset "pulley",
// "도르래 줄이 많으면 얼마나 쉬워질까?"), consumed by apps/lab3d/tests/pulley_lab_checks.gd.
// The law is the web's PulleyAdvantageChallenge (src/app/mechanics-challenges.ts): n = 1, 2, 4
// supporting strands, required force F = m g / n, lift = pull / n (liftDistanceForPull), pull for a
// lift = n lift (pullDistanceForLift). The 3D lab pulls the rope hand over hand in strokes of whole
// 5 cm cells (pull = cells / 20 m), the load stops at 2.4 m (the web's maxLift); work: mechanics.ts
// work (F d_pull) and gravitationalPotentialEnergy (m g d_lift).
// Runs in the root `npm test`. Regenerate: UPDATE_PULLEY_VECTORS=1 npx vitest run apps/lab3d
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { PulleyAdvantageChallenge, type SupportStrands } from "../../../src/app/mechanics-challenges";
import { gravitationalPotentialEnergy, work } from "../../../src/physics/laws/mechanics";

const G = 9.81;
const CELLS_PER_M = 20;
const MAX_LIFT = 2.4;
const vectorsPath = fileURLToPath(new URL("../tests/pulley_lab_vectors.json", import.meta.url));
const playgroundPath = fileURLToPath(new URL("../../../src/app/physics-playground.ts", import.meta.url));

/** Strokes of `strokes` cells each (each cut at the rope left to pull); a sample every `every` cells. */
function pulleyCase(name: string, strands: SupportStrands, mass: number, strokes: number[], every: number) {
  const challenge = new PulleyAdvantageChallenge({ loadMass: mass, gravity: G, supportStrands: strands });
  const ropeCells = Math.round(challenge.pullDistanceForLift(MAX_LIFT) * CELLS_PER_M);
  let before = 0;
  const samples = [];
  for (const [s, wanted] of strokes.entries()) {
    const limit = Math.max(0, ropeCells - before);
    const cells = Math.min(wanted, limit);
    for (let k = 0; k <= cells; k += 1) {
      if (k % every !== 0 && k !== cells) continue;
      const pulled = (before + k) / CELLS_PER_M;
      const lift = Math.min(MAX_LIFT, challenge.liftDistanceForPull(pulled));
      samples.push({
        stroke: s,
        cells: k,
        limit,
        pulled,
        lift,
        work_in: work({ x: challenge.requiredForce, y: 0 }, { x: pulled, y: 0 }),
        work_out: gravitationalPotentialEnergy(mass, G, lift),
      });
    }
    before += cells;
  }
  return {
    name,
    strands,
    mass,
    strokes,
    required: challenge.requiredForce,
    pull_per_metre: challenge.pullDistanceForLift(1),
    weight: mass * G,
    samples,
  };
}

function buildVectors() {
  return {
    source: "src/app/mechanics-challenges.ts PulleyAdvantageChallenge, src/physics/laws/mechanics.ts work / gravitationalPotentialEnergy",
    tolerance: 1e-9,
    g: G,
    cells_per_m: CELLS_PER_M,
    max_lift: MAX_LIFT,
    cases: [
      // The lab's start: the web's 20 kg on one strand; full strokes of 2.6 m until the top.
      pulleyCase("one", 1, 20, [52, 52], 2),
      pulleyCase("two", 2, 20, [52, 52, 52], 2),
      pulleyCase("four", 4, 20, [52, 52, 52, 52, 52], 2),
      // Short strokes of a lighter load: the same 1 m of rope lifts 1 / n m.
      pulleyCase("light short", 4, 7, [20, 20, 7], 1),
      pulleyCase("two short", 2, 7, [20, 13], 1),
    ],
  };
}

describe("pulley lab vectors", () => {
  it("use the web's 20 kg load and 1 / 2 / 4 strands", () => {
    const source = readFileSync(playgroundPath, "utf8");
    expect(source).toMatch(/label: "들어 올릴 짐",[^}]*mass: 20,/);
    expect(source).toMatch(/for \(const \[index, strands\] of \(\[1, 2, 4\] as SupportStrands\[\]\)\.entries\(\)\)/);
  });

  it("match the committed JSON generated from the TS core", () => {
    const vectors = buildVectors();
    if (process.env.UPDATE_PULLEY_VECTORS === "1") {
      writeFileSync(vectorsPath, `${JSON.stringify(vectors, null, 2)}\n`);
    }
    const committed = JSON.parse(readFileSync(vectorsPath, "utf8"));
    expect(committed).toEqual(JSON.parse(JSON.stringify(vectors)));
  });

  it("trade force for rope: F n = m g, pull = n lift, and the hand's work = the load's energy", () => {
    for (const run of buildVectors().cases) {
      expect(Math.abs(run.required * run.strands - run.weight)).toBeLessThan(1e-12 * run.weight);
      expect(run.pull_per_metre).toBe(run.strands);
      for (const s of run.samples) {
        expect(Math.abs(s.pulled - s.lift * run.strands)).toBeLessThan(1e-12);
        expect(Math.abs(s.work_in - s.work_out)).toBeLessThan(1e-9 * Math.max(1, s.work_out));
      }
      const last = run.samples[run.samples.length - 1];
      if (run.strokes.reduce((a, b) => a + b, 0) >= run.strands * MAX_LIFT * CELLS_PER_M) expect(last.lift).toBe(MAX_LIFT);
    }
  });
});
