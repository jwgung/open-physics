import { describe, expect, it } from "vitest";
import {
  CircularMotionModel,
  PendulumModel,
  PulleyModel,
  RotationBalanceModel,
} from "./mechanics-scenes";

describe("CircularMotionModel", () => {
  it("keeps the object on its circle with inward acceleration", () => {
    const model = new CircularMotionModel({ x: 100, y: 100 }, 50, 2);
    model.step(Math.PI / 4);
    const pose = model.pose();

    expect(Math.hypot(pose.position.x - 100, pose.position.y - 100)).toBeCloseTo(50);
    expect(pose.position.x).toBeCloseTo(100);
    expect(pose.acceleration.y).toBeLessThan(0);
  });
});

describe("PendulumModel", () => {
  it("accelerates a displaced bob back toward the lowest point", () => {
    const model = new PendulumModel({ x: 0, y: 0 }, 100, Math.PI / 4);
    model.step(0.1, 980);

    expect(model.angularAcceleration).toBeLessThan(0);
    expect(model.angularVelocity).toBeLessThan(0);
    expect(Math.hypot(model.pose().position.x, model.pose().position.y)).toBeCloseTo(100);
  });
});

describe("RotationBalanceModel", () => {
  it("rotates toward the heavier side according to torque", () => {
    const model = new RotationBalanceModel({ x: 0, y: 0 }, 100, 0);
    model.step(0.1, 980, 1, 3);

    expect(model.angularAcceleration).toBeGreaterThan(0);
    expect(model.poses().right.position.y).toBeGreaterThan(0);
  });
});

describe("PulleyModel", () => {
  it("moves the heavier weight down while the other rises equally", () => {
    const model = new PulleyModel({ x: 100, y: 50 }, 30, 100, 60);
    model.step(0.1, 980, 1, 3);
    const poses = model.poses();

    expect(model.acceleration).toBeGreaterThan(0);
    expect(poses.right.position.y - 150).toBeCloseTo(-(poses.left.position.y - 150));
    expect(poses.right.velocity.y).toBeGreaterThan(0);
  });
});
