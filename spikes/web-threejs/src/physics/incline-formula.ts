/**
 * Incline friction readout computed only from the existing TS formula core.
 * Everything shown on screen in S3 comes from here, never from Rapier.
 *
 * 1D slope frame: +s points downhill along the incline surface.
 */
import { accelerationFromForce, type BodyState } from "../../../../src/physics/core";
import { KineticFriction } from "../../../../src/physics/laws/basic";
import { constantAccelerationDisplacement } from "../../../../src/physics/laws/mechanics";

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
 * Friction force (signed, along +s downhill) the correction layer must apply this step,
 * following the same static/kinetic rule as the product core.
 */
export function frictionForceAlongSlope(
  readout: InclineReadout,
  kineticCoefficient: number,
  slopeSpeed: number,
  mass: number,
  dt: number,
): number {
  const tangential = readout.tangentialGravity;
  if (Math.abs(slopeSpeed) < REST_SPEED && Math.abs(tangential) <= readout.maxStaticFriction) {
    return -tangential;
  }
  const direction = Math.abs(slopeSpeed) >= REST_SPEED ? Math.sign(slopeSpeed) : Math.sign(tangential);
  let friction = -direction * kineticFrictionMagnitude(readout.normalForce, kineticCoefficient, slopeSpeed);
  if (Math.abs(slopeSpeed) >= REST_SPEED) {
    const nextSpeed = slopeSpeed + (tangential + friction) / mass * dt;
    if (slopeSpeed * nextSpeed <= 0) friction = -mass * slopeSpeed / dt - tangential;
  }
  return friction;
}
