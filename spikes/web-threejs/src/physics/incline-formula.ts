/**
 * Incline friction readout computed only from the existing TS formula core.
 * Everything shown on screen in S3 comes from here, never from Rapier.
 *
 * 1D slope frame: +s points downhill along the incline surface.
 */
import { accelerationFromForce, type BodyState } from "../../../../src/physics/core";
import { KineticFriction } from "../../../../src/physics/laws/basic";
import { constantAccelerationDisplacement } from "../../../../src/physics/laws/mechanics";
import { SurfaceContactFrictionModifier } from "../../../../src/physics/laws/world-mechanics";
import type { Body } from "../../../../src/physics/world";

export interface InclineParams {
  mass: number;
  gravity: number;
  staticCoefficient: number;
  kineticCoefficient: number;
  angleRad: number;
}

export interface InclineReadout {
  angleDeg: number;
  /** m g sinθ, downhill (N). */
  tangentialGravity: number;
  /** m g cosθ (N). */
  normalForce: number;
  /** μs N (N). */
  maxStaticFriction: number;
  /** atan(μs) (deg). */
  criticalAngleDeg: number;
  /** Whether a body at rest stays at rest. */
  holdsAtRest: boolean;
  /** Downhill acceleration while sliding, g(sinθ − μk cosθ), 0 if it holds (m/s²). */
  slidingAcceleration: number;
}

/** Same threshold the product core uses for "at rest" (SurfaceContactFrictionModifier). */
export const REST_SPEED = 0.01;

export const S3_PARAMS: Readonly<Omit<InclineParams, "angleRad">> = Object.freeze({
  mass: 1,
  gravity: 9.81,
  staticCoefficient: 0.5,
  kineticCoefficient: 0.4,
});

const degrees = (rad: number): number => rad * 180 / Math.PI;

export const kineticFrictionMagnitude = (normalForce: number, coefficient: number, slopeSpeed: number): number => {
  const state: BodyState = {
    position: { x: 0, y: 0 },
    velocity: { x: slopeSpeed === 0 ? 1 : slopeSpeed, y: 0 },
    acceleration: { x: 0, y: 0 },
    mass: 1,
  };
  const friction = new KineticFriction(normalForce, coefficient).force(state, { time: 0, dt: 0 });
  return Math.abs(friction.vector.x);
};

export function inclineReadout(params: InclineParams): InclineReadout {
  const { mass, gravity, staticCoefficient, kineticCoefficient, angleRad } = params;
  const tangentialGravity = mass * gravity * Math.sin(angleRad);
  const normalForce = mass * gravity * Math.cos(angleRad);
  const maxStaticFriction = staticCoefficient * normalForce;
  const holdsAtRest = tangentialGravity <= maxStaticFriction;
  const kinetic = kineticFrictionMagnitude(normalForce, kineticCoefficient, 1);
  const net = { vector: { x: tangentialGravity - kinetic, y: 0 } };
  const slidingAcceleration = holdsAtRest ? 0 : Math.max(0, accelerationFromForce(net, mass).x);
  return {
    angleDeg: degrees(angleRad),
    tangentialGravity,
    normalForce,
    maxStaticFriction,
    criticalAngleDeg: degrees(Math.atan(staticCoefficient)),
    holdsAtRest,
    slidingAcceleration,
  };
}

/** Expected distance from rest after t seconds of sliding: s = ½at². */
export const expectedDistance = (acceleration: number, seconds: number): number =>
  constantAccelerationDisplacement({ x: 0, y: 0 }, { x: acceleration, y: 0 }, seconds).x;

/**
 * Friction force (signed, along +s downhill) the correction layer must apply this step.
 * Delegates to the product core's SurfaceContactFrictionModifier on an equivalent 2D ramp,
 * so the static/kinetic rule, rest threshold and reversal clamp stay identical to the core.
 */
export function frictionForceAlongSlope(
  readout: InclineReadout,
  params: Readonly<Omit<InclineParams, "angleRad">>,
  slopeSpeed: number,
  dt: number,
): number {
  const { mass, gravity, staticCoefficient, kineticCoefficient } = params;
  // Core convention: +y points down; tilting the ramp by -θ makes (-cos, -sin) of that angle the downhill direction.
  const angle = -readout.angleDeg * Math.PI / 180;
  const downhill = { x: -Math.cos(angle), y: -Math.sin(angle) };
  const body: Body = {
    id: "box",
    radius: 10,
    staticFriction: staticCoefficient,
    kineticFriction: kineticCoefficient,
    state: {
      position: { x: 50 + Math.sin(angle) * 15, y: 100 - Math.cos(angle) * 15 },
      velocity: { x: downhill.x * slopeSpeed, y: downhill.y * slopeSpeed },
      acceleration: { x: 0, y: 0 },
      mass,
    },
  };
  const ramp: Body = {
    id: "ramp",
    collider: { kind: "box", halfWidth: 50, halfHeight: 5, angle },
    staticFriction: staticCoefficient,
    kineticFriction: kineticCoefficient,
    fixed: true,
    state: { position: { x: 50, y: 100 }, velocity: { x: 0, y: 0 }, acceleration: { x: 0, y: 0 }, mass: 1 },
  };
  const modifier = new SurfaceContactFrictionModifier({ floorY: 1e6, normalAcceleration: gravity });
  const result = modifier.modifyForce(body, [body, ramp], { vector: { x: 0, y: mass * gravity } }, { time: 0, dt });
  const netAlongSlope = result.vector.x * downhill.x + result.vector.y * downhill.y;
  return netAlongSlope - readout.tangentialGravity;
}
