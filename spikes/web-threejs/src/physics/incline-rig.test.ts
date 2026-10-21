import RAPIER from "@dimforge/rapier3d-compat";
import { beforeAll, describe, expect, it } from "vitest";
import { expectedDistance, inclineReadout, S3_PARAMS } from "./incline-formula";
import { FIXED_DT, InclineRig } from "./incline-rig";

const stepsFor = (seconds: number): number => Math.round(seconds / FIXED_DT);
const rad = (deg: number): number => deg * Math.PI / 180;

/** Runs until slideTime reaches t and returns the downhill distance since release. */
const distanceAtSlideTime = (rig: InclineRig, seconds: number): number => {
  while ((rig.slideTime ?? 0) < seconds - FIXED_DT / 2) rig.step();
  return rig.sample().distance;
};

describe("S3 incline formula readout (spec §4)", () => {
  it("critical angle is atan(μs) = 26.565°", () => {
    expect(inclineReadout({ ...S3_PARAMS, angleRad: rad(30) }).criticalAngleDeg).toBeCloseTo(26.565, 3);
  });

  it("displays a = g(sinθ − μk cosθ) = 2.412 m/s² at 35°", () => {
    const a = inclineReadout({ ...S3_PARAMS, angleRad: rad(35) }).slidingAcceleration;
    expect(a).toBeCloseTo(9.81 * (Math.sin(rad(35)) - 0.4 * Math.cos(rad(35))), 12);
    expect(a).toBeCloseTo(2.412, 3);
    expect(expectedDistance(a, 1)).toBeCloseTo(1.206, 3);
    expect(expectedDistance(a, 2)).toBeCloseTo(4.825, 3);
  });
});

describe("S3 Rapier + correction layer, engine fixed timestep (spec §4)", () => {
  beforeAll(async () => { await RAPIER.init(); });

  it("26.0°: holds still", () => {
    const rig = new InclineRig(RAPIER, 26);
    for (let i = 0; i < stepsFor(3); i += 1) rig.step();
    const sample = rig.sample();
    rig.dispose();
    expect(sample.phase).toBe("holding");
    expect(sample.slideTime).toBeNull();
    expect(sample.drift).toBeLessThanOrEqual(0.001);
  });

  it("27.0°: starts sliding within 1 s", () => {
    const rig = new InclineRig(RAPIER, 27);
    for (let i = 0; i < stepsFor(1); i += 1) rig.step();
    const sample = rig.sample();
    rig.dispose();
    expect(sample.phase).toBe("sliding");
    expect(sample.distance).toBeGreaterThan(0.01);
  });

  it("35°: measured s(1s), s(2s) and a within ±1 %", () => {
    const rig = new InclineRig(RAPIER, 35);
    const a = rig.readout.slidingAcceleration;
    const s1 = distanceAtSlideTime(rig, 1);
    const v1 = rig.sample().speed;
    const s2 = distanceAtSlideTime(rig, 2);
    const v2 = rig.sample().speed;
    rig.dispose();
    const measuredA = (v2 - v1) / 1;
    console.info(`[S3] a=${a.toFixed(4)} measuredA=${measuredA.toFixed(4)} s1=${s1.toFixed(4)} s2=${s2.toFixed(4)}`);
    expect(Math.abs(s1 - 1.206) / 1.206).toBeLessThanOrEqual(0.01);
    expect(Math.abs(s2 - 4.825) / 4.825).toBeLessThanOrEqual(0.01);
    expect(Math.abs(measuredA - 2.412) / 2.412).toBeLessThanOrEqual(0.01);
  });

  it("20°: drift ≤ 1 mm over 10 s", () => {
    const rig = new InclineRig(RAPIER, 20);
    for (let i = 0; i < stepsFor(10); i += 1) rig.step();
    const sample = rig.sample();
    rig.dispose();
    console.info(`[S3] drift20=${(sample.drift * 1000).toFixed(4)}mm`);
    expect(sample.drift).toBeLessThanOrEqual(0.001);
  });
});

describe("S3 without correction (baseline, documents why the layer exists)", () => {
  beforeAll(async () => { await RAPIER.init(); });

  it("Rapier with friction 0 and no layer slides at 20°", () => {
    const rig = new InclineRig(RAPIER, 20);
    for (let i = 0; i < stepsFor(1); i += 1) rig.world.step();
    const drift = rig.sample().drift;
    rig.dispose();
    expect(drift).toBeGreaterThan(0.5);
  });
});
