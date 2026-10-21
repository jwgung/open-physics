/**
 * S3 rig: Rapier incline + box with a formula correction layer.
 *
 * Rapier has a single Coulomb friction coefficient and no static/kinetic split.
 * The correction layer sets Rapier friction to 0 on both colliders and, every fixed
 * step, applies the friction force the formula core prescribes along the slope:
 * - holding (|v| < 0.01 and mg·sinθ ≤ μs·N): friction cancels the tangential gravity
 * - sliding: friction = μk·N opposite to motion (with the core's reversal clamp)
 * Rapier still integrates the motion and resolves the normal contact.
 *
 * No integrator correction is applied. Rapier's substepped solver (4 solver iterations
 * per 1/60 s step) integrates constant acceleration with ≈+0.4 % distance error at t=1 s
 * and ≈+0.2 % at t=2 s (see incline-rig.test.ts), inside the ±1 % budget.
 */
import type RAPIER_NS from "@dimforge/rapier3d-compat";
import {
  frictionForceAlongSlope,
  inclineReadout,
  REST_SPEED,
  S3_PARAMS,
  type InclineReadout,
} from "./incline-formula";

type Rapier = typeof RAPIER_NS;
type Vec3 = { x: number; y: number; z: number };

export const FIXED_DT = 1 / 60;
export const PLANK_HALF = { x: 4, y: 0.1, z: 1 } as const;
export const BOX_HALF = 0.25;
/** Box start distance up the slope from the plank centre (m). */
const START_UPHILL = 3;

export type InclinePhase = "holding" | "sliding";

export interface InclineSample {
  /** Engine time since the rig was (re)placed (s). */
  time: number;
  /** Engine time since sliding started, or null while it never slid (s). */
  slideTime: number | null;
  /** Downhill displacement from the start point (m), measured from Rapier. */
  distance: number;
  /** Total 3D displacement magnitude from the start point (m), measured from Rapier. */
  drift: number;
  /** Downhill speed (m/s), measured from Rapier. */
  speed: number;
  phase: InclinePhase;
}

const dot = (a: Vec3, b: Vec3): number => a.x * b.x + a.y * b.y + a.z * b.z;

export class InclineRig {
  readonly world: RAPIER_NS.World;
  readonly plank: RAPIER_NS.RigidBody;
  readonly box: RAPIER_NS.RigidBody;
  readout!: InclineReadout;
  phase: InclinePhase = "holding";
  time = 0;
  slideTime: number | null = null;
  /** Number of fixed steps where the correction layer ran (for cost reporting). */
  correctionSteps = 0;
  private angleRad = 0;
  private start: Vec3 = { x: 0, y: 0, z: 0 };
  private downhill: Vec3 = { x: -1, y: 0, z: 0 };

  constructor(private readonly rapier: Rapier, angleDeg: number) {
    this.world = new rapier.World({ x: 0, y: -S3_PARAMS.gravity, z: 0 });
    this.world.timestep = FIXED_DT;
    this.plank = this.world.createRigidBody(rapier.RigidBodyDesc.fixed());
    this.world.createCollider(
      rapier.ColliderDesc.cuboid(PLANK_HALF.x, PLANK_HALF.y, PLANK_HALF.z)
        .setFriction(0)
        .setFrictionCombineRule(rapier.CoefficientCombineRule.Min)
        .setRestitution(0)
        .setRestitutionCombineRule(rapier.CoefficientCombineRule.Min),
      this.plank,
    );
    this.box = this.world.createRigidBody(
      rapier.RigidBodyDesc.dynamic().enabledRotations(false, false, false).setCanSleep(false),
    );
    this.world.createCollider(
      rapier.ColliderDesc.cuboid(BOX_HALF, BOX_HALF, BOX_HALF)
        .setMass(S3_PARAMS.mass)
        .setFriction(0)
        .setFrictionCombineRule(rapier.CoefficientCombineRule.Min)
        .setRestitution(0),
      this.box,
    );
    this.setAngle(angleDeg);
  }

  get angleDeg(): number { return this.angleRad * 180 / Math.PI; }

  /** Rotates the incline and puts the box back at rest at the start point. */
  setAngle(angleDeg: number): void {
    this.angleRad = angleDeg * Math.PI / 180;
    const c = Math.cos(this.angleRad);
    const s = Math.sin(this.angleRad);
    const half = this.angleRad / 2;
    this.plank.setRotation({ x: 0, y: 0, z: Math.sin(half), w: Math.cos(half) }, true);
    this.plank.setTranslation({ x: 0, y: 0, z: 0 }, true);
    const uphill = { x: c, y: s, z: 0 };
    const normal = { x: -s, y: c, z: 0 };
    this.downhill = { x: -c, y: -s, z: 0 };
    const lift = PLANK_HALF.y + BOX_HALF;
    this.start = {
      x: uphill.x * START_UPHILL + normal.x * lift,
      y: uphill.y * START_UPHILL + normal.y * lift,
      z: 0,
    };
    this.box.setTranslation(this.start, true);
    this.box.setRotation({ x: 0, y: 0, z: Math.sin(half), w: Math.cos(half) }, true);
    this.box.setLinvel({ x: 0, y: 0, z: 0 }, true);
    this.box.resetForces(true);
    this.readout = inclineReadout({ ...S3_PARAMS, angleRad: this.angleRad });
    this.phase = "holding";
    this.time = 0;
    this.slideTime = null;
    this.world.step();
    // The settle step above must not count as experiment time: restore the start pose.
    this.box.setTranslation(this.start, true);
    this.box.setLinvel({ x: 0, y: 0, z: 0 }, true);
  }

  /** Advances one fixed step with the correction layer. */
  step(): void {
    const speed = dot(this.box.linvel(), this.downhill);
    const friction = frictionForceAlongSlope(this.readout, S3_PARAMS, speed, FIXED_DT);
    const holding = Math.abs(speed) < REST_SPEED && Math.abs(friction + this.readout.tangentialGravity) < 1e-9;
    const slopeForce = friction;
    if (!holding && this.phase === "holding") this.slideTime = 0;
    this.phase = holding ? "holding" : "sliding";
    this.box.resetForces(true);
    this.box.addForce({
      x: this.downhill.x * slopeForce,
      y: this.downhill.y * slopeForce,
      z: this.downhill.z * slopeForce,
    }, true);
    this.correctionSteps += 1;
    this.world.step();
    this.time += FIXED_DT;
    if (this.slideTime !== null) this.slideTime += FIXED_DT;
  }

  sample(): InclineSample {
    const p = this.box.translation();
    const delta = { x: p.x - this.start.x, y: p.y - this.start.y, z: p.z - this.start.z };
    return {
      time: this.time,
      slideTime: this.slideTime,
      distance: dot(delta, this.downhill),
      drift: Math.hypot(delta.x, delta.y, delta.z),
      speed: dot(this.box.linvel(), this.downhill),
      phase: this.phase,
    };
  }

  /** True once the box has slid off the plank's lower end. */
  get finished(): boolean {
    return this.sample().distance > START_UPHILL + PLANK_HALF.x - BOX_HALF;
  }

  dispose(): void {
    this.world.free();
  }
}
