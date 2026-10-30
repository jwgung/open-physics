import { describe, expect, it } from "vitest";
import { LeverChallenge, OrbitChallenge, PulleyAdvantageChallenge } from "./mechanics-challenges";

describe("LeverChallenge", () => {
  it("requires less effort when the handle is farther from the pivot", () => {
    const lever = new LeverChallenge({ loadMass: 20, gravity: 9.81, loadArm: 80, effortArm: 80 });
    const nearForce = lever.requiredForce;

    lever.setEffortArm(200);

    expect(lever.requiredForce).toBeCloseTo(nearForce * 0.4);
    expect(lever.mechanicalAdvantage).toBeCloseTo(2.5);
  });

  it("lifts only after the applied effort reaches the required force", () => {
    const lever = new LeverChallenge({ loadMass: 10, gravity: 10, loadArm: 80, effortArm: 200 });

    expect(lever.applyForce(39).lifting).toBe(false);
    expect(lever.applyForce(40).lifting).toBe(true);
  });
});

describe("PulleyAdvantageChallenge", () => {
  it("trades pulling distance for reduced force", () => {
    const pulley = new PulleyAdvantageChallenge({ loadMass: 20, gravity: 10 });

    expect(pulley.requiredForce).toBe(200);
    pulley.setSupportStrands(2);
    expect(pulley.requiredForce).toBe(100);
    expect(pulley.pullDistanceForLift(30)).toBe(60);
    pulley.setSupportStrands(4);
    expect(pulley.requiredForce).toBe(50);
    expect(pulley.pullDistanceForLift(30)).toBe(120);
  });
});

describe("OrbitChallenge", () => {
  const orbit = new OrbitChallenge({ center: { x: 0, y: 0 }, gravitationalParameter: 10_000, collisionRadius: 20 });

  it("distinguishes a circular orbit from escape speed", () => {
    expect(orbit.analyze({ x: 100, y: 0 }, { x: 0, y: 10 }).outcome).toBe("orbit");
    expect(orbit.analyze({ x: 100, y: 0 }, { x: 0, y: 15 }).outcome).toBe("escape");
  });

  it("detects a path aimed into the central body", () => {
    const result = orbit.analyze({ x: 100, y: 0 }, { x: -12, y: 0 });

    expect(result.outcome).toBe("crash");
    expect(result.path.length).toBeGreaterThan(2);
  });

  it("keeps comparison speeds finite even when the launch starts inside the planet", () => {
    const result = orbit.analyze({ x: 0, y: 0 }, { x: 0, y: 0 });

    expect(result.outcome).toBe("crash");
    expect(result.circularSpeed).toBeTypeOf("number");
    expect(Number.isFinite(result.circularSpeed)).toBe(true);
    expect(Number.isFinite(result.escapeSpeed)).toBe(true);
  });
});
