import type { Vector2 } from "./core";

export interface KinematicPose {
  position: Vector2;
  velocity: Vector2;
  acceleration: Vector2;
}

export class CircularMotionModel {
  constructor(
    public center: Vector2,
    public radius: number,
    public angularSpeed: number,
    public angle = 0,
  ) {}

  step(dt: number): void { this.angle += this.angularSpeed * dt; }

  pose(): KinematicPose {
    const cos = Math.cos(this.angle);
    const sin = Math.sin(this.angle);
    return {
      position: { x: this.center.x + this.radius * cos, y: this.center.y + this.radius * sin },
      velocity: {
        x: -this.angularSpeed * this.radius * sin,
        y: this.angularSpeed * this.radius * cos,
      },
      acceleration: {
        x: -(this.angularSpeed ** 2) * this.radius * cos,
        y: -(this.angularSpeed ** 2) * this.radius * sin,
      },
    };
  }

  moveTo(point: Vector2): void {
    this.angle = Math.atan2(point.y - this.center.y, point.x - this.center.x);
  }

  resize(scaleX: number, scaleY: number): void {
    this.center = { x: this.center.x * scaleX, y: this.center.y * scaleY };
    this.radius *= Math.min(scaleX, scaleY);
  }
}

export class PendulumModel {
  angularVelocity = 0;
  angularAcceleration = 0;

  constructor(
    public anchor: Vector2,
    public length: number,
    public angle: number,
    public damping = 0.08,
  ) {}

  step(dt: number, gravityAcceleration: number): void {
    this.angularAcceleration = -(gravityAcceleration / this.length) * Math.sin(this.angle)
      - this.damping * this.angularVelocity;
    this.angularVelocity += this.angularAcceleration * dt;
    this.angle += this.angularVelocity * dt;
  }

  pose(): KinematicPose {
    const sin = Math.sin(this.angle);
    const cos = Math.cos(this.angle);
    return {
      position: { x: this.anchor.x + this.length * sin, y: this.anchor.y + this.length * cos },
      velocity: {
        x: this.length * cos * this.angularVelocity,
        y: -this.length * sin * this.angularVelocity,
      },
      acceleration: {
        x: this.length * (-sin * this.angularVelocity ** 2 + cos * this.angularAcceleration),
        y: this.length * (-cos * this.angularVelocity ** 2 - sin * this.angularAcceleration),
      },
    };
  }

  moveTo(point: Vector2): void {
    this.angle = Math.atan2(point.x - this.anchor.x, point.y - this.anchor.y);
    this.angularVelocity = 0;
    this.angularAcceleration = 0;
  }

  resize(scaleX: number, scaleY: number): void {
    this.anchor = { x: this.anchor.x * scaleX, y: this.anchor.y * scaleY };
    this.length *= Math.min(scaleX, scaleY);
  }
}

export class RotationBalanceModel {
  angularVelocity = 0;
  angularAcceleration = 0;

  constructor(
    public center: Vector2,
    public halfLength: number,
    public angle = -0.12,
    public damping = 0.45,
  ) {}

  step(dt: number, gravityAcceleration: number, leftMass: number, rightMass: number): void {
    const torque = (rightMass - leftMass) * gravityAcceleration * this.halfLength * Math.cos(this.angle);
    const momentOfInertia = Math.max(0.001, (leftMass + rightMass) * this.halfLength ** 2);
    this.angularAcceleration = torque / momentOfInertia - this.damping * this.angularVelocity;
    this.angularVelocity += this.angularAcceleration * dt;
    this.angle += this.angularVelocity * dt;
  }

  poses(): { left: KinematicPose; right: KinematicPose } {
    const cos = Math.cos(this.angle);
    const sin = Math.sin(this.angle);
    const endpoint = (side: -1 | 1): KinematicPose => ({
      position: {
        x: this.center.x + side * this.halfLength * cos,
        y: this.center.y + side * this.halfLength * sin,
      },
      velocity: {
        x: -side * this.halfLength * sin * this.angularVelocity,
        y: side * this.halfLength * cos * this.angularVelocity,
      },
      acceleration: {
        x: side * this.halfLength * (
          -cos * this.angularVelocity ** 2 - sin * this.angularAcceleration
        ),
        y: side * this.halfLength * (
          -sin * this.angularVelocity ** 2 + cos * this.angularAcceleration
        ),
      },
    });
    return { left: endpoint(-1), right: endpoint(1) };
  }

  moveEndpoint(side: -1 | 1, point: Vector2): void {
    const angle = Math.atan2(point.y - this.center.y, point.x - this.center.x);
    this.angle = side === 1 ? angle : angle + Math.PI;
    this.angularVelocity = 0;
    this.angularAcceleration = 0;
  }

  resize(scaleX: number, scaleY: number): void {
    this.center = { x: this.center.x * scaleX, y: this.center.y * scaleY };
    this.halfLength *= Math.min(scaleX, scaleY);
  }
}

export class PulleyModel {
  offset = 0;
  velocity = 0;
  acceleration = 0;
  wheelAngle = 0;

  constructor(
    public center: Vector2,
    public radius: number,
    public baseDrop: number,
    public maxTravel: number,
  ) {}

  step(dt: number, gravityAcceleration: number, leftMass: number, rightMass: number): void {
    this.acceleration = gravityAcceleration * (rightMass - leftMass) / (leftMass + rightMass);
    this.velocity += this.acceleration * dt;
    this.offset += this.velocity * dt;
    if (Math.abs(this.offset) > this.maxTravel) {
      this.offset = Math.sign(this.offset) * this.maxTravel;
      this.velocity = 0;
    }
    this.wheelAngle += this.velocity * dt / this.radius;
  }

  poses(): { left: KinematicPose; right: KinematicPose } {
    return {
      left: {
        position: { x: this.center.x - this.radius, y: this.center.y + this.baseDrop - this.offset },
        velocity: { x: 0, y: -this.velocity },
        acceleration: { x: 0, y: -this.acceleration },
      },
      right: {
        position: { x: this.center.x + this.radius, y: this.center.y + this.baseDrop + this.offset },
        velocity: { x: 0, y: this.velocity },
        acceleration: { x: 0, y: this.acceleration },
      },
    };
  }

  moveWeight(side: "left" | "right", point: Vector2): void {
    const relative = point.y - this.center.y - this.baseDrop;
    this.offset = Math.max(-this.maxTravel, Math.min(this.maxTravel, side === "right" ? relative : -relative));
    this.velocity = 0;
  }

  resize(scaleX: number, scaleY: number): void {
    this.center = { x: this.center.x * scaleX, y: this.center.y * scaleY };
    this.radius *= Math.min(scaleX, scaleY);
    this.baseDrop *= scaleY;
    this.maxTravel *= scaleY;
    this.offset *= scaleY;
  }
}
