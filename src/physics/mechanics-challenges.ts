import type { Vector2 } from "./core";

const requirePositive = (label: string, value: number): number => {
  if (!Number.isFinite(value) || value <= 0) throw new RangeError(`${label} must be greater than zero.`);
  return value;
};

export interface LeverChallengeOptions {
  loadMass: number;
  gravity: number;
  loadArm: number;
  effortArm: number;
}

export interface LeverAttempt {
  appliedForce: number;
  requiredForce: number;
  lifting: boolean;
}

/** Torque balance for a learner-controlled lever. */
export class LeverChallenge {
  loadMass: number;
  gravity: number;
  loadArm: number;
  effortArm: number;

  constructor(options: LeverChallengeOptions) {
    this.loadMass = requirePositive("Load mass", options.loadMass);
    this.gravity = requirePositive("Gravity", options.gravity);
    this.loadArm = requirePositive("Load arm", options.loadArm);
    this.effortArm = requirePositive("Effort arm", options.effortArm);
  }

  get requiredForce(): number {
    return this.loadMass * this.gravity * this.loadArm / this.effortArm;
  }

  get mechanicalAdvantage(): number {
    return this.effortArm / this.loadArm;
  }

  setEffortArm(value: number): void { this.effortArm = requirePositive("Effort arm", value); }
  setLoadArm(value: number): void { this.loadArm = requirePositive("Load arm", value); }
  setLoadMass(value: number): void { this.loadMass = requirePositive("Load mass", value); }
  setGravity(value: number): void { this.gravity = requirePositive("Gravity", value); }

  applyForce(force: number): LeverAttempt {
    if (!Number.isFinite(force)) throw new RangeError("Applied force must be finite.");
    const appliedForce = Math.max(0, force);
    return {
      appliedForce,
      requiredForce: this.requiredForce,
      lifting: appliedForce >= this.requiredForce,
    };
  }
}

export type SupportStrands = 1 | 2 | 4;

export interface PulleyAdvantageOptions {
  loadMass: number;
  gravity: number;
  supportStrands?: SupportStrands;
}

/** Ideal pulley trade-off: more supporting strands need less force but more rope travel. */
export class PulleyAdvantageChallenge {
  loadMass: number;
  gravity: number;
  supportStrands: SupportStrands;

  constructor(options: PulleyAdvantageOptions) {
    this.loadMass = requirePositive("Load mass", options.loadMass);
    this.gravity = requirePositive("Gravity", options.gravity);
    this.supportStrands = options.supportStrands ?? 1;
    this.validateSupportStrands(this.supportStrands);
  }

  get requiredForce(): number {
    return this.loadMass * this.gravity / this.supportStrands;
  }

  setSupportStrands(value: SupportStrands): void {
    this.validateSupportStrands(value);
    this.supportStrands = value;
  }

  setLoadMass(value: number): void { this.loadMass = requirePositive("Load mass", value); }
  setGravity(value: number): void { this.gravity = requirePositive("Gravity", value); }

  pullDistanceForLift(liftDistance: number): number {
    if (!Number.isFinite(liftDistance) || liftDistance < 0) {
      throw new RangeError("Lift distance must be non-negative.");
    }
    return liftDistance * this.supportStrands;
  }

  liftDistanceForPull(pullDistance: number): number {
    if (!Number.isFinite(pullDistance) || pullDistance < 0) {
      throw new RangeError("Pull distance must be non-negative.");
    }
    return pullDistance / this.supportStrands;
  }

  private validateSupportStrands(value: number): asserts value is SupportStrands {
    if (value !== 1 && value !== 2 && value !== 4) {
      throw new RangeError("Supporting strands must be 1, 2, or 4.");
    }
  }
}

export type OrbitOutcome = "crash" | "orbit" | "escape";

export interface OrbitChallengeOptions {
  center: Vector2;
  gravitationalParameter: number;
  collisionRadius: number;
}

export interface OrbitAnalysis {
  outcome: OrbitOutcome;
  path: Vector2[];
  speed: number;
  circularSpeed: number;
  escapeSpeed: number;
}

/** Predicts whether a launch will hit the planet, remain bound, or escape. */
export class OrbitChallenge {
  center: Vector2;
  gravitationalParameter: number;
  collisionRadius: number;

  constructor(options: OrbitChallengeOptions) {
    this.center = { ...options.center };
    this.gravitationalParameter = requirePositive("Gravitational parameter", options.gravitationalParameter);
    this.collisionRadius = requirePositive("Collision radius", options.collisionRadius);
  }

  analyze(position: Vector2, velocity: Vector2): OrbitAnalysis {
    const relativeX = position.x - this.center.x;
    const relativeY = position.y - this.center.y;
    const radius = Math.hypot(relativeX, relativeY);
    if (radius <= this.collisionRadius) return this.result("crash", [position], radius, velocity);

    const path: Vector2[] = [{ ...position }];
    const simulatedPosition = { ...position };
    const simulatedVelocity = { ...velocity };
    const initialEnergy = this.specificEnergy(radius, velocity);
    const dt = Math.max(0.02, Math.min(0.12, radius / Math.max(Math.hypot(velocity.x, velocity.y), 1) / 140));

    for (let step = 0; step < 1_200; step += 1) {
      const dx = simulatedPosition.x - this.center.x;
      const dy = simulatedPosition.y - this.center.y;
      const distance = Math.hypot(dx, dy);
      const accelerationScale = -this.gravitationalParameter / (distance * distance * distance);
      simulatedVelocity.x += dx * accelerationScale * dt;
      simulatedVelocity.y += dy * accelerationScale * dt;
      simulatedPosition.x += simulatedVelocity.x * dt;
      simulatedPosition.y += simulatedVelocity.y * dt;
      if (step % 3 === 0) path.push({ ...simulatedPosition });

      const nextDistance = Math.hypot(
        simulatedPosition.x - this.center.x,
        simulatedPosition.y - this.center.y,
      );
      if (nextDistance <= this.collisionRadius) {
        path.push({ ...simulatedPosition });
        return this.result("crash", path, radius, velocity);
      }
      if (initialEnergy >= 0 && nextDistance > radius * 4) {
        return this.result("escape", path, radius, velocity);
      }
    }

    return this.result(initialEnergy >= 0 ? "escape" : "orbit", path, radius, velocity);
  }

  private specificEnergy(radius: number, velocity: Vector2): number {
    return (velocity.x * velocity.x + velocity.y * velocity.y) / 2
      - this.gravitationalParameter / radius;
  }

  private result(outcome: OrbitOutcome, path: Vector2[], radius: number, velocity: Vector2): OrbitAnalysis {
    const safeRadius = Math.max(radius, this.collisionRadius);
    return {
      outcome,
      path,
      speed: Math.hypot(velocity.x, velocity.y),
      circularSpeed: Math.sqrt(this.gravitationalParameter / safeRadius),
      escapeSpeed: Math.sqrt(2 * this.gravitationalParameter / safeRadius),
    };
  }
}
