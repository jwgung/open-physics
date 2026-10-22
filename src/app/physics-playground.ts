import type { Vector2 } from "../physics/core";
import { PointGravityField, UniformGravityField } from "../physics/fields";
import {
  AnchoredSpringLaw,
  BuoyancyAreaLaw,
  BuoyancyRegionLaw,
  ConstantBodyForceLaw,
  PushFrictionLaw,
  SurfaceContactFrictionModifier,
} from "../physics/laws/world-mechanics";
import { PhysicsSimulation } from "../physics/simulation";
import type { Body, BodyCollider } from "../physics/world";
import {
  PendulumModel,
  type KinematicPose,
} from "./mechanics-scenes";
import {
  LeverChallenge,
  OrbitChallenge,
  PulleyAdvantageChallenge,
  type OrbitAnalysis,
  type SupportStrands,
} from "./mechanics-challenges";

export type PlaygroundShape = "circle" | "box";
/** Every guided experiment preset (the single list the PlaygroundPreset union comes from). */
export const PLAYGROUND_PRESETS = [
  "free-fall", "projectile", "collision", "spring", "friction", "rotation", "orbit", "buoyancy", "constraints", "pulley",
] as const;
export type PlaygroundPreset = (typeof PLAYGROUND_PRESETS)[number];
export type PlaygroundMaterial = "rubber" | "wood" | "steel" | "clay";
export type SandboxObjectKind = "ball" | "box" | "block" | "anchor";
export type SandboxApparatusKind = "spring" | "lever" | "pulley";
export type SandboxConnectionKind = "rope" | "rod";
export type SandboxEnvironmentKind = "gravity-source" | "water";

export const MATERIALS: Readonly<Record<PlaygroundMaterial, {
  restitution: number;
  friction: number;
}>> = {
  rubber: { restitution: 0.88, friction: 0.42 },
  wood: { restitution: 0.5, friction: 0.22 },
  steel: { restitution: 0.72, friction: 0.08 },
  clay: { restitution: 0.08, friction: 0.58 },
};

export interface PlaygroundObject {
  id: string;
  label: string;
  shape: PlaygroundShape;
  x: number;
  y: number;
  width: number;
  height: number;
  radius: number;
  color: string;
  material: PlaygroundMaterial;
  angle: number;
  anchor?: boolean;
  gravitySource?: boolean;
}

export interface PlaygroundObjectOptions {
  label?: string;
  color?: string;
  mass?: number;
  material?: PlaygroundMaterial;
  velocity?: Vector2;
  fixed?: boolean;
  anchor?: boolean;
  gravitySource?: boolean;
  angle?: number;
}

export interface PlaygroundSnapshot {
  paused: boolean;
  gravity: number;
  preset: PlaygroundPreset;
  selected: {
    id: string;
    label: string;
    shape: PlaygroundShape;
    color: string;
    mass: number;
    material: PlaygroundMaterial;
    fixed: boolean;
    guided: boolean;
    anchor: boolean;
    gravitySource: boolean;
    angleDegrees: number;
  } | null;
  ropeConnection: { startId: string; startLabel: string; kind: SandboxConnectionKind } | null;
  appliedForceIds: string[];
  environment: { water: boolean; gravitySourceCount: number };
  observation: {
    speed: number;
    speedDirection: string;
    acceleration: number;
    accelerationDirection: string;
    momentum: number;
    kineticEnergy: number;
    potentialEnergy: number;
    springEnergy: number;
    appliedForce: number;
  } | null;
  forceDiagram: PlaygroundForceDiagram | null;
  graph: PlaygroundGraph | null;
  comparison: PlaygroundTrialComparison | null;
  collision: {
    readonly occurred: boolean;
    readonly velocityA: number;
    readonly velocityB: number;
  } | null;
}

export interface PlaygroundTrialComparison {
  readonly condition: string;
  readonly values: readonly {
    readonly label: string;
    readonly value: number;
    readonly unit: string;
  }[];
}

export interface PlaygroundForceVector {
  readonly label: string;
  readonly vector: Vector2;
  readonly magnitude: number;
  readonly direction: string;
  readonly color: string;
}

export interface PlaygroundForceDiagram {
  readonly objectLabel: string;
  readonly forces: readonly PlaygroundForceVector[];
  readonly net: PlaygroundForceVector;
  readonly balanced: boolean;
}

export interface PlaygroundGraph {
  title: string;
  xLabel: string;
  yLabel: string;
  series: Array<{ label: string; color: string }>;
  samples: Array<{ time: number; values: number[] }>;
}

export interface PlaygroundOptions {
  gravity?: number;
  width?: number;
  height?: number;
  onUpdate?: (snapshot: PlaygroundSnapshot) => void;
}

export interface VisualizationOptions {
  grid: boolean;
  trails: boolean;
  vectors: boolean;
}

export interface SelectedObjectUpdate {
  label?: string;
  color?: string;
  mass?: number;
  material?: PlaygroundMaterial;
}

const PIXELS_PER_METER = 48;
const PRESET_REFERENCE_WIDTH = 960;
const FIXED_STEP = 1 / 120;
const FLOOR_HEIGHT = 76;
const RESTING_REBOUND_SPEED = PIXELS_PER_METER;
const COLLISION_WORLD_DAMPING = 0.15;
const MOTION_SLEEP_SPEED = 2;
const VELOCITY_VECTOR_SCALE = 0.22;
const MAX_VELOCITY_VECTOR_LENGTH = 96;
const DEFAULT_VELOCITY_HANDLE_OFFSET = 64;
const VELOCITY_HANDLE_RADIUS = 12;
const CONTROL_HIT_RADIUS = 24;
const VELOCITY_IDLE_EPSILON = 0.01;
const VELOCITY_ANGLE_SNAP_RADIANS = 15 * Math.PI / 180;
const FORCE_VECTOR_SCALE = 10 / PIXELS_PER_METER;
const DEFAULT_APPLIED_FORCE = 4 * PIXELS_PER_METER;
const POINT_GRAVITY_GUIDE_RADIUS = 180;
const POINT_GRAVITY_ORBITAL_SPEED = 155;
const ROTATION_HANDLE_OFFSET = 38;
const BLOCK_ANGLE_SNAP_RADIANS = 15 * Math.PI / 180;
const MIN_BLOCK_WIDTH = 28;
const MIN_BLOCK_HEIGHT = 24;
const LEVER_FORCE_PER_PIXEL = 1.25;
const LEVER_LIFT_ANGLE = 0.18;
const GRAPH_SAMPLE_INTERVAL = 1 / 12;
const MAX_GRAPH_SAMPLES = 150;
const TRAJECTORY_PREVIEW_STEP = 0.08;
const TRAJECTORY_PREVIEW_STEPS = 45;
const SPRING_MOUNT_CLEARANCE = 8;
const COLORS = ["#5b7cfa", "#f27a54", "#25a77a", "#a069dc", "#e2a62b"];
const MATERIAL_LABELS: Readonly<Record<PlaygroundMaterial, string>> = {
  rubber: "고무",
  wood: "나무",
  steel: "금속",
  clay: "점토",
};

export function mechanicsForceDirection(vector: Vector2): string {
  const magnitude = Math.hypot(vector.x, vector.y);
  if (magnitude < 0.05) return "힘이 균형을 이뤄요";
  const horizontal = Math.abs(vector.x) / magnitude;
  const vertical = Math.abs(vector.y) / magnitude;
  if (horizontal < 0.35) return vector.y < 0 ? "위쪽" : "아래쪽";
  if (vertical < 0.35) return vector.x < 0 ? "왼쪽" : "오른쪽";
  return `${vector.y < 0 ? "위" : "아래"}${vector.x < 0 ? "왼쪽" : "오른쪽"}`;
}

type ResizeHandle = "width" | "height" | "both";

const GRAPH_SPECS: Readonly<Record<PlaygroundPreset, Omit<PlaygroundGraph, "samples" | "xLabel">>> = {
  "free-fall": {
    title: "바닥까지 남은 높이",
    yLabel: "높이 (m)",
    series: [
      { label: "가벼운 공", color: "#5b7cfa" },
      { label: "기준 공", color: "#25a77a" },
      { label: "무거운 공", color: "#f27a54" },
    ],
  },
  projectile: {
    title: "발사체의 높이",
    yLabel: "높이 (m)",
    series: [{ label: "발사체", color: "#5b7cfa" }],
  },
  collision: {
    title: "두 물체의 운동량",
    yLabel: "운동량 (kg·m/s)",
    series: [
      { label: "물체 A", color: "#5b7cfa" },
      { label: "물체 B", color: "#f27a54" },
    ],
  },
  spring: {
    title: "에너지가 바뀌는 모습",
    yLabel: "에너지 비율 (%)",
    series: [
      { label: "움직임", color: "#5b7cfa" },
      { label: "용수철", color: "#a069dc" },
    ],
  },
  friction: {
    title: "미는 힘과 버티는 힘",
    yLabel: "힘 (N)",
    series: [
      { label: "내가 주는 힘", color: "#e05c3f" },
      { label: "최대 정지 마찰력", color: "#5b7cfa" },
    ],
  },
  rotation: {
    title: "지렛대에 필요한 힘",
    yLabel: "힘 (N)",
    series: [
      { label: "내가 누르는 힘", color: "#e05c3f" },
      { label: "들어 올리는 데 필요한 힘", color: "#5b7cfa" },
    ],
  },
  constraints: {
    title: "두 진자의 각도",
    yLabel: "각도 (°)",
    series: [
      { label: "줄", color: "#5b7cfa" },
      { label: "막대", color: "#25a77a" },
    ],
  },
  pulley: {
    title: "줄 수에 따른 필요한 힘",
    yLabel: "힘 (N)",
    series: [
      { label: "내가 당기는 힘", color: "#e05c3f" },
      { label: "필요한 힘", color: "#5b7cfa" },
    ],
  },
  orbit: {
    title: "발사 속력과 궤도 기준",
    yLabel: "속력 (m/s)",
    series: [
      { label: "발사 속력", color: "#5b7cfa" },
      { label: "원 궤도 속력", color: "#25a77a" },
      { label: "탈출 속력", color: "#e05c3f" },
    ],
  },
  buoyancy: {
    title: "물에 잠긴 깊이",
    yLabel: "잠긴 깊이 (m)",
    series: [{ label: "공", color: "#f27a54" }],
  },
};

type GuidedMechanicsScene =
  | {
    kind: "lever";
    loadId: string;
    model: LeverChallenge;
    center: Vector2;
    beamLength: number;
    appliedForce: number;
    angle: number;
  }
  | {
    kind: "constraints";
    ropeId: string;
    rodId: string;
    rope: PendulumModel;
    rod: PendulumModel;
  }
  | {
    kind: "pulley-advantage";
    loadId: string;
    model: PulleyAdvantageChallenge;
    fixedY: number;
    loadX: number;
    loadStartY: number;
    pullX: number;
    pullStartY: number;
    handleDistance: number;
    pullDistance: number;
    maxLift: number;
  };

interface OrbitExperiment {
  field: PointGravityField;
  challenge: OrbitChallenge;
  analysis: OrbitAnalysis;
  centerId: string;
  bodyId: string;
  guideRadius: number;
}

type ChallengeDrag = "friction" | "lever" | "pulley";

/** Connects browser input and rendering to the renderer-independent physics core. */
export class PhysicsPlayground {
  readonly canvas: HTMLCanvasElement;
  readonly ctx: CanvasRenderingContext2D;
  readonly simulation: PhysicsSimulation;
  readonly objects = new Map<string, PlaygroundObject>();
  readonly visualization: VisualizationOptions = { grid: true, trails: true, vectors: true };

  gravity: number;
  currentPreset: PlaygroundPreset = "free-fall";
  onUpdate?: (snapshot: PlaygroundSnapshot) => void;

  private _paused = true;
  private pointerId: number | null = null;
  private draggedId: string | null = null;
  private velocityDraggedId: string | null = null;
  private forceDraggedId: string | null = null;
  private rotatingId: string | null = null;
  private resizingId: string | null = null;
  private resizeHandle: ResizeHandle | null = null;
  private resizeAnchor: Vector2 | null = null;
  private challengeDrag: ChallengeDrag | null = null;
  private challengeDragOrigin: Vector2 | null = null;
  private challengeDragPoint: Vector2 | null = null;
  private challengeDragStartPullDistance = 0;
  private challengeDragStartHandleDistance = 0;
  private selectedId: string | null = null;
  private labMode = true;
  private graphTime = 0;
  private lastGraphSampleTime = 0;
  private graphSamples: PlaygroundGraph["samples"] = [];
  private lastFrame = 0;
  private lastNotification = 0;
  private accumulator = 0;
  private trailTick = 0;
  private objectSequence = 0;
  private ropeSequence = 0;
  private readonly trails = new Map<string, Vector2[]>();
  private ropeStartId: string | null = null;
  private ropePointer: Vector2 | null = null;
  private connectionKind: SandboxConnectionKind | null = null;
  private readonly forceLaws = new Map<string, ConstantBodyForceLaw>();
  private readonly gravitySources = new Map<string, { field: PointGravityField; guideRadius: number }>();
  private sandboxWater: BuoyancyAreaLaw | null = null;
  private readonly surfaceFriction: SurfaceContactFrictionModifier;
  private springLaw: AnchoredSpringLaw | null = null;
  private readonly sandboxSpringLaws = new Map<string, AnchoredSpringLaw>();
  private frictionLaw: PushFrictionLaw | null = null;
  private buoyancyLaw: BuoyancyRegionLaw | null = null;
  private guidedScene: GuidedMechanicsScene | null = null;
  private readonly sandboxGuidedScenes: GuidedMechanicsScene[] = [];
  private challengeScene: GuidedMechanicsScene | null = null;
  private orbitExperiment: OrbitExperiment | null = null;
  private impulseFlash = 0;
  private directManipulationAutoPlay = true;
  private collisionResult: { velocityA: number; velocityB: number } | null = null;

  constructor(canvas: HTMLCanvasElement, options: PlaygroundOptions = {}) {
    this.canvas = canvas;
    const context = canvas.getContext("2d");
    if (!context) throw new Error("2D canvas context is not available.");
    this.ctx = context;
    this.gravity = options.gravity ?? 9.81;
    this.onUpdate = options.onUpdate;
    this.canvas.width = options.width ?? 960;
    this.canvas.height = options.height ?? 600;
    this.surfaceFriction = new SurfaceContactFrictionModifier({
      floorY: this.floorY,
      normalAcceleration: this.gravity * PIXELS_PER_METER,
    });
    this.simulation = new PhysicsSimulation({
      fields: [new UniformGravityField({ x: 0, y: this.gravity * PIXELS_PER_METER })],
      forceModifiers: [this.surfaceFriction],
      restitutionVelocityThreshold: RESTING_REBOUND_SPEED,
    });
    this.bindPointerEvents();
    requestAnimationFrame((time) => this.frame(time));
  }

  get paused(): boolean { return this._paused; }
  set paused(value: boolean) {
    this._paused = value;
    this.accumulator = 0;
    this.notify();
  }
  get floorY(): number { return this.canvas.height - FLOOR_HEIGHT; }

  toggle(): void { this.paused = !this.paused; }

  setDirectManipulationAutoPlay(enabled: boolean): void {
    this.directManipulationAutoPlay = enabled;
  }

  addObject(): PlaygroundObject {
    return this.addSandboxObject("ball");
  }

  addSandboxObject(kind: SandboxObjectKind): PlaygroundObject {
    this.resetRopeConnectionState();
    this._paused = true;
    this.accumulator = 0;
    const sequence = this.objects.size + 1;
    if (kind === "ball") {
      return this.addCircle(this.canvas.width * 0.3, 115, 25, {
        label: `공 ${sequence}`,
        material: "rubber",
      });
    }
    if (kind === "box") {
      return this.addBox(this.canvas.width * 0.62, 115, 56, 56, {
        label: `상자 ${sequence}`,
        material: "wood",
      });
    }
    if (kind === "anchor") {
      return this.addCircle(this.canvas.width * 0.22, this.floorY * 0.32, 14, {
        label: `고정점 ${sequence}`,
        color: "#53699d",
        material: "steel",
        fixed: true,
        anchor: true,
      });
    }
    return this.addBox(this.canvas.width * 0.58, this.floorY - 115, 170, 26, {
      label: `고정 블록 ${sequence}`,
      color: "#718099",
      material: "steel",
      fixed: true,
    });
  }

  addSandboxApparatus(kind: SandboxApparatusKind): PlaygroundObject {
    this.resetRopeConnectionState();
    this._paused = true;
    this.labMode = false;
    this.accumulator = 0;
    if (kind === "spring") {
      const selected = this.selectedId ? this.objects.get(this.selectedId) : undefined;
      const selectedBody = selected ? this.simulation.getBody(selected.id) : undefined;
      const object = selected && !selectedBody?.fixed
        ? selected
        : this.addCircle(this.canvas.width * 0.56, this.floorY * 0.48, 28, {
          label: "용수철 공",
          color: "#a069dc",
          material: "wood",
        });
      this.connectSpring(object);
      this.notify();
      return object;
    }

    const sceneKind = kind === "lever" ? "lever" : "pulley-advantage";
    const existing = this.allGuidedScenes().find((scene) => scene.kind === sceneKind);
    if (existing) this.removeGuidedApparatus(existing);
    if (this.guidedScene) {
      this.sandboxGuidedScenes.push(this.guidedScene);
      this.guidedScene = null;
    }
    this.moveOrdinaryObjectsBelowApparatusHeader();
    const object = kind === "lever"
      ? this.createLeverChallenge()
      : this.createPulleyChallenge();
    this.notify();
    return object;
  }

  startConnection(kind: SandboxConnectionKind): boolean {
    if (this.ropeStartId) {
      this.resetRopeConnectionState();
      this.notify();
      return false;
    }
    const object = this.selectedId ? this.objects.get(this.selectedId) : undefined;
    if (this.labMode || !object || this.isGuidedBody(object.id)) return false;
    this._paused = true;
    this.accumulator = 0;
    this.ropeStartId = object.id;
    this.ropePointer = { x: object.x, y: object.y };
    this.connectionKind = kind;
    this.canvas.style.cursor = "crosshair";
    this.notify();
    return true;
  }

  startRopeConnection(): boolean { return this.startConnection("rope"); }

  toggleForceForSelected(): boolean {
    if (!this.selectedId) return false;
    const body = this.simulation.getBody(this.selectedId);
    if (!body || body.fixed || this.isGuidedBody(this.selectedId)) return false;
    const active = this.forceLaws.get(this.selectedId);
    if (active) {
      this.simulation.removeLaw(active.id);
      this.forceLaws.delete(this.selectedId);
      this.simulation.refreshAccelerations();
      this.notify();
      return false;
    }
    const law = new ConstantBodyForceLaw({
      bodyId: this.selectedId,
      vector: { x: DEFAULT_APPLIED_FORCE, y: 0 },
    });
    this.forceLaws.set(this.selectedId, law);
    this.simulation.addLaw(law);
    this._paused = true;
    this.simulation.refreshAccelerations();
    this.notify();
    return true;
  }

  toggleSandboxEnvironment(kind: SandboxEnvironmentKind): boolean {
    if (this.labMode) return false;
    this._paused = true;
    this.accumulator = 0;
    if (kind === "water") {
      if (this.sandboxWater) {
        this.simulation.removeLaw(this.sandboxWater.id);
        this.sandboxWater = null;
        this.simulation.refreshAccelerations();
        this.notify();
        return false;
      }
      this.sandboxWater = new BuoyancyAreaLaw({
        id: "fluid.buoyancy.sandbox",
        waterline: this.floorY * 0.58,
        referenceDisplacedMass: 1.45,
        referenceRadius: 28,
        gravityAcceleration: this.gravity * PIXELS_PER_METER,
      });
      this.simulation.addLaw(this.sandboxWater);
      this.simulation.refreshAccelerations();
      this.notify();
      return true;
    }

    this.replaceGravity(0);
    const source = this.addCircle(this.canvas.width * 0.34, this.floorY * 0.52, 38, {
      label: `중력원 ${this.gravitySources.size + 1}`,
      color: "#e2a62b",
      mass: 20,
      material: "steel",
      fixed: true,
      gravitySource: true,
    });
    const field = new PointGravityField(
      { x: source.x, y: source.y },
      1,
      POINT_GRAVITY_ORBITAL_SPEED ** 2 * POINT_GRAVITY_GUIDE_RADIUS,
      `field.gravity.point.${source.id}`,
    );
    this.gravitySources.set(source.id, { field, guideRadius: POINT_GRAVITY_GUIDE_RADIUS });
    this.simulation.addField(field);
    this.simulation.refreshAccelerations();
    this.notify();
    return true;
  }

  cancelRopeConnection(): boolean {
    if (!this.ropeStartId) return false;
    this.resetRopeConnectionState();
    this.notify();
    return true;
  }

  startSandbox(): void {
    this._paused = true;
    this.labMode = false;
    this.resetGraph();
    this.currentPreset = "free-fall";
    this.accumulator = 0;
    this.trailTick = 0;
    this.selectedId = null;
    this.resetRopeConnectionState();
    this.objects.clear();
    this.trails.clear();
    this.clearExperimentLaws();
    this.simulation.clear();
    this.replaceGravity(9.81);
    this.addCircle(this.canvas.width * 0.5, 120, 28, {
      label: "물체 1",
      color: "#5b7cfa",
      mass: 1,
      material: "rubber",
    });
    this.notify();
  }

  addCircle(x = this.canvas.width / 2, y = 120, radius = 25, options: PlaygroundObjectOptions = {}): PlaygroundObject {
    const id = this.nextObjectId();
    const object: PlaygroundObject = {
      id,
      label: options.label ?? `원 ${this.objects.size + 1}`,
      shape: "circle",
      x,
      y,
      width: radius * 2,
      height: radius * 2,
      radius,
      color: options.color ?? this.nextColor(),
      material: options.material ?? "rubber",
      angle: options.angle ?? 0,
      anchor: options.anchor,
      gravitySource: options.gravitySource,
    };
    this.registerObject(object, options);
    return object;
  }

  addBox(x = this.canvas.width / 2, y = 110, width = 54, height = 54, options: PlaygroundObjectOptions = {}): PlaygroundObject {
    const id = this.nextObjectId();
    const object: PlaygroundObject = {
      id,
      label: options.label ?? `상자 ${this.objects.size + 1}`,
      shape: "box",
      x,
      y,
      width,
      height,
      radius: Math.min(width, height) / 2,
      color: options.color ?? this.nextColor(),
      material: options.material ?? "wood",
      angle: options.angle ?? 0,
      anchor: options.anchor,
      gravitySource: options.gravitySource,
    };
    this.registerObject(object, options);
    return object;
  }

  loadPreset(preset: PlaygroundPreset, autoPlay = false): void {
    this._paused = true;
    this.labMode = true;
    this.resetGraph();
    this.currentPreset = preset;
    this.collisionResult = null;
    this.accumulator = 0;
    this.trailTick = 0;
    this.selectedId = null;
    this.resetRopeConnectionState();
    this.objects.clear();
    this.trails.clear();
    this.clearExperimentLaws();
    this.simulation.clear();

    if (preset === "free-fall") {
      this.replaceGravity(9.81);
      this.addCircle(this.presetX(350), 125, 24, { label: "가벼운 공", color: "#5b7cfa", mass: 0.5, material: "wood" });
      this.addCircle(this.presetX(480), 125, 24, { label: "기준 공", color: "#25a77a", mass: 1, material: "wood" });
      this.addCircle(this.presetX(610), 125, 24, { label: "무거운 공", color: "#f27a54", mass: 3, material: "wood" });
    } else if (preset === "projectile") {
      this.replaceGravity(9.81);
      this.addCircle(this.presetX(145), this.floorY - 42, 22, {
        label: "발사체",
        color: "#5b7cfa",
        mass: 1,
        material: "rubber",
        velocity: { x: 5.6, y: -7.2 },
      });
    } else if (preset === "collision") {
      this.replaceGravity(0);
      this.addCircle(this.presetX(285), 300, 32, {
        label: "물체 A",
        color: "#5b7cfa",
        mass: 1,
        material: "rubber",
        velocity: { x: 3.4, y: 0 },
      });
      this.addCircle(this.presetX(675), 300, 40, {
        label: "물체 B",
        color: "#f27a54",
        mass: 2,
        material: "rubber",
        velocity: { x: -1.7, y: 0 },
      });
    } else if (preset === "spring") {
      this.replaceGravity(0);
      const anchor = { x: this.canvas.width * 0.22, y: this.floorY * 0.52 };
      const restLength = this.canvas.width * 0.28;
      const object = this.addCircle(anchor.x + restLength + this.canvas.width * 0.12, anchor.y, 28, {
        label: "용수철 공",
        color: "#a069dc",
        mass: 1,
        material: "wood",
      });
      this.connectSpring(object, anchor, restLength);
    } else if (preset === "friction") {
      this.replaceGravity(9.81);
      const object = this.addBox(this.canvas.width * 0.34, this.floorY - 34, 76, 68, {
        label: "밀어 볼 상자",
        color: "#e2a62b",
        mass: 8,
        material: "wood",
      });
      this.frictionLaw = new PushFrictionLaw({
        bodyId: object.id,
        surfaceY: this.floorY,
        staticCoefficient: MATERIALS[object.material].friction + 0.18,
        kineticCoefficient: MATERIALS[object.material].friction,
        normalAcceleration: this.gravity * PIXELS_PER_METER,
      });
      this.surfaceFriction.excludeBody(object.id);
      this.simulation.addLaw(this.frictionLaw);
      this.simulation.refreshAccelerations();
    } else if (preset === "rotation") {
      this.replaceGravity(9.81);
      this.createLeverChallenge();
    } else if (preset === "orbit") {
      this.replaceGravity(0);
      const center = { x: this.canvas.width * 0.5, y: this.floorY * 0.5 };
      const radius = Math.min(this.canvas.width * 0.24, this.floorY * 0.34);
      const orbitalSpeed = 155;
      const field = new PointGravityField(center, 1, orbitalSpeed ** 2 * radius);
      this.simulation.addField(field);
      const centerObject = this.addCircle(center.x, center.y, 38, {
        label: "큰 별",
        color: "#e2a62b",
        mass: 20,
        material: "steel",
        fixed: true,
      });
      const orbiting = this.addCircle(center.x + radius, center.y, 21, {
        label: "작은 별",
        color: "#5b7cfa",
        mass: 1,
        material: "steel",
        velocity: { x: 0, y: -orbitalSpeed / PIXELS_PER_METER },
      });
      const challenge = new OrbitChallenge({
        center,
        gravitationalParameter: field.G * field.sourceMass,
        collisionRadius: 38 + 21,
      });
      this.orbitExperiment = {
        field,
        challenge,
        analysis: challenge.analyze({ x: orbiting.x, y: orbiting.y }, { x: 0, y: -orbitalSpeed }),
        centerId: centerObject.id,
        bodyId: orbiting.id,
        guideRadius: radius,
      };
      this.refreshOrbitAnalysis();
      this.simulation.refreshAccelerations();
    } else if (preset === "buoyancy") {
      this.replaceGravity(9.81);
      const waterline = this.floorY * 0.4;
      const object = this.addCircle(this.canvas.width * 0.5, waterline - 70, 35, {
        label: "물에 띄울 공",
        color: "#f27a54",
        mass: 1,
        material: "wood",
      });
      this.buoyancyLaw = new BuoyancyRegionLaw({
        bodyId: object.id,
        waterline,
        displacedMass: 1.45,
        gravityAcceleration: this.gravity * PIXELS_PER_METER,
      });
      this.simulation.addLaw(this.buoyancyLaw);
      this.simulation.refreshAccelerations();
    } else if (preset === "constraints") {
      this.replaceGravity(9.81);
      const length = Math.min(210, this.floorY * 0.42);
      const rope = new PendulumModel({ x: this.canvas.width * 0.34, y: 105 }, length, 0.62, 0.06);
      const rod = new PendulumModel({ x: this.canvas.width * 0.68, y: 105 }, length, -0.5, 0.03);
      const ropePose = rope.pose();
      const rodPose = rod.pose();
      const ropeObject = this.addCircle(ropePose.position.x, ropePose.position.y, 25, {
        label: "줄 추",
        color: "#5b7cfa",
        mass: 1,
        material: "wood",
        fixed: true,
      });
      const rodObject = this.addCircle(rodPose.position.x, rodPose.position.y, 25, {
        label: "막대 추",
        color: "#25a77a",
        mass: 1,
        material: "steel",
        fixed: true,
      });
      this.guidedScene = {
        kind: "constraints",
        ropeId: ropeObject.id,
        rodId: rodObject.id,
        rope,
        rod,
      };
      this.setBodyPose(ropeObject.id, ropePose);
      this.setBodyPose(rodObject.id, rodPose);
    } else {
      this.replaceGravity(9.81);
      this.createPulleyChallenge();
    }
    this._paused = !autoPlay;
    this.recordGraphSample(true);
    this.notify();
  }

  reset(autoPlay = false): void { this.loadPreset(this.currentPreset, autoPlay); }

  stepOnce(): void {
    if (!this.paused) return;
    this.advance(1 / 60);
    this.syncObjects();
    this.render();
    this.notify();
  }

  removeSelected(): void {
    if (!this.selectedId) return;
    if (this.ropeStartId === this.selectedId) this.resetRopeConnectionState();
    const guidedIds = this.guidedBodyIds();
    if (guidedIds.includes(this.selectedId)) {
      this.removeGuidedApparatus(this.guidedSceneForBody(this.selectedId));
      this.notify();
      return;
    }
    if (
      this.orbitExperiment
      && [this.orbitExperiment.centerId, this.orbitExperiment.bodyId].includes(this.selectedId)
    ) {
      this.simulation.removeBody(this.orbitExperiment.centerId);
      this.simulation.removeBody(this.orbitExperiment.bodyId);
      this.objects.delete(this.orbitExperiment.centerId);
      this.objects.delete(this.orbitExperiment.bodyId);
      this.simulation.removeField(this.orbitExperiment.field.id);
      this.orbitExperiment = null;
      this.selectedId = null;
      this.notify();
      return;
    }
    if (this.springLaw?.bodyId === this.selectedId) {
      this.simulation.removeLaw(this.springLaw.id);
      this.springLaw = null;
    }
    const sandboxSpring = this.sandboxSpringLaws.get(this.selectedId);
    if (sandboxSpring) {
      this.simulation.removeLaw(sandboxSpring.id);
      this.sandboxSpringLaws.delete(this.selectedId);
    }
    if (this.frictionLaw?.bodyId === this.selectedId) {
      this.simulation.removeLaw(this.frictionLaw.id);
      this.frictionLaw = null;
    }
    if (this.buoyancyLaw?.bodyId === this.selectedId) {
      this.simulation.removeLaw(this.buoyancyLaw.id);
      this.buoyancyLaw = null;
    }
    const forceLaw = this.forceLaws.get(this.selectedId);
    if (forceLaw) {
      this.simulation.removeLaw(forceLaw.id);
      this.forceLaws.delete(this.selectedId);
    }
    const gravitySource = this.gravitySources.get(this.selectedId);
    if (gravitySource) {
      this.simulation.removeField(gravitySource.field.id);
      this.gravitySources.delete(this.selectedId);
    }
    this.simulation.removeBody(this.selectedId);
    this.objects.delete(this.selectedId);
    this.trails.delete(this.selectedId);
    this.selectedId = null;
    this.notify();
  }

  select(id: string | null): void {
    const nextId = id && this.objects.has(id) ? id : null;
    if (!this.labMode && nextId !== this.selectedId) {
      this.selectedId = nextId;
      this.resetGraph();
      this.recordGraphSample();
    } else {
      this.selectedId = nextId;
    }
    this.notify();
  }

  setGravity(value: number): void {
    if (!Number.isFinite(value)) return;
    this.replaceGravity(Math.max(0, Math.min(30, value)));
    this.notify();
  }

  setVisualization(option: keyof VisualizationOptions, value: boolean): void {
    this.visualization[option] = value;
    if (option === "trails" && !value) this.clearTrails();
    this.notify();
  }

  updateSelected(update: SelectedObjectUpdate): void {
    if (!this.selectedId) return;
    const object = this.objects.get(this.selectedId);
    const body = this.simulation.getBody(this.selectedId);
    if (!object || !body) return;

    if (update.label !== undefined) object.label = update.label.trim().slice(0, 24) || object.label;
    if (update.color !== undefined) object.color = update.color;
    if (update.mass !== undefined && Number.isFinite(update.mass)) {
      body.state.mass = Math.max(0.1, Math.min(20, update.mass));
      const objectScene = this.guidedSceneForBody(object.id);
      if (objectScene?.kind === "lever" && objectScene.loadId === object.id) {
        objectScene.model.setLoadMass(body.state.mass);
      }
      if (objectScene?.kind === "pulley-advantage" && objectScene.loadId === object.id) {
        objectScene.model.setLoadMass(body.state.mass);
      }
    }
    if (update.material !== undefined) {
      object.material = update.material;
      body.restitution = MATERIALS[update.material].restitution;
      body.staticFriction = MATERIALS[update.material].friction + 0.18;
      body.kineticFriction = MATERIALS[update.material].friction;
      if (this.frictionLaw?.bodyId === object.id) {
        this.frictionLaw.setCoefficients(
          MATERIALS[update.material].friction + 0.18,
          MATERIALS[update.material].friction,
        );
      }
    }
    this.clearTrails();
    this.simulation.refreshAccelerations();
    this.advanceGuidedScene(0);
    this.recordGraphSample(true);
    this.notify();
  }

  snapshot(): PlaygroundSnapshot {
    let selected: PlaygroundSnapshot["selected"] = null;
    if (this.selectedId) {
      const object = this.objects.get(this.selectedId);
      const body = this.simulation.getBody(this.selectedId);
      if (object && body) {
        selected = {
          id: object.id,
          label: object.label,
          shape: object.shape,
          color: object.color,
          mass: body.state.mass,
          material: object.material,
          fixed: Boolean(body.fixed),
          guided: this.isGuidedBody(object.id),
          anchor: Boolean(object.anchor),
          gravitySource: Boolean(object.gravitySource),
          angleDegrees: this.toDegrees(object.angle),
        };
      }
    }
    const ropeStart = this.ropeStartId ? this.objects.get(this.ropeStartId) : undefined;
    const observation = selected ? this.selectedObservation(selected.id) : null;
    const forceDiagram = selected ? this.forceDiagramFor(selected.id) : null;
    const collisionObjects = this.labMode && this.currentPreset === "collision" ? [...this.objects.values()].slice(0, 2) : [];
    const collisionBodies = collisionObjects.map((object) => this.simulation.getBody(object.id));
    const graph = this.labMode
      ? {
        ...GRAPH_SPECS[this.currentPreset],
        xLabel: "시간",
        samples: this.graphSamples.map((sample) => ({ time: sample.time, values: [...sample.values] })),
      }
      : selected && !selected.fixed ? {
        title: `${selected.label}의 속력`,
        xLabel: "시간",
        yLabel: "속력 (m/s)",
        series: [{ label: selected.label, color: selected.color }],
        samples: this.graphSamples.map((sample) => ({ time: sample.time, values: [...sample.values] })),
      } : null;
    return {
      paused: this.paused,
      gravity: this.gravity,
      preset: this.currentPreset,
      selected,
      ropeConnection: ropeStart && this.connectionKind
        ? { startId: ropeStart.id, startLabel: ropeStart.label, kind: this.connectionKind }
        : null,
      appliedForceIds: [...this.forceLaws.keys()],
      environment: { water: Boolean(this.sandboxWater), gravitySourceCount: this.gravitySources.size },
      observation,
      forceDiagram,
      graph,
      comparison: this.currentComparison(),
      collision: collisionBodies.length === 2 && collisionBodies[0] && collisionBodies[1]
        ? {
          occurred: Boolean(this.collisionResult),
          velocityA: this.collisionResult?.velocityA ?? collisionBodies[0].state.velocity.x / PIXELS_PER_METER,
          velocityB: this.collisionResult?.velocityB ?? collisionBodies[1].state.velocity.x / PIXELS_PER_METER,
        }
        : null,
    };
  }

  private currentComparison(): PlaygroundTrialComparison | null {
    if (!this.labMode) return null;
    const firstObject = this.objects.values().next().value as PlaygroundObject | undefined;
    if (this.currentPreset === "friction" && firstObject && this.frictionLaw) {
      const body = this.simulation.getBody(firstObject.id);
      if (!body) return null;
      return {
        condition: `${MATERIAL_LABELS[firstObject.material]} · ${body.state.mass < 4 ? "가벼운 물체" : body.state.mass < 8 ? "보통 물체" : "무거운 물체"}`,
        values: [{
          label: "움직이기 시작하는 힘",
          value: this.frictionLaw.maximumStaticForce(body.state) / PIXELS_PER_METER,
          unit: "N",
        }],
      };
    }
    if (this.currentPreset === "pulley" && this.guidedScene?.kind === "pulley-advantage") {
      const model = this.guidedScene.model;
      return {
        condition: `${model.supportStrands}줄 · ${model.loadMass < 8 ? "가벼운 짐" : model.loadMass < 15 ? "보통 짐" : "무거운 짐"}`,
        values: [
          { label: "필요한 힘", value: model.requiredForce, unit: "N" },
          { label: "1 m 올릴 때 당기는 줄", value: model.supportStrands, unit: "m" },
        ],
      };
    }
    if (this.currentPreset === "orbit" && this.orbitExperiment) {
      const body = this.simulation.getBody(this.orbitExperiment.bodyId);
      if (!body) return null;
      const radius = Math.hypot(
        body.state.position.x - this.orbitExperiment.field.sourcePosition.x,
        body.state.position.y - this.orbitExperiment.field.sourcePosition.y,
      );
      const period = 2 * Math.PI * radius / Math.max(this.orbitExperiment.analysis.circularSpeed, 1e-9);
      const outcome = this.orbitExperiment.analysis.outcome === "crash" ? "충돌" : this.orbitExperiment.analysis.outcome === "escape" ? "이탈" : "공전";
      return {
        condition: `예상 결과 · ${outcome}`,
        values: [
          { label: "현재 궤도 반지름", value: radius / PIXELS_PER_METER, unit: "m" },
          { label: "원 궤도 예상 주기", value: period, unit: "s" },
        ],
      };
    }
    return null;
  }

  clearTrails(): void {
    for (const [id, object] of this.objects) this.trails.set(id, [{ x: object.x, y: object.y }]);
  }

  private resetGraph(): void {
    this.graphTime = 0;
    this.lastGraphSampleTime = 0;
    this.graphSamples = [];
  }

  private recordGraphProgress(dt: number): void {
    this.graphTime += dt;
    if (this.graphTime - this.lastGraphSampleTime >= GRAPH_SAMPLE_INTERVAL) {
      this.recordGraphSample();
    }
  }

  private recordGraphSample(replaceAtCurrentTime = false): void {
    const sample = { time: this.graphTime, values: this.currentGraphValues() };
    const last = this.graphSamples.at(-1);
    if (replaceAtCurrentTime && last && Math.abs(last.time - this.graphTime) < 0.0001) {
      this.graphSamples[this.graphSamples.length - 1] = sample;
    } else {
      this.graphSamples.push(sample);
    }
    if (this.graphSamples.length > MAX_GRAPH_SAMPLES) this.graphSamples.shift();
    this.lastGraphSampleTime = this.graphTime;
  }

  private currentGraphValues(): number[] {
    if (!this.labMode) {
      const body = this.selectedId ? this.simulation.getBody(this.selectedId) : undefined;
      return body ? [Math.hypot(body.state.velocity.x, body.state.velocity.y) / PIXELS_PER_METER] : [0];
    }
    const objects = [...this.objects.values()];
    if (this.currentPreset === "free-fall") {
      return objects.map((object) => this.heightAboveFloor(object));
    }
    if (this.currentPreset === "projectile") {
      return objects[0] ? [this.heightAboveFloor(objects[0])] : [0];
    }
    if (this.currentPreset === "collision") {
      return objects.slice(0, 2).map((object) => {
        const body = this.simulation.getBody(object.id);
        return body ? body.state.mass * body.state.velocity.x / PIXELS_PER_METER : 0;
      });
    }
    if (this.currentPreset === "spring") {
      const law = this.springLaw;
      const object = objects[0];
      const body = object ? this.simulation.getBody(object.id) : undefined;
      if (!law || !body) return [0, 0];
      const speed = Math.hypot(body.state.velocity.x, body.state.velocity.y) / PIXELS_PER_METER;
      const extension = (
        Math.hypot(body.state.position.x - law.anchor.x, body.state.position.y - law.anchor.y)
        - law.restLength
      ) / PIXELS_PER_METER;
      const kinetic = 0.5 * body.state.mass * speed ** 2;
      const spring = 0.5 * law.stiffness * extension ** 2;
      const total = kinetic + spring;
      return total > 0.0001 ? [kinetic / total * 100, spring / total * 100] : [0, 0];
    }
    if (this.currentPreset === "friction") {
      const body = objects[0] ? this.simulation.getBody(objects[0].id) : undefined;
      return body && this.frictionLaw
        ? [Math.abs(this.frictionLaw.appliedForce) / PIXELS_PER_METER,
          this.frictionLaw.maximumStaticForce(body.state) / PIXELS_PER_METER]
        : [0, 0];
    }
    if (this.currentPreset === "rotation") {
      return this.guidedScene?.kind === "lever"
        ? [this.guidedScene.appliedForce, this.guidedScene.model.requiredForce]
        : [0, 0];
    }
    if (this.currentPreset === "constraints") {
      return this.guidedScene?.kind === "constraints"
        ? [this.toDegrees(this.guidedScene.rope.angle), this.toDegrees(this.guidedScene.rod.angle)]
        : [0, 0];
    }
    if (this.currentPreset === "pulley") {
      return this.guidedScene?.kind === "pulley-advantage"
        ? [this.guidedScene.pullDistance > 0 ? this.guidedScene.model.requiredForce : 0,
          this.guidedScene.model.requiredForce]
        : [0, 0];
    }
    if (this.currentPreset === "orbit") {
      const orbit = this.orbitExperiment;
      return orbit ? [
        orbit.analysis.speed / PIXELS_PER_METER,
        orbit.analysis.circularSpeed / PIXELS_PER_METER,
        orbit.analysis.escapeSpeed / PIXELS_PER_METER,
      ] : [0, 0, 0];
    }
    const law = this.buoyancyLaw;
    const object = objects[0];
    const body = object ? this.simulation.getBody(object.id) : undefined;
    if (!law || !object || !body) return [0];
    const submergedHeight = Math.max(
      0,
      Math.min(object.height, body.state.position.y + object.height / 2 - law.waterline),
    );
    return [submergedHeight / PIXELS_PER_METER];
  }

  private heightAboveFloor(object: PlaygroundObject): number {
    const body = this.simulation.getBody(object.id);
    if (!body) return 0;
    const halfHeight = object.shape === "circle" ? object.radius : object.height / 2;
    return Math.max(0, (this.floorY - body.state.position.y - halfHeight) / PIXELS_PER_METER);
  }

  private selectedObservation(id: string): NonNullable<PlaygroundSnapshot["observation"]> | null {
    const object = this.objects.get(id);
    const body = this.simulation.getBody(id);
    if (!object || !body || body.fixed) return null;
    const speed = Math.hypot(body.state.velocity.x, body.state.velocity.y) / PIXELS_PER_METER;
    const acceleration = Math.hypot(body.state.acceleration.x, body.state.acceleration.y) / PIXELS_PER_METER;
    const height = this.heightAboveFloor(object);
    const spring = this.springForBody(id);
    const extension = spring
      ? (Math.hypot(
        body.state.position.x - spring.anchor.x,
        body.state.position.y - spring.anchor.y,
      ) - spring.restLength) / PIXELS_PER_METER
      : 0;
    const appliedForce = this.forceLaws.get(id)?.vector;
    return {
      speed,
      speedDirection: speed < 0.005 ? "멈춤" : mechanicsForceDirection(body.state.velocity),
      acceleration,
      accelerationDirection: acceleration < 0.005 ? "변화 없음" : mechanicsForceDirection(body.state.acceleration),
      momentum: body.state.mass * speed,
      kineticEnergy: 0.5 * body.state.mass * speed ** 2,
      potentialEnergy: body.state.mass * this.gravity * height,
      springEnergy: spring ? 0.5 * spring.stiffness * extension ** 2 : 0,
      appliedForce: appliedForce ? Math.hypot(appliedForce.x, appliedForce.y) / PIXELS_PER_METER : 0,
    };
  }

  private forceDiagramFor(id: string): PlaygroundForceDiagram | null {
    const object = this.objects.get(id);
    const body = this.simulation.getBody(id);
    if (!object || !body || object.gravitySource || object.anchor) return null;

    const components: Array<{ label: string; vector: Vector2; color: string }> = [];
    const addComponent = (label: string, vector: Vector2, color: string): void => {
      if (Math.hypot(vector.x, vector.y) < 0.01) return;
      const existing = components.find((component) => component.label === label);
      if (existing) {
        existing.vector.x += vector.x;
        existing.vector.y += vector.y;
      } else {
        components.push({ label, vector: { ...vector }, color });
      }
    };

    for (const force of this.simulation.forceBreakdown(id, FIXED_STEP)) {
      const vector = { x: force.vector.x / PIXELS_PER_METER, y: force.vector.y / PIXELS_PER_METER };
      const source = force.source ?? "";
      if (this.frictionLaw?.bodyId === id && source === this.frictionLaw.id) {
        const applied = { x: this.frictionLaw.appliedForce / PIXELS_PER_METER, y: 0 };
        addComponent("주는 힘", applied, "#e05c3f");
        addComponent("마찰력", { x: vector.x - applied.x, y: vector.y }, "#5b7cfa");
      } else if (source.startsWith("field.gravity")) {
        addComponent("중력", vector, "#e2a62b");
      } else if (source.startsWith("spring.anchor")) {
        addComponent("용수철 힘", vector, "#a069dc");
      } else if (source.startsWith("force.constant")) {
        addComponent("주는 힘", vector, "#e05c3f");
      } else if (source.startsWith("fluid.buoyancy")) {
        addComponent("부력·물의 저항", vector, "#2b9bb5");
      } else if (source === "friction.surface.contact") {
        addComponent("마찰력", vector, "#5b7cfa");
      }
    }

    const guided = this.guidedSceneForBody(id);
    if (guided) {
      const current = components.reduce(
        (sum, component) => ({ x: sum.x + component.vector.x, y: sum.y + component.vector.y }),
        { x: 0, y: 0 },
      );
      const target = {
        x: body.state.mass * body.state.acceleration.x / PIXELS_PER_METER,
        y: body.state.mass * body.state.acceleration.y / PIXELS_PER_METER,
      };
      const label = guided.kind === "constraints"
        ? (guided.ropeId === id ? "줄의 장력" : "막대가 미는 힘")
        : guided.kind === "pulley-advantage" ? "줄이 당기는 힘" : "지렛대가 미는 힘";
      addComponent(label, { x: target.x - current.x, y: target.y - current.y }, "#25a77a");
    } else if (this.isRestingOnFloor(object, body)) {
      const verticalForce = components.reduce((sum, component) => sum + component.vector.y, 0);
      if (verticalForce > 0) addComponent("수직항력", { x: 0, y: -verticalForce }, "#25a77a");
    }

    const netVector = components.reduce(
      (sum, component) => ({ x: sum.x + component.vector.x, y: sum.y + component.vector.y }),
      { x: 0, y: 0 },
    );
    const toVector = (label: string, vector: Vector2, color: string): PlaygroundForceVector => ({
      label,
      vector: { ...vector },
      magnitude: Math.hypot(vector.x, vector.y),
      direction: mechanicsForceDirection(vector),
      color,
    });
    return {
      objectLabel: object.label,
      forces: components.map((component) => toVector(component.label, component.vector, component.color)),
      net: toVector("알짜힘", netVector, "#17243b"),
      balanced: Math.hypot(netVector.x, netVector.y) < 0.05,
    };
  }

  private isRestingOnFloor(object: PlaygroundObject, body: Body): boolean {
    const bottom = body.state.position.y + this.objectHalfExtents(object).y;
    return !body.fixed
      && Math.abs(bottom - this.floorY) <= 2.5
      && body.state.velocity.y >= -0.05 * PIXELS_PER_METER;
  }

  private springForBody(id: string): AnchoredSpringLaw | null {
    if (this.springLaw?.bodyId === id) return this.springLaw;
    return this.sandboxSpringLaws.get(id) ?? null;
  }

  private activeSpringLaws(): AnchoredSpringLaw[] {
    return [
      ...(this.springLaw ? [this.springLaw] : []),
      ...this.sandboxSpringLaws.values(),
    ];
  }

  private toDegrees(radians: number): number { return radians * 180 / Math.PI; }

  private presetX(referenceX: number): number {
    return referenceX / PRESET_REFERENCE_WIDTH * this.canvas.width;
  }

  private connectSpring(
    object: PlaygroundObject,
    anchor: Vector2 = {
      x: Math.max(54, object.x - Math.min(this.canvas.width * 0.25, 240)),
      y: object.y,
    },
    restLength = Math.hypot(object.x - anchor.x, object.y - anchor.y),
  ): void {
    const law = new AnchoredSpringLaw({
      bodyId: object.id,
      anchor,
      restLength,
      stiffness: 5,
      damping: 0.45,
    });
    if (this.labMode) {
      if (this.springLaw) this.simulation.removeLaw(this.springLaw.id);
      this.springLaw = law;
    } else {
      const previous = this.sandboxSpringLaws.get(object.id);
      if (previous) this.simulation.removeLaw(previous.id);
      this.sandboxSpringLaws.set(object.id, law);
    }
    this.simulation.addLaw(law);
    this.simulation.refreshAccelerations();
    this.select(object.id);
  }

  private createLeverChallenge(): PlaygroundObject {
    const center = this.labMode
      ? { x: this.canvas.width * 0.46, y: this.floorY * 0.58 }
      : { x: this.canvas.width * 0.29, y: this.floorY * 0.7 };
    const beamLength = this.labMode
      ? Math.min(this.canvas.width * 0.58, 560)
      : Math.min(this.canvas.width * 0.42, 410);
    const loadArm = beamLength * 0.22;
    const effortArm = beamLength * 0.45;
    const load = this.addBox(center.x - loadArm, center.y - 45, 74, 74, {
      label: "무거운 짐",
      color: "#f27a54",
      mass: 20,
      material: "wood",
      fixed: true,
    });
    this.guidedScene = {
      kind: "lever",
      loadId: load.id,
      model: new LeverChallenge({
        loadMass: 20,
        gravity: Math.max(this.gravity, 0.01),
        loadArm,
        effortArm,
      }),
      center,
      beamLength,
      appliedForce: 0,
      angle: 0,
    };
    this.applyGuidedScenePoses();
    return load;
  }

  private createPulleyChallenge(): PlaygroundObject {
    const fixedY = this.labMode
      ? Math.min(183, Math.round(this.floorY * 0.38))
      : Math.min(190, Math.round(this.floorY * 0.32));
    const loadX = this.canvas.width * (this.labMode ? 0.38 : 0.7);
    const loadStartY = this.floorY - 51;
    const pullX = this.canvas.width * (this.labMode ? 0.68 : 0.88);
    const load = this.addBox(loadX, loadStartY, 82, 82, {
      label: "들어 올릴 짐",
      color: "#f27a54",
      mass: 20,
      material: "wood",
      fixed: true,
    });
    this.guidedScene = {
      kind: "pulley-advantage",
      loadId: load.id,
      model: new PulleyAdvantageChallenge({
        loadMass: 20,
        gravity: Math.max(this.gravity, 0.01),
        supportStrands: 1,
      }),
      fixedY,
      loadX,
      loadStartY,
      pullX,
      pullStartY: fixedY + 113,
      handleDistance: 0,
      pullDistance: 0,
      maxLift: Math.max(0, loadStartY - fixedY - 90),
    };
    this.applyGuidedScenePoses();
    return load;
  }

  private removeGuidedApparatus(scene: GuidedMechanicsScene | null = this.guidedScene): void {
    if (!scene) return;
    const guidedIds = this.bodyIdsForScene(scene);
    for (const id of guidedIds) {
      this.simulation.removeBody(id);
      this.objects.delete(id);
      this.trails.delete(id);
    }
    if (this.selectedId && guidedIds.includes(this.selectedId)) this.selectedId = null;
    const archivedIndex = this.sandboxGuidedScenes.indexOf(scene);
    if (archivedIndex >= 0) this.sandboxGuidedScenes.splice(archivedIndex, 1);
    if (this.guidedScene === scene) this.guidedScene = this.sandboxGuidedScenes.pop() ?? null;
    this.challengeDrag = null;
    this.challengeDragOrigin = null;
    this.challengeDragPoint = null;
    this.challengeDragStartPullDistance = 0;
    this.challengeDragStartHandleDistance = 0;
    this.challengeScene = null;
  }

  private moveOrdinaryObjectsBelowApparatusHeader(): void {
    for (const object of this.objects.values()) {
      const body = this.simulation.getBody(object.id);
      if (!body) continue;
      const halfHeight = this.objectHalfExtents(object).y;
      if (body.state.position.y - halfHeight >= 170) continue;
      body.state.position.y = this.floorY - halfHeight - 12;
      body.state.velocity = { x: 0, y: 0 };
      body.state.acceleration = this.gravityAcceleration();
    }
    this.syncObjects();
    this.clearTrails();
  }

  private refreshOrbitAnalysis(): void {
    const orbit = this.orbitExperiment;
    if (!orbit) return;
    const body = this.simulation.getBody(orbit.bodyId);
    if (!body) return;
    orbit.analysis = orbit.challenge.analyze(body.state.position, body.state.velocity);
  }

  private registerObject(object: PlaygroundObject, options: PlaygroundObjectOptions): void {
    this.objects.set(object.id, object);
    this.trails.set(object.id, [{ x: object.x, y: object.y }]);
    this.simulation.addBody({
      id: object.id,
      radius: object.radius,
      collider: object.shape === "circle"
        ? { kind: "circle", radius: object.radius }
        : this.boxCollider(object),
      restitution: MATERIALS[object.material].restitution,
      staticFriction: MATERIALS[object.material].friction + 0.18,
      kineticFriction: MATERIALS[object.material].friction,
      fixed: options.fixed,
      state: {
        position: { x: object.x, y: object.y },
        velocity: this.toPixels(options.velocity ?? { x: 0, y: 0 }),
        acceleration: this.gravityAcceleration(),
        mass: options.mass ?? 1,
      },
    });
    this.select(object.id);
  }

  private replaceGravity(value: number): void {
    this.gravity = value;
    this.simulation.removeField("field.gravity.uniform");
    this.simulation.addField(new UniformGravityField({ x: 0, y: value * PIXELS_PER_METER }));
    this.frictionLaw?.setNormalAcceleration(value * PIXELS_PER_METER);
    this.buoyancyLaw?.setGravityAcceleration(value * PIXELS_PER_METER);
    this.sandboxWater?.setGravityAcceleration(value * PIXELS_PER_METER);
    this.surfaceFriction.setNormalAcceleration(value * PIXELS_PER_METER);
    for (const scene of this.allGuidedScenes()) {
      if (scene.kind === "lever" || scene.kind === "pulley-advantage") {
        scene.model.setGravity(Math.max(value, 0.01));
      }
    }
    this.simulation.refreshAccelerations();
    this.advanceGuidedScene(0);
  }

  private clearExperimentLaws(): void {
    if (this.springLaw) this.simulation.removeLaw(this.springLaw.id);
    if (this.frictionLaw) this.simulation.removeLaw(this.frictionLaw.id);
    if (this.buoyancyLaw) this.simulation.removeLaw(this.buoyancyLaw.id);
    if (this.orbitExperiment) this.simulation.removeField(this.orbitExperiment.field.id);
    for (const law of this.sandboxSpringLaws.values()) this.simulation.removeLaw(law.id);
    for (const law of this.forceLaws.values()) this.simulation.removeLaw(law.id);
    for (const source of this.gravitySources.values()) this.simulation.removeField(source.field.id);
    if (this.sandboxWater) this.simulation.removeLaw(this.sandboxWater.id);
    this.surfaceFriction.clearExcludedBodies();
    this.springLaw = null;
    this.sandboxSpringLaws.clear();
    this.frictionLaw = null;
    this.buoyancyLaw = null;
    this.guidedScene = null;
    this.sandboxGuidedScenes.length = 0;
    this.orbitExperiment = null;
    this.forceLaws.clear();
    this.gravitySources.clear();
    this.sandboxWater = null;
    this.forceDraggedId = null;
    this.rotatingId = null;
    this.challengeDrag = null;
    this.challengeDragOrigin = null;
    this.challengeDragPoint = null;
    this.challengeDragStartPullDistance = 0;
    this.challengeDragStartHandleDistance = 0;
    this.challengeScene = null;
    this.resetRopeConnectionState();
    this.impulseFlash = 0;
  }

  private resetRopeConnectionState(): void {
    this.ropeStartId = null;
    this.ropePointer = null;
    this.connectionKind = null;
    this.canvas.style.cursor = "grab";
  }

  private gravityAcceleration(): Vector2 {
    return { x: 0, y: this.gravity * PIXELS_PER_METER };
  }

  private allGuidedScenes(): GuidedMechanicsScene[] {
    return [...this.sandboxGuidedScenes, ...(this.guidedScene ? [this.guidedScene] : [])];
  }

  private bodyIdsForScene(scene: GuidedMechanicsScene): string[] {
    if (scene.kind === "lever" || scene.kind === "pulley-advantage") return [scene.loadId];
    return [scene.ropeId, scene.rodId];
  }

  private guidedBodyIds(): string[] {
    return this.allGuidedScenes().flatMap((scene) => this.bodyIdsForScene(scene));
  }

  private guidedSceneForBody(id: string): GuidedMechanicsScene | null {
    return this.allGuidedScenes().find((scene) => this.bodyIdsForScene(scene).includes(id)) ?? null;
  }

  private isGuidedBody(id: string): boolean { return this.guidedBodyIds().includes(id); }

  private setBodyPose(id: string, pose: KinematicPose): void {
    const body = this.simulation.getBody(id);
    if (!body) return;
    body.state.position = { ...pose.position };
    body.state.velocity = { ...pose.velocity };
    body.state.acceleration = { ...pose.acceleration };
  }

  private applyGuidedScenePoses(): void {
    for (const scene of this.allGuidedScenes()) this.applyGuidedScenePose(scene);
  }

  private applyGuidedScenePose(scene: GuidedMechanicsScene): void {
    if (scene.kind === "lever") {
      const loadPosition = {
        x: scene.center.x - Math.cos(scene.angle) * scene.model.loadArm,
        y: scene.center.y - Math.sin(scene.angle) * scene.model.loadArm - 42,
      };
      this.setBodyPose(scene.loadId, { position: loadPosition, velocity: { x: 0, y: 0 }, acceleration: { x: 0, y: 0 } });
    } else if (scene.kind === "constraints") {
      this.setBodyPose(scene.ropeId, scene.rope.pose());
      this.setBodyPose(scene.rodId, scene.rod.pose());
    } else {
      const lift = Math.min(scene.maxLift, scene.model.liftDistanceForPull(scene.pullDistance));
      this.setBodyPose(scene.loadId, {
        position: { x: scene.loadX, y: scene.loadStartY - lift },
        velocity: { x: 0, y: 0 },
        acceleration: { x: 0, y: 0 },
      });
    }
  }

  private advanceGuidedScene(dt: number): void {
    const gravity = this.gravity * PIXELS_PER_METER;
    for (const scene of this.allGuidedScenes()) {
      if (scene.kind === "constraints") {
        scene.rope.step(dt, gravity);
        scene.rod.step(dt, gravity);
      }
      this.applyGuidedScenePose(scene);
    }
  }

  private dragGuidedBody(id: string, point: Vector2): boolean {
    const scene = this.guidedSceneForBody(id);
    if (!scene) return false;
    if (scene.kind === "constraints") {
      (id === scene.ropeId ? scene.rope : scene.rod).moveTo(point);
    } else {
      return true;
    }
    this.advanceGuidedScene(0);
    this.clearTrails();
    return true;
  }

  private resizeGuidedScene(scaleX: number, scaleY: number): void {
    for (const scene of this.allGuidedScenes()) this.resizeOneGuidedScene(scene, scaleX, scaleY);
    this.applyGuidedScenePoses();
  }

  private resizeOneGuidedScene(scene: GuidedMechanicsScene, scaleX: number, scaleY: number): void {
    if (scene.kind === "constraints") {
      scene.rope.resize(scaleX, scaleY);
      scene.rod.resize(scaleX, scaleY);
    } else if (scene.kind === "lever") {
      scene.center = { x: scene.center.x * scaleX, y: scene.center.y * scaleY };
      scene.beamLength *= scaleX;
      scene.model.setLoadArm(scene.model.loadArm * scaleX);
      scene.model.setEffortArm(scene.model.effortArm * scaleX);
    } else {
      scene.fixedY *= scaleY;
      scene.loadX *= scaleX;
      scene.loadStartY *= scaleY;
      scene.pullX *= scaleX;
      scene.pullStartY *= scaleY;
      scene.handleDistance *= scaleY;
      scene.pullDistance *= scaleY;
      scene.maxLift *= scaleY;
    }
  }

  private frame(time: number): void {
    this.resizeToDisplaySize();
    const elapsed = Math.min((time - this.lastFrame) / 1000 || 0, 0.05);
    this.lastFrame = time;

    if (!this.paused && !this.draggedId) {
      this.accumulator += elapsed;
      let iterations = 0;
      while (this.accumulator >= FIXED_STEP && iterations < 12) {
        this.advance(FIXED_STEP);
        this.accumulator -= FIXED_STEP;
        iterations += 1;
      }
    }

    this.syncObjects();
    this.render();
    if (time - this.lastNotification > 80) {
      this.lastNotification = time;
      this.notify();
    }
    requestAnimationFrame((next) => this.frame(next));
  }

  private resizeToDisplaySize(): void {
    if (typeof this.canvas.getBoundingClientRect !== "function") return;
    const rect = this.canvas.getBoundingClientRect();
    const width = Math.round(rect.width);
    const height = Math.round(rect.height);
    if (width <= 0 || height <= FLOOR_HEIGHT || (width === this.canvas.width && height === this.canvas.height)) return;
    this.resizeWorld(width, height);
  }

  private resizeWorld(width: number, height: number): void {
    const previousWidth = this.canvas.width;
    const previousFloorY = this.floorY;
    const nextFloorY = height - FLOOR_HEIGHT;
    const scaleX = width / previousWidth;
    const scaleY = nextFloorY / previousFloorY;

    for (const springLaw of this.activeSpringLaws()) {
      const anchor = {
        x: springLaw.anchor.x * width / previousWidth,
        y: this.scaleBetweenBounds(springLaw.anchor.y, 14, previousFloorY, 14, nextFloorY),
      };
      springLaw.setGeometry(anchor, springLaw.restLength * width / previousWidth);
    }
    this.frictionLaw?.setSurfaceY(nextFloorY);
    this.surfaceFriction.setFloorY(nextFloorY);
    this.buoyancyLaw?.setWaterline(this.buoyancyLaw.waterline * scaleY);
    this.sandboxWater?.setWaterline(this.sandboxWater.waterline * scaleY);
    if (this.orbitExperiment) {
      const orbitScale = Math.min(scaleX, scaleY);
      const previousField = this.orbitExperiment.field;
      const sourcePosition = {
        x: previousField.sourcePosition.x * scaleX,
        y: previousField.sourcePosition.y * scaleY,
      };
      this.simulation.removeField(previousField.id);
      this.orbitExperiment.field = new PointGravityField(
        sourcePosition,
        previousField.sourceMass,
        previousField.G * orbitScale,
      );
      this.simulation.addField(this.orbitExperiment.field);
      this.orbitExperiment.guideRadius *= orbitScale;
      this.orbitExperiment.challenge = new OrbitChallenge({
        center: sourcePosition,
        gravitationalParameter: this.orbitExperiment.field.G * this.orbitExperiment.field.sourceMass,
        collisionRadius: 59 * orbitScale,
      });
    }
    this.resizeGuidedScene(scaleX, scaleY);

    for (const [id, object] of this.objects) {
      const body = this.simulation.getBody(id);
      if (!body || this.isGuidedBody(id)) continue;
      const { x: halfWidth, y: halfHeight } = this.objectHalfExtents(object);
      body.state.position = {
        x: this.scaleBetweenBounds(
          body.state.position.x,
          14 + halfWidth,
          previousWidth - 14 - halfWidth,
          14 + halfWidth,
          width - 14 - halfWidth,
        ),
        y: this.scaleBetweenBounds(
          body.state.position.y,
          14 + halfHeight,
          previousFloorY - halfHeight,
          14 + halfHeight,
          nextFloorY - halfHeight,
        ),
      };
      this.gravitySources.get(id)?.field.setSourcePosition(body.state.position);
    }
    for (let index = 0; index < this.simulation.constraints.length; index += 1) {
      const constraint = this.simulation.constraints[index];
      const a = this.simulation.getBody(constraint.bodyA);
      const b = this.simulation.getBody(constraint.bodyB);
      if (!a || !b) continue;
      this.simulation.constraints[index] = {
        ...constraint,
        distance: Math.hypot(
          b.state.position.x - a.state.position.x,
          b.state.position.y - a.state.position.y,
        ),
      };
    }
    if (this.ropePointer) {
      this.ropePointer = { x: this.ropePointer.x * scaleX, y: this.ropePointer.y * scaleY };
    }
    if (this.challengeDragOrigin) {
      this.challengeDragOrigin = { x: this.challengeDragOrigin.x * scaleX, y: this.challengeDragOrigin.y * scaleY };
    }
    if (this.challengeDragPoint) {
      this.challengeDragPoint = { x: this.challengeDragPoint.x * scaleX, y: this.challengeDragPoint.y * scaleY };
    }
    this.challengeDragStartPullDistance *= scaleY;
    this.challengeDragStartHandleDistance *= scaleY;

    this.canvas.width = width;
    this.canvas.height = height;
    this.syncObjects();
    this.clearTrails();
    this.simulation.refreshAccelerations();
    this.refreshOrbitAnalysis();
  }

  private scaleBetweenBounds(value: number, oldMin: number, oldMax: number, nextMin: number, nextMax: number): number {
    if (oldMax <= oldMin || nextMax <= nextMin) return nextMin;
    const ratio = Math.max(0, Math.min(1, (value - oldMin) / (oldMax - oldMin)));
    return nextMin + ratio * (nextMax - nextMin);
  }

  private advance(dt: number): void {
    const springPreviousPositions = new Map<string, Vector2>();
    for (const law of this.activeSpringLaws()) {
      const body = this.simulation.getBody(law.bodyId);
      if (body) springPreviousPositions.set(law.bodyId, { ...body.state.position });
    }
    this.simulation.step(dt);
    if (this.labMode && this.currentPreset === "collision" && !this.collisionResult && this.simulation.collisionEvents.length > 0) {
      const objects = [...this.objects.values()].slice(0, 2);
      const bodyA = objects[0] ? this.simulation.getBody(objects[0].id) : undefined;
      const bodyB = objects[1] ? this.simulation.getBody(objects[1].id) : undefined;
      if (bodyA && bodyB) {
        this.collisionResult = {
          velocityA: bodyA.state.velocity.x / PIXELS_PER_METER,
          velocityB: bodyB.state.velocity.x / PIXELS_PER_METER,
        };
      }
    }
    this.advanceGuidedScene(dt);
    for (const law of this.activeSpringLaws()) {
      this.resolveSpringMount(law, springPreviousPositions.get(law.bodyId) ?? null);
    }
    if ((this.currentPreset === "collision" || !this.labMode) && this.simulation.collisionEvents.length > 0) {
      this.impulseFlash = 1;
    } else {
      this.impulseFlash = Math.max(0, this.impulseFlash - dt * 2.5);
    }
    this.applyPresetDamping(dt);
    this.resolveWorldBounds();
    this.recordGraphProgress(dt);
    this.trailTick += 1;
    if (this.trailTick % 4 === 0) this.recordTrails();
  }

  private applyPresetDamping(dt: number): void {
    if (this.currentPreset !== "collision") return;
    const damping = Math.exp(-COLLISION_WORLD_DAMPING * dt);
    for (const body of this.simulation.allBodies) {
      if (body.fixed) continue;
      body.state.velocity.x *= damping;
      body.state.velocity.y *= damping;
      if (Math.hypot(body.state.velocity.x, body.state.velocity.y) < MOTION_SLEEP_SPEED) {
        body.state.velocity = { x: 0, y: 0 };
      }
    }
  }

  private resolveSpringMount(law: AnchoredSpringLaw, previousPosition: Vector2 | null): void {
    if (!previousPosition) return;
    const body = this.simulation.getBody(law.bodyId);
    const object = this.objects.get(law.bodyId);
    if (!body || !object) return;

    const minimumDistance = object.radius + SPRING_MOUNT_CLEARANCE;
    const start = {
      x: previousPosition.x - law.anchor.x,
      y: previousPosition.y - law.anchor.y,
    };
    const end = {
      x: body.state.position.x - law.anchor.x,
      y: body.state.position.y - law.anchor.y,
    };
    const movement = { x: end.x - start.x, y: end.y - start.y };
    const endDistance = Math.hypot(end.x, end.y);
    let normal: Vector2 | null = null;

    if (endDistance < minimumDistance) {
      const startDistance = Math.hypot(start.x, start.y);
      const direction = endDistance > 0.0001 ? end : start;
      const directionLength = endDistance > 0.0001 ? endDistance : startDistance;
      normal = directionLength > 0.0001
        ? { x: direction.x / directionLength, y: direction.y / directionLength }
        : { x: 1, y: 0 };
    } else {
      const a = movement.x ** 2 + movement.y ** 2;
      if (a === 0) return;
      const b = 2 * (start.x * movement.x + start.y * movement.y);
      const c = start.x ** 2 + start.y ** 2 - minimumDistance ** 2;
      const discriminant = b ** 2 - 4 * a * c;
      if (discriminant < 0) return;
      const contactTime = (-b - Math.sqrt(discriminant)) / (2 * a);
      if (contactTime < 0 || contactTime > 1) return;
      const contact = {
        x: start.x + movement.x * contactTime,
        y: start.y + movement.y * contactTime,
      };
      const contactLength = Math.hypot(contact.x, contact.y);
      if (contactLength === 0) return;
      normal = { x: contact.x / contactLength, y: contact.y / contactLength };
      if (movement.x * normal.x + movement.y * normal.y >= 0) return;
    }

    body.state.position = {
      x: law.anchor.x + normal.x * minimumDistance,
      y: law.anchor.y + normal.y * minimumDistance,
    };
    const inwardSpeed = body.state.velocity.x * normal.x + body.state.velocity.y * normal.y;
    if (inwardSpeed < 0) {
      body.state.velocity = {
        x: body.state.velocity.x - normal.x * inwardSpeed,
        y: body.state.velocity.y - normal.y * inwardSpeed,
      };
    }
    this.simulation.refreshAccelerations();
  }

  private resolveWorldBounds(): void {
    const margin = 14;
    for (const object of this.objects.values()) {
      const body = this.simulation.getBody(object.id);
      if (!body || this.isGuidedBody(object.id)) continue;
      const { x: halfWidth, y: halfHeight } = this.objectHalfExtents(object);
      const left = margin + halfWidth;
      const right = this.canvas.width - margin - halfWidth;
      const top = margin + halfHeight;
      const bottom = this.floorY - halfHeight;
      const restitution = body.restitution ?? 0.6;

      if (body.state.position.x < left) {
        body.state.position.x = left;
        if (body.state.velocity.x < 0) {
          body.state.velocity.x *= -restitution;
        }
      } else if (body.state.position.x > right) {
        body.state.position.x = right;
        if (body.state.velocity.x > 0) {
          body.state.velocity.x *= -restitution;
        }
      }

      if (body.state.position.y < top) {
        body.state.position.y = top;
        if (body.state.velocity.y < 0) {
          body.state.velocity.y *= -restitution;
        }
      } else if (body.state.position.y >= bottom) {
        body.state.position.y = bottom;
        if (body.state.velocity.y > 0) {
          const reboundSpeed = body.state.velocity.y * restitution;
          body.state.velocity.y = reboundSpeed < RESTING_REBOUND_SPEED ? 0 : -reboundSpeed;
        }
      }
    }
  }

  private recordTrails(): void {
    for (const object of this.objects.values()) {
      const body = this.simulation.getBody(object.id);
      if (!body) continue;
      const points = this.trails.get(object.id) ?? [];
      const last = points.at(-1);
      if (!last || Math.hypot(body.state.position.x - last.x, body.state.position.y - last.y) > 2) {
        points.push({ ...body.state.position });
      }
      if (points.length > 90) points.shift();
      this.trails.set(object.id, points);
    }
  }

  private syncObjects(): void {
    for (const [id, object] of this.objects) {
      const body = this.simulation.getBody(id);
      if (!body) continue;
      object.x = body.state.position.x;
      object.y = body.state.position.y;
    }
  }

  private render(): void {
    const { ctx, canvas } = this;
    const background = ctx.createLinearGradient(0, 0, 0, canvas.height);
    background.addColorStop(0, "#fbfdff");
    background.addColorStop(1, "#f3f6fb");
    ctx.fillStyle = background;
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    if (this.visualization.grid) this.drawGrid();
    if (this.buoyancyLaw || this.sandboxWater) this.drawWaterRegion();
    if (this.visualization.trails) this.drawTrails();
    this.drawGround();
    if (this.frictionLaw) {
      this.drawFrictionSurface();
      this.drawFrictionChallenge();
    }
    this.drawOrbitGuide();
    this.drawSandboxOrbitGuide();
    this.drawGuidedScene();
    this.drawSandboxRopes();
    for (const law of this.activeSpringLaws()) this.drawSpringConnection(law);
    this.drawTrajectoryPreview();
    for (const object of this.objects.values()) this.drawObject(object);
    this.drawAppliedForces();
    if (this.labMode && this.visualization.vectors) this.drawSelectedNetForce();
    if (this.currentPreset === "collision") this.drawMomentumVisualization();
    if (this.currentPreset === "spring") this.drawEnergyVisualization();
    if (!this.labMode && this.impulseFlash > 0) this.drawSandboxImpulseFeedback();
  }

  private drawSandboxImpulseFeedback(): void {
    const { ctx } = this;
    ctx.save();
    ctx.globalAlpha = this.impulseFlash;
    ctx.fillStyle = "#fff4c7";
    this.roundRect(this.canvas.width / 2 - 88, 24, 176, 40, 12);
    ctx.fill();
    ctx.fillStyle = "#8b6712";
    ctx.font = "800 15px Inter, system-ui, sans-serif";
    ctx.textAlign = "center";
    ctx.fillText("충격량이 전달됐어요", this.canvas.width / 2, 49);
    ctx.restore();
  }

  private drawWaterRegion(): void {
    const law = this.buoyancyLaw ?? this.sandboxWater;
    if (!law) return;
    const { ctx, canvas } = this;
    const water = ctx.createLinearGradient(0, law.waterline, 0, this.floorY);
    water.addColorStop(0, "#8cd5f080");
    water.addColorStop(1, "#4c9fdbb8");
    ctx.save();
    ctx.fillStyle = water;
    ctx.fillRect(0, law.waterline, canvas.width, this.floorY - law.waterline);
    ctx.strokeStyle = "#318dc9";
    ctx.lineWidth = 3;
    ctx.beginPath();
    for (let x = 0; x <= canvas.width; x += 12) {
      const y = law.waterline + Math.sin(x / 24) * 3;
      if (x === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
    }
    ctx.stroke();
    ctx.fillStyle = "#176c9f";
    ctx.font = "700 16px Inter, system-ui, sans-serif";
    ctx.fillText("물", 20, law.waterline + 28);
    ctx.restore();
  }

  private drawSandboxOrbitGuide(): void {
    if (this.labMode || this.gravitySources.size === 0 || !this.selectedId) return;
    const body = this.simulation.getBody(this.selectedId);
    const object = this.objects.get(this.selectedId);
    if (!body || !object || body.fixed) return;
    const source = [...this.gravitySources.entries()]
      .map(([id, entry]) => ({ id, ...entry }))
      .sort((a, b) => {
        const distanceA = Math.hypot(
          body.state.position.x - a.field.sourcePosition.x,
          body.state.position.y - a.field.sourcePosition.y,
        );
        const distanceB = Math.hypot(
          body.state.position.x - b.field.sourcePosition.x,
          body.state.position.y - b.field.sourcePosition.y,
        );
        return distanceA - distanceB;
      })[0];
    if (!source) return;
    const sourceObject = this.objects.get(source.id);
    const challenge = new OrbitChallenge({
      center: source.field.sourcePosition,
      gravitationalParameter: source.field.G * source.field.sourceMass,
      collisionRadius: (sourceObject?.radius ?? 38) + object.radius,
    });
    const analysis = challenge.analyze(body.state.position, body.state.velocity);
    const color = analysis.outcome === "crash"
      ? "#e05c3f"
      : analysis.outcome === "escape" ? "#a069dc" : "#25a77a";
    const { ctx } = this;
    ctx.save();
    ctx.strokeStyle = "#6681d755";
    ctx.lineWidth = 2;
    ctx.setLineDash([7, 7]);
    ctx.beginPath();
    ctx.arc(source.field.sourcePosition.x, source.field.sourcePosition.y, source.guideRadius, 0, Math.PI * 2);
    ctx.stroke();
    if (this.paused) {
      ctx.strokeStyle = color;
      ctx.lineWidth = 4;
      ctx.setLineDash([10, 6]);
      ctx.beginPath();
      analysis.path.forEach((point, index) => {
        if (index === 0) ctx.moveTo(point.x, point.y); else ctx.lineTo(point.x, point.y);
      });
      ctx.stroke();
    }
    ctx.restore();
  }

  private drawAppliedForces(): void {
    const { ctx } = this;
    for (const [id, law] of this.forceLaws) {
      const body = this.simulation.getBody(id);
      if (!body) continue;
      const handle = this.forceHandlePoint(law, body.state.position);
      ctx.save();
      ctx.strokeStyle = "#e05c3f";
      ctx.fillStyle = "#e05c3f";
      ctx.lineWidth = 5;
      ctx.beginPath();
      ctx.moveTo(body.state.position.x, body.state.position.y);
      ctx.lineTo(handle.x, handle.y);
      ctx.stroke();
      this.drawArrowHead(handle, law.vector, "#e05c3f", 12);
      ctx.beginPath();
      ctx.arc(handle.x, handle.y, 11, 0, Math.PI * 2);
      ctx.fill();
      ctx.font = "800 14px Inter, system-ui, sans-serif";
      ctx.textAlign = "center";
      const label = "주는 힘";
      const labelWidth = ctx.measureText(label).width;
      const labelX = Math.max(labelWidth / 2 + 8, Math.min(this.canvas.width - labelWidth / 2 - 8, handle.x));
      const desiredLabelY = handle.y - 18 < 18 ? handle.y + 31 : handle.y - 18;
      const labelY = Math.max(18, Math.min(this.floorY - 8, desiredLabelY));
      ctx.fillStyle = "#ffffffeb";
      this.roundRect(labelX - labelWidth / 2 - 6, labelY - 15, labelWidth + 12, 20, 7);
      ctx.fill();
      ctx.fillStyle = "#9f3d2b";
      ctx.fillText(label, labelX, labelY);
      ctx.restore();
    }
  }

  private drawSelectedNetForce(): void {
    if (!this.selectedId) return;
    const object = this.objects.get(this.selectedId);
    const diagram = this.forceDiagramFor(this.selectedId);
    if (!object || !diagram || diagram.balanced) return;
    this.drawArrow(
      object.x + 12,
      object.y,
      diagram.net.vector,
      5.2,
      diagram.net.color,
      "",
      this.floorY - 10,
    );
  }

  private drawOrbitGuide(): void {
    const orbit = this.orbitExperiment;
    if (!orbit) return;
    const { ctx } = this;
    const center = orbit.field.sourcePosition;
    ctx.save();
    ctx.strokeStyle = "#6681d788";
    ctx.lineWidth = 2;
    ctx.setLineDash([7, 7]);
    ctx.beginPath();
    ctx.arc(center.x, center.y, orbit.guideRadius, 0, Math.PI * 2);
    ctx.stroke();
    const outcomeColor = orbit.analysis.outcome === "crash"
      ? "#e05c3f"
      : orbit.analysis.outcome === "escape" ? "#a069dc" : "#25a77a";
    ctx.strokeStyle = outcomeColor;
    ctx.lineWidth = 4;
    ctx.setLineDash([10, 6]);
    ctx.beginPath();
    orbit.analysis.path.forEach((point, index) => {
      if (index === 0) ctx.moveTo(point.x, point.y); else ctx.lineTo(point.x, point.y);
    });
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.fillStyle = outcomeColor;
    ctx.font = "800 18px Inter, system-ui, sans-serif";
    const outcome = orbit.analysis.outcome === "crash"
      ? "행성과 충돌해요"
      : orbit.analysis.outcome === "escape" ? "궤도를 벗어나요" : "계속 공전해요";
    ctx.fillText(`예상: ${outcome}`, 24, 78);
    ctx.fillStyle = "#53699d";
    ctx.font = "700 15px Inter, system-ui, sans-serif";
    ctx.fillText("속도 화살표의 길이와 방향을 조금씩 바꿔 보세요", 24, 104);
    ctx.restore();
  }

  private drawGuidedScene(): void {
    const scenes = this.allGuidedScenes();
    if (scenes.length === 0) return;
    const { ctx } = this;
    ctx.save();
    ctx.lineCap = "round";
    ctx.lineJoin = "round";

    for (const scene of scenes) {
      if (scene.kind === "lever") {
        this.drawLeverChallenge(scene);
      } else if (scene.kind === "constraints") {
        this.drawConstraintLink(scene.rope.anchor, scene.rope.pose().position, false, "줄");
        this.drawConstraintLink(scene.rod.anchor, scene.rod.pose().position, true, "단단한 막대");
        this.drawPivot(scene.rope.anchor, "고정점");
        this.drawPivot(scene.rod.anchor, "고정점");
      } else {
        this.drawPulleyChallenge(scene);
      }
    }
    ctx.restore();
  }

  private drawLeverChallenge(scene: Extract<GuidedMechanicsScene, { kind: "lever" }>): void {
    const { ctx } = this;
    const compact = this.canvas.width < 520;
    const direction = { x: Math.cos(scene.angle), y: Math.sin(scene.angle) };
    const beamLeft = -(scene.model.loadArm + 64);
    const beamRight = scene.beamLength * 0.52;
    const effortFractions = [0.35, 0.6, 0.9] as const;
    const effortLabels = ["가까이", "중간", "멀리"] as const;

    ctx.save();
    ctx.shadowColor = "#25324a2f";
    ctx.shadowBlur = 10;
    ctx.shadowOffsetY = 7;
    ctx.fillStyle = "#8090a8";
    ctx.beginPath();
    ctx.moveTo(scene.center.x, scene.center.y + 5);
    ctx.lineTo(scene.center.x - 58, scene.center.y + 112);
    ctx.lineTo(scene.center.x + 58, scene.center.y + 112);
    ctx.closePath();
    ctx.fill();
    ctx.shadowColor = "transparent";
    ctx.fillStyle = "#5e6d84";
    this.roundRect(scene.center.x - 76, scene.center.y + 104, 152, 18, 7);
    ctx.fill();
    ctx.fillStyle = "#aeb9c8";
    ctx.beginPath();
    ctx.moveTo(scene.center.x, scene.center.y + 16);
    ctx.lineTo(scene.center.x - 40, scene.center.y + 100);
    ctx.lineTo(scene.center.x + 40, scene.center.y + 100);
    ctx.closePath();
    ctx.fill();
    ctx.restore();

    ctx.save();
    ctx.translate(scene.center.x, scene.center.y);
    ctx.rotate(scene.angle);
    ctx.shadowColor = "#17233b3d";
    ctx.shadowBlur = 9;
    ctx.shadowOffsetY = 6;
    const beamGradient = ctx.createLinearGradient(0, -12, 0, 12);
    beamGradient.addColorStop(0, "#71839d");
    beamGradient.addColorStop(0.5, "#43536b");
    beamGradient.addColorStop(1, "#2f3d53");
    ctx.fillStyle = beamGradient;
    this.roundRect(beamLeft, -12, beamRight - beamLeft, 24, 10);
    ctx.fill();
    ctx.shadowColor = "transparent";
    ctx.fillStyle = "#aeb9c8";
    this.roundRect(beamLeft + 7, -8, beamRight - beamLeft - 14, 5, 3);
    ctx.fill();
    ctx.strokeStyle = "#dce3ecaa";
    ctx.lineWidth = 2;
    for (let tick = -scene.model.loadArm; tick <= beamRight - 14; tick += 34) {
      ctx.beginPath();
      ctx.moveTo(tick, -10);
      ctx.lineTo(tick, tick % 68 === 0 ? -2 : -5);
      ctx.stroke();
    }
    ctx.fillStyle = "#495a72";
    this.roundRect(-scene.model.loadArm - 43, -17, 86, 10, 5);
    ctx.fill();
    ctx.restore();

    for (const [index, fraction] of effortFractions.entries()) {
      const arm = scene.beamLength * 0.52 * fraction;
      const selected = Math.abs(arm - scene.model.effortArm) < 4;
      const point = {
        x: scene.center.x + direction.x * arm,
        y: scene.center.y + direction.y * arm,
      };
      ctx.save();
      if (selected) {
        ctx.shadowColor = "#e05c3f66";
        ctx.shadowBlur = 12;
      }
      ctx.fillStyle = selected ? "#e05c3f" : "#f8fafc";
      ctx.strokeStyle = selected ? "#ffffff" : "#e05c3f";
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.arc(point.x, point.y, selected ? 11 : 8, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
      ctx.shadowColor = "transparent";
      ctx.fillStyle = selected ? "#c9472f" : "#66758a";
      ctx.font = `700 ${selected ? 14 : 13}px Inter, system-ui, sans-serif`;
      ctx.textAlign = "center";
      ctx.fillText(compact ? `${index + 1}` : effortLabels[index], point.x, point.y - 22);
      ctx.restore();
    }

    const handle = this.leverHandlePoint(scene);
    const effortPoint = {
      x: scene.center.x + direction.x * scene.model.effortArm,
      y: scene.center.y + direction.y * scene.model.effortArm,
    };
    ctx.strokeStyle = "#d7dee8";
    ctx.lineWidth = 8;
    ctx.beginPath();
    ctx.moveTo(effortPoint.x, effortPoint.y + 5);
    ctx.lineTo(handle.x, handle.y);
    ctx.stroke();
    ctx.strokeStyle = "#74839a";
    ctx.lineWidth = 3;
    ctx.stroke();
    ctx.save();
    ctx.shadowColor = "#d4472e4f";
    ctx.shadowBlur = 9;
    ctx.fillStyle = "#e05c3f";
    ctx.strokeStyle = "#e05c3f";
    this.roundRect(handle.x - 30, handle.y - 10, 60, 20, 10);
    ctx.fill();
    ctx.shadowColor = "transparent";
    ctx.fillStyle = "#ffb29f";
    this.roundRect(handle.x - 22, handle.y - 6, 44, 5, 3);
    ctx.fill();
    ctx.restore();
    ctx.fillStyle = "#c9472f";
    ctx.font = "800 14px Inter, system-ui, sans-serif";
    ctx.textAlign = "left";
    if (!compact) ctx.fillText("아래로 눌러요", handle.x + 40, handle.y + 5);

    ctx.fillStyle = "#ffffff";
    ctx.strokeStyle = "#34405a";
    ctx.lineWidth = 5;
    ctx.beginPath();
    ctx.arc(scene.center.x, scene.center.y, 13, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = "#34405a";
    ctx.beginPath();
    ctx.arc(scene.center.x, scene.center.y, 4, 0, Math.PI * 2);
    ctx.fill();
    ctx.font = "800 14px Inter, system-ui, sans-serif";
    ctx.textAlign = "center";
    ctx.fillText("받침점", scene.center.x, scene.center.y - 27);

    const distanceLabelPoint = {
      x: (scene.center.x + effortPoint.x) / 2,
      y: (scene.center.y + effortPoint.y) / 2 + 35,
    };
    ctx.strokeStyle = "#8a98aa";
    ctx.lineWidth = 2;
    ctx.setLineDash([5, 4]);
    ctx.beginPath();
    ctx.moveTo(scene.center.x + 12, scene.center.y + 30);
    ctx.lineTo(effortPoint.x, effortPoint.y + 30);
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.fillStyle = "#66758a";
    ctx.font = "700 13px Inter, system-ui, sans-serif";
    ctx.fillText(compact ? "힘점" : "선택한 힘점", distanceLabelPoint.x, distanceLabelPoint.y);

    const lifting = scene.model.applyForce(scene.appliedForce).lifting;
    ctx.fillStyle = lifting ? "#167b5a" : "#46546a";
    ctx.font = `800 ${compact ? 14 : 18}px Inter, system-ui, sans-serif`;
    ctx.textAlign = compact ? "center" : "left";
    ctx.fillText(
      lifting
        ? "들렸다! 힘이 충분해요"
        : compact ? "아래로 눌러 보세요" : "힘점을 골라 아래로 눌러 보세요",
      compact ? this.canvas.width / 2 : 24,
      compact ? 22 : 78,
    );
  }

  private drawPulleyChallenge(scene: Extract<GuidedMechanicsScene, { kind: "pulley-advantage" }>): void {
    const { ctx } = this;
    const compact = this.canvas.width < 520;
    const load = this.simulation.getBody(scene.loadId);
    if (!load) return;
    const fixedY = scene.fixedY;
    const movingY = load.state.position.y - 88;
    const guide = { x: scene.pullX, y: fixedY, radius: 18 };
    const fixedWheels: Array<{ x: number; y: number; radius: number }> = [];
    const movingWheels: Array<{ x: number; y: number; radius: number }> = [];

    ctx.save();
    ctx.shadowColor = "#26344c2f";
    ctx.shadowBlur = 8;
    ctx.shadowOffsetY = 5;
    ctx.fillStyle = "#68778d";
    this.roundRect(scene.loadX - 104, fixedY - 40, scene.pullX - scene.loadX + 138, 18, 7);
    ctx.fill();
    ctx.shadowColor = "transparent";
    ctx.fillStyle = "#aeb9c8";
    this.roundRect(scene.loadX - 96, fixedY - 36, scene.pullX - scene.loadX + 122, 5, 3);
    ctx.fill();
    ctx.restore();

    const traceRope = () => {
      ctx.beginPath();
      if (scene.model.supportStrands === 1) {
        const radius = 36;
        const fixed = { x: scene.loadX + radius, y: fixedY, radius };
        fixedWheels.push(fixed);
        ctx.moveTo(scene.loadX, load.state.position.y - 42);
        ctx.lineTo(scene.loadX, fixedY);
        ctx.arc(fixed.x, fixed.y, radius, Math.PI, Math.PI * 2);
        ctx.lineTo(guide.x - guide.radius, guide.y);
      } else if (scene.model.supportStrands === 2) {
        const lower = { x: scene.loadX, y: movingY, radius: 31 };
        const fixed = { x: scene.loadX + 70, y: fixedY, radius: 34 };
        movingWheels.push(lower);
        fixedWheels.push(fixed);
        ctx.moveTo(lower.x - lower.radius, fixedY - 52);
        ctx.lineTo(lower.x - lower.radius, lower.y);
        ctx.arc(lower.x, lower.y, lower.radius, Math.PI, 0, true);
        ctx.lineTo(fixed.x - fixed.radius, fixed.y);
        ctx.arc(fixed.x, fixed.y, fixed.radius, Math.PI, Math.PI * 2);
        ctx.lineTo(guide.x - guide.radius, guide.y);
      } else {
        const radius = 24;
        const lowerLeft = { x: scene.loadX - 48, y: movingY, radius };
        const upperLeft = { x: scene.loadX, y: fixedY, radius };
        const lowerRight = { x: scene.loadX + 48, y: movingY, radius };
        const upperRight = { x: scene.loadX + 96, y: fixedY, radius };
        movingWheels.push(lowerLeft, lowerRight);
        fixedWheels.push(upperLeft, upperRight);
        ctx.moveTo(lowerLeft.x - radius, fixedY - 52);
        ctx.lineTo(lowerLeft.x - radius, lowerLeft.y);
        ctx.arc(lowerLeft.x, lowerLeft.y, radius, Math.PI, 0, true);
        ctx.lineTo(upperLeft.x - radius, upperLeft.y);
        ctx.arc(upperLeft.x, upperLeft.y, radius, Math.PI, Math.PI * 2);
        ctx.lineTo(lowerRight.x - radius, lowerRight.y);
        ctx.arc(lowerRight.x, lowerRight.y, radius, Math.PI, 0, true);
        ctx.lineTo(upperRight.x - radius, upperRight.y);
        ctx.arc(upperRight.x, upperRight.y, radius, Math.PI, Math.PI * 2);
        ctx.lineTo(guide.x - guide.radius, guide.y);
      }
      ctx.arc(guide.x, guide.y, guide.radius, Math.PI, Math.PI / 2, true);
      ctx.lineTo(guide.x, this.pulleyHandlePoint(scene).y);
    };

    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.strokeStyle = "#31435f";
    ctx.lineWidth = 9;
    traceRope();
    ctx.stroke();
    fixedWheels.length = 0;
    movingWheels.length = 0;
    ctx.strokeStyle = "#75a4dd";
    ctx.lineWidth = 4;
    traceRope();
    ctx.stroke();

    const anchorX = scene.model.supportStrands === 1
      ? null
      : movingWheels[0].x - movingWheels[0].radius;
    if (anchorX !== null) this.drawPulleyAnchor({ x: anchorX, y: fixedY - 52 });

    if (movingWheels.length > 0) {
      const left = movingWheels[0].x - movingWheels[0].radius - 9;
      const rightWheel = movingWheels.at(-1)!;
      const right = rightWheel.x + rightWheel.radius + 9;
      ctx.fillStyle = "#6b7a90";
      this.roundRect(left, movingY - 12, right - left, 24, 8);
      ctx.fill();
      ctx.strokeStyle = "#34405a";
      ctx.lineWidth = 7;
      ctx.beginPath();
      ctx.moveTo(scene.loadX, movingY + 18);
      ctx.lineTo(scene.loadX, load.state.position.y - 42);
      ctx.stroke();
      ctx.fillStyle = "#34405a";
      ctx.beginPath();
      ctx.arc(scene.loadX, load.state.position.y - 42, 7, 0, Math.PI * 2);
      ctx.fill();
    } else {
      ctx.fillStyle = "#34405a";
      ctx.beginPath();
      ctx.arc(scene.loadX, load.state.position.y - 42, 7, 0, Math.PI * 2);
      ctx.fill();
    }
    for (const wheel of fixedWheels) this.drawPulleyWheel(wheel, false);
    for (const wheel of movingWheels) this.drawPulleyWheel(wheel, true);
    this.drawPulleyWheel(guide, false);

    const handle = this.pulleyHandlePoint(scene);
    ctx.save();
    ctx.shadowColor = "#c9472f55";
    ctx.shadowBlur = 9;
    ctx.fillStyle = "#e05c3f";
    this.roundRect(handle.x - 30, handle.y - 10, 60, 20, 10);
    ctx.fill();
    ctx.shadowColor = "transparent";
    ctx.fillStyle = "#ffb29f";
    this.roundRect(handle.x - 22, handle.y - 6, 44, 5, 3);
    ctx.fill();
    ctx.restore();
    ctx.fillStyle = "#c9472f";
    ctx.font = "800 14px Inter, system-ui, sans-serif";
    ctx.textAlign = "left";
    if (!compact) ctx.fillText("당기는 손잡이", handle.x + 38, handle.y + 5);

    ctx.font = "800 16px Inter, system-ui, sans-serif";
    ctx.textAlign = "center";
    for (const [index, strands] of ([1, 2, 4] as SupportStrands[]).entries()) {
      const x = this.canvas.width * 0.5 + (index - 1) * 104;
      ctx.fillStyle = scene.model.supportStrands === strands ? "#5b7cfa" : "#ffffff";
      ctx.strokeStyle = "#5b7cfa";
      ctx.lineWidth = 2;
      const buttonY = compact ? 12 : 66;
      const buttonHeight = compact ? 34 : 38;
      this.roundRect(x - 44, buttonY, 88, buttonHeight, buttonHeight / 2);
      ctx.fill();
      ctx.stroke();
      ctx.fillStyle = scene.model.supportStrands === strands ? "#ffffff" : "#3d568f";
      ctx.fillText(`${strands}줄`, x, buttonY + (compact ? 17 : 25));
      if (compact && scene.model.supportStrands === strands) {
        ctx.font = "800 10px Inter, system-ui, sans-serif";
        ctx.fillText("선택", x, buttonY + 30);
        ctx.font = "800 16px Inter, system-ui, sans-serif";
      }
    }
    ctx.textAlign = "left";
    ctx.fillStyle = "#34405a";
    ctx.font = "800 18px Inter, system-ui, sans-serif";
    if (!compact) ctx.fillText(
      `${scene.model.supportStrands}줄 도르래 · 손잡이를 아래로 당겨요`,
      24,
      130,
    );
    if (!compact) {
      ctx.font = "700 15px Inter, system-ui, sans-serif";
      ctx.fillText(
        "줄이 많으면 더 쉽게 들리지만 더 길게 당겨야 해요",
        24,
        154,
      );
    }
  }

  private drawPulleyWheel(
    wheel: { x: number; y: number; radius: number },
    moving: boolean,
  ): void {
    const { ctx } = this;
    ctx.save();
    ctx.shadowColor = "#1f2b4038";
    ctx.shadowBlur = 8;
    ctx.shadowOffsetY = 4;
    ctx.fillStyle = moving ? "#e7edf5" : "#f5f8fb";
    ctx.strokeStyle = "#34405a";
    ctx.lineWidth = 5;
    ctx.beginPath();
    ctx.arc(wheel.x, wheel.y, wheel.radius, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
    ctx.shadowColor = "transparent";
    ctx.strokeStyle = "#8b9aaf";
    ctx.lineWidth = Math.max(5, wheel.radius * 0.17);
    ctx.beginPath();
    ctx.arc(wheel.x, wheel.y, wheel.radius * 0.72, 0, Math.PI * 2);
    ctx.stroke();
    ctx.strokeStyle = "#5c6d84";
    ctx.lineWidth = 4;
    for (let spoke = 0; spoke < 6; spoke += 1) {
      const angle = spoke * Math.PI / 3;
      ctx.beginPath();
      ctx.moveTo(wheel.x, wheel.y);
      ctx.lineTo(
        wheel.x + Math.cos(angle) * wheel.radius * 0.62,
        wheel.y + Math.sin(angle) * wheel.radius * 0.62,
      );
      ctx.stroke();
    }
    ctx.fillStyle = moving ? "#e05c3f" : "#5b7cfa";
    ctx.strokeStyle = "#ffffff";
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.arc(wheel.x, wheel.y, Math.max(7, wheel.radius * 0.22), 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
    if (!moving) {
      ctx.strokeStyle = "#596a81";
      ctx.lineWidth = 6;
      ctx.beginPath();
      ctx.moveTo(wheel.x, wheel.y - wheel.radius - 5);
      ctx.lineTo(wheel.x, wheel.y - wheel.radius - 22);
      ctx.stroke();
    }
    ctx.restore();
  }

  private drawPulleyAnchor(point: Vector2): void {
    const { ctx } = this;
    ctx.save();
    ctx.strokeStyle = "#596a81";
    ctx.lineWidth = 6;
    ctx.beginPath();
    ctx.moveTo(point.x, point.y - 18);
    ctx.lineTo(point.x, point.y + 2);
    ctx.stroke();
    ctx.fillStyle = "#ffffff";
    ctx.strokeStyle = "#34405a";
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.arc(point.x, point.y + 7, 8, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
    ctx.restore();
  }

  private drawConstraintLink(start: Vector2, end: Vector2, rigid: boolean, label: string): void {
    const { ctx } = this;
    ctx.save();
    ctx.strokeStyle = rigid ? "#527a6d" : "#68758a";
    ctx.lineWidth = rigid ? 10 : 4;
    ctx.beginPath();
    ctx.moveTo(start.x, start.y);
    ctx.lineTo(end.x, end.y);
    ctx.stroke();
    ctx.fillStyle = rigid ? "#315d50" : "#536078";
    ctx.font = "700 14px Inter, system-ui, sans-serif";
    ctx.textAlign = "center";
    ctx.fillText(label, (start.x + end.x) / 2 + 18, (start.y + end.y) / 2);
    ctx.restore();
  }

  private drawSandboxRopes(): void {
    const { ctx } = this;
    ctx.save();
    ctx.lineCap = "round";
    for (const constraint of this.simulation.constraints) {
      const kind = constraint.id.startsWith("sandbox-rod-")
        ? "rod"
        : constraint.id.startsWith("sandbox-rope-") ? "rope" : null;
      if (!kind) continue;
      const a = this.simulation.getBody(constraint.bodyA);
      const b = this.simulation.getBody(constraint.bodyB);
      if (!a || !b) continue;
      ctx.strokeStyle = kind === "rod" ? "#456c61" : "#33435d";
      ctx.lineWidth = kind === "rod" ? 11 : 7;
      ctx.beginPath();
      ctx.moveTo(a.state.position.x, a.state.position.y);
      ctx.lineTo(b.state.position.x, b.state.position.y);
      ctx.stroke();
      ctx.strokeStyle = kind === "rod" ? "#a8cbbb" : "#79a7d8";
      ctx.lineWidth = kind === "rod" ? 4 : 3;
      ctx.stroke();
    }

    const start = this.ropeStartId ? this.simulation.getBody(this.ropeStartId) : undefined;
    if (start && this.ropePointer) {
      const rigid = this.connectionKind === "rod";
      ctx.strokeStyle = rigid ? "#4e7b6daa" : "#5575e8aa";
      ctx.lineWidth = rigid ? 8 : 4;
      ctx.setLineDash(rigid ? [] : [9, 8]);
      ctx.beginPath();
      ctx.moveTo(start.state.position.x, start.state.position.y);
      ctx.lineTo(this.ropePointer.x, this.ropePointer.y);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.fillStyle = "#5575e8";
      ctx.beginPath();
      ctx.arc(start.state.position.x, start.state.position.y, 6, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  }

  private drawPivot(point: Vector2, label: string, labelOffset = 17): void {
    const { ctx } = this;
    ctx.save();
    ctx.fillStyle = "#ffffff";
    ctx.strokeStyle = "#34405a";
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.arc(point.x, point.y, 9, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = "#34405a";
    ctx.font = "700 14px Inter, system-ui, sans-serif";
    ctx.textAlign = "center";
    ctx.fillText(label, point.x, point.y - labelOffset);
    ctx.restore();
  }

  private drawMomentumVisualization(): void {
    const compact = this.canvas.width < 520;
    const collisionObjects = [...this.objects.values()].slice(0, 2);
    for (const object of collisionObjects) {
      const body = this.simulation.getBody(object.id);
      if (!body) continue;
      this.drawArrow(
        object.x,
        object.y,
        { x: body.state.velocity.x * body.state.mass, y: body.state.velocity.y * body.state.mass },
        0.16,
        "#196ba0",
        compact ? "" : "운동량 p = mv",
      );
    }
    const forcePairAlpha = Math.max(this.impulseFlash, this.collisionResult ? 0.78 : 0);
    if (forcePairAlpha <= 0) return;
    const { ctx } = this;
    const centerX = this.canvas.width / 2; const diagramY = compact ? 54 : 136;
    if (compact) {
      ctx.save(); ctx.globalAlpha = forcePairAlpha; ctx.fillStyle = "#ffffffee";
      this.roundRect(centerX - 142, 16, 284, 66, 12); ctx.fill();
      ctx.fillStyle = "#42516a"; ctx.font = "800 13px Inter, system-ui, sans-serif"; ctx.textAlign = "center";
      ctx.fillText("충돌 순간의 힘", centerX, 38);
      this.drawArrow(centerX - 12, 60, { x: -68, y: 0 }, 1, "#e05c3f", "");
      this.drawArrow(centerX + 12, 60, { x: 68, y: 0 }, 1, "#25a77a", "");
      ctx.restore();
      return;
    }
    ctx.save(); ctx.globalAlpha = forcePairAlpha; ctx.fillStyle = "#ffffffee";
    this.roundRect(centerX - 190, diagramY - 54, 380, 112, 13); ctx.fill();
    ctx.fillStyle = "#42516a"; ctx.font = "800 15px Inter, system-ui, sans-serif"; ctx.textAlign = "center";
    ctx.fillText("충돌 순간 · 크기가 같고 방향이 반대인 힘", centerX, diagramY - 29);
    this.drawArrow(centerX - 16, diagramY + 5, { x: -105, y: 0 }, 1, "#e05c3f", "");
    this.drawArrow(centerX + 16, diagramY + 5, { x: 105, y: 0 }, 1, "#25a77a", "");
    ctx.font = "700 13px Inter, system-ui, sans-serif";
    ctx.fillStyle = "#e05c3f"; ctx.fillText("물체 1이 받은 힘", centerX - 72, diagramY + 39);
    ctx.fillStyle = "#25a77a"; ctx.fillText("물체 2가 받은 힘", centerX + 72, diagramY + 39);
    ctx.restore();
    ctx.save();
    ctx.globalAlpha = this.impulseFlash;
    ctx.fillStyle = "#fff4c7";
    this.roundRect(this.canvas.width / 2 - 80, 32, 160, 42, 12);
    ctx.fill();
    ctx.fillStyle = "#8b6712";
    ctx.font = "800 16px Inter, system-ui, sans-serif";
    ctx.textAlign = "center";
    ctx.fillText("충격량이 전달됐어요", this.canvas.width / 2, 58);
    ctx.restore();
  }

  private drawEnergyVisualization(): void {
    const law = this.springLaw;
    if (!law) return;
    const body = this.simulation.getBody(law.bodyId);
    if (!body) return;
    const speedSquared = body.state.velocity.x ** 2 + body.state.velocity.y ** 2;
    const kinetic = 0.5 * body.state.mass * speedSquared;
    const distance = Math.hypot(body.state.position.x - law.anchor.x, body.state.position.y - law.anchor.y);
    const spring = 0.5 * law.stiffness * (distance - law.restLength) ** 2;
    const total = Math.max(1, kinetic + spring);
    const x = 24;
    const y = 54;
    const width = Math.min(280, this.canvas.width * 0.3);
    const { ctx } = this;
    ctx.save();
    ctx.fillStyle = "#ffffffdd";
    this.roundRect(x, y, width, 66, 12);
    ctx.fill();
    ctx.fillStyle = "#536078";
    ctx.font = "700 14px Inter, system-ui, sans-serif";
    ctx.fillText("움직임 에너지", x + 12, y + 22);
    ctx.fillText("용수철 에너지", x + 12, y + 49);
    ctx.fillStyle = "#5b7cfa";
    ctx.fillRect(x + 126, y + 11, (width - 140) * kinetic / total, 12);
    ctx.fillStyle = "#a069dc";
    ctx.fillRect(x + 126, y + 38, (width - 140) * spring / total, 12);
    ctx.restore();
  }

  private drawGrid(): void {
    const { ctx, canvas } = this;
    ctx.save();
    ctx.lineWidth = 1;
    for (let x = 40; x < canvas.width; x += 40) {
      ctx.strokeStyle = x % 200 === 0 ? "#dbe3ef" : "#e9eef6";
      ctx.beginPath();
      ctx.moveTo(x, 0);
      ctx.lineTo(x, this.floorY);
      ctx.stroke();
    }
    for (let y = 40; y < this.floorY; y += 40) {
      ctx.strokeStyle = y % 200 === 0 ? "#dbe3ef" : "#e9eef6";
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(canvas.width, y);
      ctx.stroke();
    }
    ctx.restore();
  }

  private drawTrails(): void {
    const { ctx } = this;
    ctx.save();
    ctx.lineWidth = 2.5;
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    for (const [id, points] of this.trails) {
      if (points.length < 2) continue;
      const object = this.objects.get(id);
      if (!object) continue;
      ctx.strokeStyle = `${object.color}55`;
      ctx.beginPath();
      points.forEach((point, index) => index === 0 ? ctx.moveTo(point.x, point.y) : ctx.lineTo(point.x, point.y));
      ctx.stroke();
    }
    ctx.restore();
  }

  private drawGround(): void {
    const { ctx, canvas } = this;
    const ground = ctx.createLinearGradient(0, this.floorY, 0, canvas.height);
    ground.addColorStop(0, "#dce7e1");
    ground.addColorStop(1, "#cbdad3");
    ctx.fillStyle = ground;
    ctx.fillRect(0, this.floorY, canvas.width, canvas.height - this.floorY);
    ctx.fillStyle = "#9cb7aa";
    ctx.fillRect(0, this.floorY, canvas.width, 3);
    ctx.save();
    ctx.strokeStyle = "#b4c8be";
    for (let x = -30; x < canvas.width; x += 24) {
      ctx.beginPath();
      ctx.moveTo(x, canvas.height);
      ctx.lineTo(x + 48, this.floorY);
      ctx.stroke();
    }
    ctx.restore();
  }

  private drawFrictionSurface(): void {
    const { ctx, canvas } = this;
    ctx.save();
    ctx.fillStyle = "#f4d681";
    ctx.fillRect(0, this.floorY, canvas.width, 8);
    ctx.strokeStyle = "#c7962c";
    ctx.lineWidth = 2;
    for (let x = 8; x < canvas.width; x += 18) {
      ctx.beginPath();
      ctx.moveTo(x, this.floorY + 1);
      ctx.lineTo(x + 7, this.floorY + 7);
      ctx.stroke();
    }
    ctx.fillStyle = "#856116";
    ctx.font = "700 14px Inter, system-ui, sans-serif";
    ctx.fillText("마찰이 있는 바닥", 18, this.floorY - 14);
    ctx.restore();
  }

  private drawFrictionChallenge(): void {
    const law = this.frictionLaw;
    const object = law ? this.objects.get(law.bodyId) : undefined;
    const body = law ? this.simulation.getBody(law.bodyId) : undefined;
    if (!law || !object || !body) return;
    const { ctx } = this;
    const handle = this.frictionHandlePoint();
    const moving = law.status(body.state) === "moving";

    ctx.save();
    ctx.strokeStyle = moving ? "#e05c3f" : "#5b7cfa";
    ctx.lineWidth = 6;
    ctx.beginPath();
    ctx.moveTo(object.x + object.width / 2, object.y);
    ctx.lineTo(handle.x, handle.y);
    ctx.stroke();
    ctx.fillStyle = moving ? "#e05c3f" : "#ffffff";
    ctx.strokeStyle = "#e05c3f";
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.arc(handle.x, handle.y, 16, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = moving ? "#167b5a" : "#34405a";
    ctx.font = "800 18px Inter, system-ui, sans-serif";
    ctx.fillText(
      moving
        ? "움직였다! 주는 힘이 마찰을 이겼어요"
        : "버티는 중 · 마찰이 움직임을 막고 있어요",
      24,
      78,
    );
    ctx.font = "700 15px Inter, system-ui, sans-serif";
    ctx.fillStyle = "#536078";
    ctx.fillText("빨간 손잡이를 좌우로 밀거나 당겨 보세요", 24, 104);
    ctx.restore();
  }

  private drawSpringConnection(law: AnchoredSpringLaw): void {
    const body = this.simulation.getBody(law.bodyId);
    const object = this.objects.get(law.bodyId);
    if (!body || !object) return;
    const start = law.anchor;
    const centerDx = body.state.position.x - start.x;
    const centerDy = body.state.position.y - start.y;
    const centerDistance = Math.hypot(centerDx, centerDy);
    if (centerDistance === 0) return;
    const nx = centerDx / centerDistance;
    const ny = centerDy / centerDistance;
    const px = -ny;
    const py = nx;
    const end = {
      x: body.state.position.x - nx * Math.max(0, object.radius - 3),
      y: body.state.position.y - ny * Math.max(0, object.radius - 3),
    };
    const dx = end.x - start.x;
    const dy = end.y - start.y;
    const length = Math.hypot(dx, dy);
    const equilibrium = {
      x: start.x + nx * law.restLength,
      y: start.y + ny * law.restLength,
    };
    const { ctx } = this;
    const leadLength = Math.min(28, length * 0.11);
    const tailLength = Math.min(24, length * 0.09);
    const coilLength = Math.max(0, length - leadLength - tailLength);
    const coilStart = { x: start.x + nx * leadLength, y: start.y + ny * leadLength };
    const coilEnd = { x: end.x - nx * tailLength, y: end.y - ny * tailLength };
    const turns = 11;
    const amplitude = Math.max(5, Math.min(12, coilLength * 0.055));
    const samples = turns * 20;

    const traceSpring = (): void => {
      ctx.beginPath();
      ctx.moveTo(start.x, start.y);
      ctx.lineTo(coilStart.x, coilStart.y);
      for (let sample = 1; sample <= samples; sample += 1) {
        const progress = sample / samples;
        const along = coilLength * progress;
        const offset = Math.sin(progress * turns * Math.PI * 2) * amplitude;
        ctx.lineTo(
          coilStart.x + nx * along + px * offset,
          coilStart.y + ny * along + py * offset,
        );
      }
      ctx.lineTo(coilEnd.x, coilEnd.y);
      ctx.lineTo(end.x, end.y);
    };

    ctx.save();

    // The equilibrium position is a reference mark, not another object.
    ctx.strokeStyle = "#8157ba77";
    ctx.lineWidth = 2;
    ctx.setLineDash([5, 5]);
    ctx.beginPath();
    ctx.moveTo(equilibrium.x - px * 19, equilibrium.y - py * 19);
    ctx.lineTo(equilibrium.x + px * 19, equilibrium.y + py * 19);
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.fillStyle = "#8157ba";
    ctx.font = "700 14px Inter, system-ui, sans-serif";
    ctx.textAlign = "center";
    ctx.fillText("제자리", equilibrium.x + px * 32, equilibrium.y + py * 32);

    // A fixed bracket makes the anchor read as a mounted end of the spring.
    const bracketX = start.x - nx * 12;
    const bracketY = start.y - ny * 12;
    ctx.strokeStyle = "#d7deea";
    ctx.lineWidth = 15;
    ctx.lineCap = "round";
    ctx.beginPath();
    ctx.moveTo(bracketX - px * 28, bracketY - py * 28);
    ctx.lineTo(bracketX + px * 28, bracketY + py * 28);
    ctx.stroke();
    ctx.strokeStyle = "#44516a";
    ctx.lineWidth = 8;
    ctx.stroke();
    ctx.strokeStyle = "#8b97aa";
    ctx.lineWidth = 2;
    for (let offset = -22; offset <= 22; offset += 11) {
      const hatchX = bracketX + px * offset;
      const hatchY = bracketY + py * offset;
      ctx.beginPath();
      ctx.moveTo(hatchX - nx * 7 - px * 4, hatchY - ny * 7 - py * 4);
      ctx.lineTo(hatchX + nx * 7 + px * 4, hatchY + ny * 7 + py * 4);
      ctx.stroke();
    }

    // Layered strokes give the coil a rounded metal-wire appearance.
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.shadowColor = "#4b2e7444";
    ctx.shadowBlur = 6;
    ctx.shadowOffsetY = 3;
    ctx.strokeStyle = "#5f3d91";
    ctx.lineWidth = 7;
    traceSpring();
    ctx.stroke();
    ctx.shadowColor = "transparent";
    const springHighlight = ctx.createLinearGradient(start.x, start.y, end.x, end.y);
    springHighlight.addColorStop(0, "#d7b8f3");
    springHighlight.addColorStop(0.48, "#9d6fd0");
    springHighlight.addColorStop(1, "#cda8ed");
    ctx.strokeStyle = springHighlight;
    ctx.lineWidth = 3;
    traceSpring();
    ctx.stroke();

    ctx.fillStyle = "#ffffff";
    ctx.strokeStyle = "#44516a";
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.arc(start.x, start.y, 7, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();

    ctx.fillStyle = "#8f61c2";
    ctx.strokeStyle = "#ffffff";
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(end.x, end.y, 5, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();

    ctx.fillStyle = "#34405a";
    ctx.fillText("고정점", start.x - nx * 5 - px * 24, start.y - ny * 5 - py * 24);
    ctx.restore();
  }

  private drawTrajectoryPreview(): void {
    if (!this.paused || !this.selectedId) return;
    if (this.springForBody(this.selectedId) || this.isGuidedBody(this.selectedId)) return;
    const object = this.objects.get(this.selectedId);
    const body = this.simulation.getBody(this.selectedId);
    if (!object || !body || body.fixed || Math.hypot(body.state.velocity.x, body.state.velocity.y) < VELOCITY_IDLE_EPSILON) return;
    const points = this.predictedPath(object, body.state.velocity, body.state.acceleration);
    if (points.length < 2) return;

    const { ctx } = this;
    ctx.save();
    ctx.strokeStyle = "#7257d599";
    ctx.lineWidth = 3;
    ctx.lineCap = "round";
    ctx.setLineDash([5, 8]);
    ctx.beginPath();
    ctx.moveTo(points[0].x, points[0].y);
    for (const point of points.slice(1)) ctx.lineTo(point.x, point.y);
    ctx.stroke();
    ctx.restore();
  }

  private predictedPath(object: PlaygroundObject, velocity: Vector2, acceleration: Vector2): Vector2[] {
    const points: Vector2[] = [{ x: object.x, y: object.y }];
    const halfWidth = object.shape === "circle" ? object.radius : object.width / 2;
    const halfHeight = object.shape === "circle" ? object.radius : object.height / 2;
    const minX = 14 + halfWidth;
    const maxX = this.canvas.width - 14 - halfWidth;
    const minY = 14 + halfHeight;
    const maxY = this.floorY - halfHeight;

    for (let step = 1; step <= TRAJECTORY_PREVIEW_STEPS; step += 1) {
      const time = step * TRAJECTORY_PREVIEW_STEP;
      const point = {
        x: object.x + velocity.x * time + 0.5 * acceleration.x * time ** 2,
        y: object.y + velocity.y * time + 0.5 * acceleration.y * time ** 2,
      };
      if (point.x < minX || point.x > maxX || point.y < minY || point.y > maxY) break;
      points.push(point);
      if (this.previewHitsObject(point, object)) break;
    }
    return points;
  }

  private previewHitsObject(point: Vector2, movingObject: PlaygroundObject): boolean {
    for (const object of this.objects.values()) {
      if (object.id === movingObject.id) continue;
      const combinedRadius = movingObject.radius + object.radius;
      if (Math.hypot(point.x - object.x, point.y - object.y) <= combinedRadius) return true;
    }
    return false;
  }

  private drawAnchorObject(object: PlaygroundObject, selected: boolean): void {
    const { ctx } = this;
    ctx.save();
    ctx.shadowColor = selected ? "#5575e877" : "#22304a2f";
    ctx.shadowBlur = selected ? 16 : 8;
    if (selected) {
      ctx.fillStyle = "#ffffff";
      ctx.beginPath();
      ctx.arc(object.x, object.y, object.radius + 7, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.fillStyle = "#34405a";
    ctx.beginPath();
    ctx.arc(object.x, object.y, object.radius, 0, Math.PI * 2);
    ctx.fill();
    ctx.shadowColor = "transparent";
    ctx.fillStyle = selected ? "#5575e8" : object.color;
    ctx.beginPath();
    ctx.arc(object.x, object.y, object.radius - 4, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = "#ffffff";
    ctx.beginPath();
    ctx.arc(object.x, object.y, 4, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = "#ffffffaa";
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(object.x - 6, object.y);
    ctx.lineTo(object.x + 6, object.y);
    ctx.moveTo(object.x, object.y - 6);
    ctx.lineTo(object.x, object.y + 6);
    ctx.stroke();
    ctx.restore();
  }

  private drawObject(object: PlaygroundObject): void {
    const { ctx } = this;
    const selected = object.id === this.selectedId;
    const body = this.simulation.getBody(object.id);
    if (!body) return;

    if (object.anchor) {
      this.drawAnchorObject(object, selected);
      this.drawLabel(object);
      return;
    }

    ctx.save();
    ctx.shadowColor = selected ? `${object.color}77` : "#22304a22";
    ctx.shadowBlur = selected ? 18 : 9;
    ctx.shadowOffsetY = selected ? 0 : 5;
    if (object.shape === "box" && object.angle !== 0) {
      ctx.translate(object.x, object.y);
      ctx.rotate(object.angle);
      ctx.translate(-object.x, -object.y);
    }
    if (selected) {
      ctx.strokeStyle = "#ffffff";
      ctx.lineWidth = 7;
      if (object.shape === "circle") {
        ctx.beginPath();
        ctx.arc(object.x, object.y, object.radius + 6, 0, Math.PI * 2);
      } else {
        this.roundRect(
          object.x - object.width / 2 - 6,
          object.y - object.height / 2 - 6,
          object.width + 12,
          object.height + 12,
          14,
        );
      }
      ctx.stroke();
      ctx.strokeStyle = object.color;
      ctx.lineWidth = 2.5;
      ctx.stroke();
    }

    if (object.shape === "circle") {
      const fill = ctx.createRadialGradient(
        object.x - object.radius * 0.35,
        object.y - object.radius * 0.4,
        object.radius * 0.12,
        object.x,
        object.y,
        object.radius,
      );
      fill.addColorStop(0, "#ffffff");
      fill.addColorStop(0.18, object.color);
      fill.addColorStop(1, this.shadeColor(object.color, -22));
      ctx.fillStyle = fill;
      ctx.beginPath();
      ctx.arc(object.x, object.y, object.radius, 0, Math.PI * 2);
      ctx.fill();
    } else {
      const left = object.x - object.width / 2;
      const top = object.y - object.height / 2;
      const fill = ctx.createLinearGradient(left, top, left, top + object.height);
      fill.addColorStop(0, this.shadeColor(object.color, 18));
      fill.addColorStop(1, this.shadeColor(object.color, -18));
      ctx.fillStyle = fill;
      this.roundRect(left, top, object.width, object.height, 10);
      ctx.fill();
    }
    ctx.restore();

    this.drawLabel(object);
    if (selected) {
      if (this.isGuidedBody(object.id)) {
        if (this.visualization.vectors) {
          this.drawArrow(object.x, object.y, body.state.velocity, 0.22, "#7257d5", "");
        }
      } else if (!body.fixed && this.frictionLaw?.bodyId !== object.id) {
        this.drawVelocityControl(object, body.state.velocity, !this.labMode);
      }
      if (
        this.visualization.vectors
        && this.frictionLaw?.bodyId !== object.id
        && (!body.fixed || this.isGuidedBody(object.id))
      ) {
        this.drawArrow(
          object.x + (this.labMode ? -12 : 0),
          object.y,
          body.state.acceleration,
          0.14,
          "#e05c3f",
          this.labMode ? "" : "가속도",
          undefined,
          !this.labMode && this.forceLaws.has(object.id),
        );
      }
      if (this.isResizableBlock(object, body)) this.drawResizeHandles(object);
    }
  }

  private drawResizeHandles(object: PlaygroundObject): void {
    const { ctx } = this;
    ctx.save();
    ctx.fillStyle = "#ffffff";
    ctx.strokeStyle = "#365eea";
    ctx.lineWidth = 3;
    ctx.lineCap = "round";
    for (const handle of this.resizeHandles(object)) {
      ctx.beginPath();
      ctx.arc(handle.x, handle.y, 8, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
      ctx.beginPath();
      if (handle.kind !== "height") {
        ctx.moveTo(handle.x - 3, handle.y);
        ctx.lineTo(handle.x + 3, handle.y);
      }
      if (handle.kind !== "width") {
        ctx.moveTo(handle.x, handle.y - 3);
        ctx.lineTo(handle.x, handle.y + 3);
      }
      ctx.stroke();
    }
    const top = this.localToWorld(object, { x: 0, y: -object.height / 2 });
    const rotation = this.rotationHandlePoint(object);
    ctx.beginPath();
    ctx.moveTo(top.x, top.y);
    ctx.lineTo(rotation.x, rotation.y);
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(rotation.x, rotation.y, 9, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = "#365eea";
    ctx.font = "800 13px Inter, system-ui, sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText("↻", rotation.x, rotation.y + 0.5);
    ctx.restore();
  }

  private drawLabel(object: PlaygroundObject): void {
    const { ctx } = this;
    const objectScene = this.guidedSceneForBody(object.id);
    if (objectScene?.kind === "pulley-advantage" && objectScene.loadId === object.id) {
      ctx.save();
      ctx.font = "800 16px Inter, system-ui, sans-serif";
      ctx.textAlign = "center";
      ctx.fillStyle = "#ffffff";
      ctx.shadowColor = "#91321f66";
      ctx.shadowBlur = 4;
      ctx.fillText(object.label, object.x, object.y + 5);
      ctx.restore();
      return;
    }
    ctx.save();
    ctx.font = "600 14px Inter, system-ui, sans-serif";
    ctx.textAlign = "center";
    const labelY = object.y - this.objectHalfExtents(object).y - 14;
    const width = ctx.measureText(object.label).width + 14;
    ctx.fillStyle = "#ffffffdd";
    this.roundRect(object.x - width / 2, labelY - 13, width, 20, 8);
    ctx.fill();
    ctx.fillStyle = "#33405a";
    ctx.fillText(object.label, object.x, labelY + 1);
    ctx.restore();
  }

  private drawVelocityControl(object: PlaygroundObject, velocity: Vector2, showLabel = true): void {
    const idle = Math.hypot(velocity.x, velocity.y) < VELOCITY_IDLE_EPSILON;
    const vector = this.velocityControlVector(object, velocity);
    const endX = object.x + vector.x;
    const endY = object.y + vector.y;
    const angle = Math.atan2(vector.y, vector.x);
    const { ctx } = this;

    ctx.save();
    ctx.strokeStyle = idle ? "#7257d588" : "#7257d5";
    ctx.fillStyle = "#7257d5";
    ctx.lineWidth = 3;
    ctx.lineCap = "round";
    if (idle) ctx.setLineDash([6, 5]);
    ctx.beginPath();
    ctx.moveTo(object.x, object.y);
    ctx.lineTo(endX, endY);
    ctx.stroke();
    ctx.setLineDash([]);
    if (!idle) {
      ctx.beginPath();
      ctx.moveTo(endX, endY);
      ctx.lineTo(endX - 10 * Math.cos(angle - Math.PI / 6), endY - 10 * Math.sin(angle - Math.PI / 6));
      ctx.lineTo(endX - 10 * Math.cos(angle + Math.PI / 6), endY - 10 * Math.sin(angle + Math.PI / 6));
      ctx.closePath();
      ctx.fill();
    }
    ctx.fillStyle = "#ffffff";
    ctx.strokeStyle = "#7257d5";
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.arc(endX, endY, 7, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
    if (showLabel) {
      ctx.fillStyle = "#7257d5";
      ctx.font = "700 14px Inter, system-ui, sans-serif";
      const label = idle ? "여기서 끌어 보세요" : `속도 · ${this.displayAngle(velocity)}°`;
      const labelWidth = ctx.measureText(label).width;
      const labelX = Math.max(labelWidth / 2 + 8, Math.min(this.canvas.width - labelWidth / 2 - 8, endX));
      const desiredLabelY = endY - 10 < 18 ? endY + 29 : endY - 10;
      const labelY = Math.max(18, Math.min(this.floorY - 8, desiredLabelY));
      ctx.textAlign = "center";
      ctx.fillStyle = "#ffffffeb";
      this.roundRect(labelX - labelWidth / 2 - 6, labelY - 15, labelWidth + 12, 20, 7);
      ctx.fill();
      ctx.fillStyle = "#7257d5";
      ctx.fillText(label, labelX, labelY);
    }
    ctx.restore();
  }

  private displayAngle(vector: Vector2): number {
    const degrees = Math.round(Math.atan2(-vector.y, vector.x) * 180 / Math.PI);
    return (degrees + 360) % 360;
  }

  private velocityVector(velocity: Vector2): Vector2 {
    let x = velocity.x * VELOCITY_VECTOR_SCALE;
    let y = velocity.y * VELOCITY_VECTOR_SCALE;
    const displayLength = Math.hypot(x, y);
    if (displayLength > MAX_VELOCITY_VECTOR_LENGTH) {
      x *= MAX_VELOCITY_VECTOR_LENGTH / displayLength;
      y *= MAX_VELOCITY_VECTOR_LENGTH / displayLength;
    }
    return { x, y };
  }

  private idleVelocityControlVector(object: PlaygroundObject): Vector2 {
    const objectExtent = object.shape === "circle"
      ? object.radius
      : Math.max(object.width, object.height) / 2;
    return {
      x: Math.max(DEFAULT_VELOCITY_HANDLE_OFFSET, objectExtent + VELOCITY_HANDLE_RADIUS + 8),
      y: 0,
    };
  }

  private velocityControlVector(object: PlaygroundObject, velocity: Vector2): Vector2 {
    if (Math.hypot(velocity.x, velocity.y) < VELOCITY_IDLE_EPSILON) {
      return this.idleVelocityControlVector(object);
    }
    const vector = this.velocityVector(velocity);
    const length = Math.hypot(vector.x, vector.y);
    const minimumLength = (object.shape === "circle"
      ? object.radius
      : Math.max(object.width, object.height) / 2) + VELOCITY_HANDLE_RADIUS + 12;
    if (length >= minimumLength) return vector;
    return {
      x: vector.x * minimumLength / length,
      y: vector.y * minimumLength / length,
    };
  }

  private drawArrow(
    originX: number,
    originY: number,
    vector: Vector2,
    factor: number,
    color: string,
    label: string,
    downwardLimit?: number,
    preferLabelBefore = false,
  ): void {
    let x = vector.x * factor;
    let y = vector.y * factor;
    const length = Math.hypot(x, y);
    if (length < 3) return;
    if (length < 46) {
      x *= 46 / length;
      y *= 46 / length;
    } else if (length > MAX_VELOCITY_VECTOR_LENGTH) {
      x *= MAX_VELOCITY_VECTOR_LENGTH / length;
      y *= MAX_VELOCITY_VECTOR_LENGTH / length;
    }
    if (downwardLimit !== undefined && y > 0 && originY + y > downwardLimit) {
      const availableLength = Math.max(3, downwardLimit - originY);
      const scale = availableLength / y;
      x *= scale;
      y = availableLength;
    }
    ({ x, y } = this.fitVectorInsideCanvas({ x: originX, y: originY }, { x, y }, 12));
    const endX = originX + x;
    const endY = originY + y;
    const angle = Math.atan2(y, x);
    const { ctx } = this;
    ctx.save();
    ctx.strokeStyle = color;
    ctx.fillStyle = color;
    ctx.lineWidth = 3;
    ctx.lineCap = "round";
    ctx.beginPath();
    ctx.moveTo(originX, originY);
    ctx.lineTo(endX, endY);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(endX, endY);
    ctx.lineTo(endX - 10 * Math.cos(angle - Math.PI / 6), endY - 10 * Math.sin(angle - Math.PI / 6));
    ctx.lineTo(endX - 10 * Math.cos(angle + Math.PI / 6), endY - 10 * Math.sin(angle + Math.PI / 6));
    ctx.closePath();
    ctx.fill();
    if (!label) {
      ctx.restore();
      return;
    }
    ctx.font = "700 14px Inter, system-ui, sans-serif";
    const mostlyVertical = Math.abs(y) >= Math.abs(x);
    const labelWidth = ctx.measureText(label).width;
    const desiredLabelX = preferLabelBefore
      ? originX - labelWidth / 2 - 14
      : mostlyVertical ? originX + 46 : originX + x * 0.5;
    const desiredLabelY = mostlyVertical ? originY + y * 0.5 + 5 : originY + y * 0.5 - 16;
    const labelX = Math.max(labelWidth / 2 + 8, Math.min(this.canvas.width - labelWidth / 2 - 8, desiredLabelX));
    const labelY = Math.max(18, Math.min(this.floorY - 8, desiredLabelY));
    ctx.textAlign = "center";
    ctx.fillStyle = "#ffffffeb";
    this.roundRect(labelX - labelWidth / 2 - 6, labelY - 15, labelWidth + 12, 20, 7);
    ctx.fill();
    ctx.fillStyle = color;
    ctx.fillText(label, labelX, labelY);
    ctx.restore();
  }

  private drawArrowHead(point: Vector2, vector: Vector2, color: string, size: number): void {
    const angle = Math.atan2(vector.y, vector.x);
    const { ctx } = this;
    ctx.save();
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.moveTo(point.x, point.y);
    ctx.lineTo(
      point.x - size * Math.cos(angle - Math.PI / 6),
      point.y - size * Math.sin(angle - Math.PI / 6),
    );
    ctx.lineTo(
      point.x - size * Math.cos(angle + Math.PI / 6),
      point.y - size * Math.sin(angle + Math.PI / 6),
    );
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }

  private frictionHandlePoint(): Vector2 {
    const law = this.frictionLaw;
    const object = law ? this.objects.get(law.bodyId) : undefined;
    if (this.challengeDrag === "friction" && this.challengeDragPoint) return this.challengeDragPoint;
    return object ? { x: object.x + object.width / 2 + 92, y: object.y } : { x: 0, y: 0 };
  }

  private leverHandlePoint(scene: Extract<GuidedMechanicsScene, { kind: "lever" }>): Vector2 {
    if (this.challengeDrag === "lever" && this.challengeScene === scene && this.challengeDragPoint) {
      return this.challengeDragPoint;
    }
    return {
      x: scene.center.x + Math.cos(scene.angle) * scene.model.effortArm,
      y: scene.center.y + Math.sin(scene.angle) * scene.model.effortArm + 70,
    };
  }

  private pulleyHandlePoint(scene: Extract<GuidedMechanicsScene, { kind: "pulley-advantage" }>): Vector2 {
    return {
      x: scene.pullX,
      y: this.challengeDrag === "pulley" && this.challengeScene === scene && this.challengeDragPoint
        ? this.challengeDragPoint.y
        : scene.pullStartY + scene.handleDistance,
    };
  }

  /** Makes the easier four-strand setup follow the learner's hand more readily. */
  private pulleyDragResponse(scene: Extract<GuidedMechanicsScene, { kind: "pulley-advantage" }>): number {
    return scene.model.supportStrands / 4;
  }

  private beginChallengeInteraction(point: Vector2, pointerId: number): boolean {
    const pulleyScene = this.allGuidedScenes().find(
      (scene): scene is Extract<GuidedMechanicsScene, { kind: "pulley-advantage" }> => scene.kind === "pulley-advantage",
    );
    const leverScene = this.allGuidedScenes().find(
      (scene): scene is Extract<GuidedMechanicsScene, { kind: "lever" }> => scene.kind === "lever",
    );
    if (pulleyScene) {
      for (const [index, strands] of ([1, 2, 4] as SupportStrands[]).entries()) {
        const x = this.canvas.width * 0.5 + (index - 1) * 104;
        if (Math.abs(point.x - x) <= 48 && point.y >= 62 && point.y <= 108) {
          pulleyScene.model.setSupportStrands(strands);
          pulleyScene.handleDistance = 0;
          pulleyScene.pullDistance = 0;
          this.applyGuidedScenePoses();
          this.clearTrails();
          this.recordGraphSample(true);
          this.notify();
          return true;
        }
      }
    }

    if (leverScene) {
      const scene = leverScene;
      for (const fraction of [0.35, 0.6, 0.9]) {
        const arm = scene.beamLength * 0.52 * fraction;
        const target = {
          x: scene.center.x + Math.cos(scene.angle) * arm,
          y: scene.center.y + Math.sin(scene.angle) * arm,
        };
        if (Math.hypot(point.x - target.x, point.y - target.y) <= 18) {
          scene.model.setEffortArm(arm);
          scene.appliedForce = 0;
          scene.angle = 0;
          this.applyGuidedScenePoses();
          this.recordGraphSample(true);
          this.notify();
          return true;
        }
      }
    }

    const candidates: Array<{ kind: ChallengeDrag; handle: Vector2; scene: GuidedMechanicsScene | null }> = [];
    if (this.frictionLaw) candidates.push({ kind: "friction", handle: this.frictionHandlePoint(), scene: null });
    if (leverScene) candidates.push({ kind: "lever", handle: this.leverHandlePoint(leverScene), scene: leverScene });
    if (pulleyScene) candidates.push({ kind: "pulley", handle: this.pulleyHandlePoint(pulleyScene), scene: pulleyScene });
    const hit = candidates.find(({ kind, handle }) => kind === "friction"
      ? Math.hypot(point.x - handle.x, point.y - handle.y) <= 24
      : Math.abs(point.x - handle.x) <= 34 && Math.abs(point.y - handle.y) <= 24);
    if (!hit) return false;
    this.pointerId = pointerId;
    this.challengeDrag = hit.kind;
    this.challengeScene = hit.scene;
    this.challengeDragOrigin = { ...hit.handle };
    this.challengeDragPoint = { ...hit.handle };
    this.challengeDragStartPullDistance = hit.kind === "pulley" && hit.scene?.kind === "pulley-advantage"
      ? hit.scene.pullDistance
      : 0;
    this.challengeDragStartHandleDistance = hit.kind === "pulley" && hit.scene?.kind === "pulley-advantage"
      ? hit.scene.handleDistance
      : 0;
    this._paused = false;
    this.canvas.setPointerCapture(pointerId);
    this.canvas.style.cursor = "grabbing";
    return true;
  }

  private updateChallengeInteraction(point: Vector2): void {
    const origin = this.challengeDragOrigin;
    if (!this.challengeDrag || !origin) return;
    if (this.challengeDrag === "friction" && this.frictionLaw) {
      const dx = Math.max(-190, Math.min(190, point.x - origin.x));
      this.challengeDragPoint = { x: origin.x + dx, y: origin.y };
      this.frictionLaw.setAppliedForce(dx * 0.9 * PIXELS_PER_METER);
      this.simulation.refreshAccelerations();
    } else if (this.challengeDrag === "lever" && this.challengeScene?.kind === "lever") {
      const dy = Math.max(0, Math.min(190, point.y - origin.y));
      const scene = this.challengeScene;
      scene.appliedForce = Math.min(scene.model.requiredForce, dy * LEVER_FORCE_PER_PIXEL);
      scene.angle = scene.model.applyForce(scene.appliedForce).lifting ? LEVER_LIFT_ANGLE : 0;
      this.challengeDragPoint = {
        x: origin.x,
        y: origin.y + dy,
      };
      this.applyGuidedScenePoses();
    } else if (this.challengeDrag === "pulley" && this.challengeScene?.kind === "pulley-advantage") {
      const scene = this.challengeScene;
      const currentLift = scene.model.liftDistanceForPull(this.challengeDragStartPullDistance);
      const remainingLift = Math.max(0, scene.maxLift - currentLift);
      const dragResponse = this.pulleyDragResponse(scene);
      const reachableStroke = Math.max(0, Math.min(
        remainingLift / dragResponse,
        this.floorY - 28 - origin.y,
      ));
      const dy = Math.max(0, Math.min(reachableStroke, point.y - origin.y));
      const maximumPullDistance = scene.model.pullDistanceForLift(scene.maxLift);
      const requestedPullDistance = scene.model.pullDistanceForLift(dy * dragResponse);
      scene.pullDistance = Math.min(
        maximumPullDistance,
        this.challengeDragStartPullDistance + requestedPullDistance,
      );
      scene.handleDistance = this.challengeDragStartHandleDistance + dy;
      this.challengeDragPoint = { x: origin.x, y: origin.y + dy };
      this.applyGuidedScenePoses();
    }
    this.graphTime += GRAPH_SAMPLE_INTERVAL;
    this.recordGraphSample();
    this.syncObjects();
    this.notify();
  }

  private completeRopeConnection(point: Vector2): boolean {
    const startId = this.ropeStartId;
    const kind = this.connectionKind;
    const target = this.hitTest(point);
    if (!startId || !kind || !target || target.id === startId || this.isGuidedBody(target.id)) {
      this.ropePointer = point;
      return false;
    }
    const start = this.simulation.getBody(startId);
    const end = this.simulation.getBody(target.id);
    if (!start || !end) return false;
    const duplicate = this.simulation.constraints.some((constraint) =>
      constraint.id.startsWith("sandbox-")
      && (
        (constraint.bodyA === startId && constraint.bodyB === target.id)
        || (constraint.bodyA === target.id && constraint.bodyB === startId)
      ));
    const distance = Math.hypot(
      end.state.position.x - start.state.position.x,
      end.state.position.y - start.state.position.y,
    );
    if (!duplicate && distance > 0) {
      this.ropeSequence += 1;
      this.simulation.addConstraint({
        id: `sandbox-${kind}-${this.ropeSequence}`,
        bodyA: startId,
        bodyB: target.id,
        distance,
      });
    }
    this.selectedId = target.id;
    this.resetRopeConnectionState();
    this.clearTrails();
    this.notify();
    return true;
  }

  private bindPointerEvents(): void {
    this.canvas.addEventListener("pointerdown", (event) => {
      const point = this.pointFromEvent(event);
      if (this.ropeStartId) {
        this.completeRopeConnection(point);
        return;
      }
      if (this.beginChallengeInteraction(point, event.pointerId)) return;
      const rotationHit = this.hitRotationHandle(point);
      if (rotationHit) {
        this.paused = true;
        this.pointerId = event.pointerId;
        this.rotatingId = rotationHit.id;
        this.canvas.setPointerCapture(event.pointerId);
        this.canvas.style.cursor = "grabbing";
        return;
      }
      const resizeHit = this.hitResizeHandle(point);
      if (resizeHit && this.selectedId) {
        const object = this.objects.get(this.selectedId);
        if (!object) return;
        this.paused = true;
        this.pointerId = event.pointerId;
        this.resizingId = object.id;
        this.resizeHandle = resizeHit;
        this.resizeAnchor = this.localToWorld(object, {
          x: -object.width / 2,
          y: -object.height / 2,
        });
        this.canvas.setPointerCapture(event.pointerId);
        this.canvas.style.cursor = this.resizeCursor(resizeHit);
        return;
      }
      const forceHit = this.hitForceHandle(point);
      if (forceHit) {
        this.paused = true;
        this.pointerId = event.pointerId;
        this.forceDraggedId = forceHit.id;
        this.canvas.setPointerCapture(event.pointerId);
        this.canvas.style.cursor = "grabbing";
        return;
      }
      const velocityHit = this.hitVelocityHandle(point);
      if (velocityHit) {
        this.paused = true;
        this.pointerId = event.pointerId;
        this.velocityDraggedId = velocityHit.id;
        this.canvas.setPointerCapture(event.pointerId);
        this.canvas.style.cursor = "grabbing";
        return;
      }
      const hit = this.hitTest(point);
      this.select(hit?.id ?? null);
      if (!hit) return;
      this.pointerId = event.pointerId;
      this.draggedId = hit.id;
      this.canvas.setPointerCapture(event.pointerId);
      this.canvas.style.cursor = "grabbing";
    });

    this.canvas.addEventListener("pointermove", (event) => {
      const point = this.pointFromEvent(event);
      if (this.ropeStartId) {
        this.ropePointer = point;
        this.canvas.style.cursor = this.hitTest(point) ? "pointer" : "crosshair";
        return;
      }
      if (event.pointerId === this.pointerId && this.challengeDrag) {
        this.updateChallengeInteraction(point);
        return;
      }
      if (event.pointerId === this.pointerId && this.rotatingId) {
        this.rotateBlockFromPoint(this.rotatingId, point);
        return;
      }
      if (event.pointerId === this.pointerId && this.resizingId) {
        this.resizeBlockFromPoint(this.resizingId, point);
        return;
      }
      if (event.pointerId === this.pointerId && this.velocityDraggedId) {
        this.updateVelocityFromPoint(this.velocityDraggedId, point);
        return;
      }
      if (event.pointerId === this.pointerId && this.forceDraggedId) {
        this.updateForceFromPoint(this.forceDraggedId, point);
        return;
      }
      if (event.pointerId !== this.pointerId || !this.draggedId) {
        const resizeHandle = this.hitResizeHandle(point);
        this.canvas.style.cursor = this.hitRotationHandle(point)
          ? "grab"
          : resizeHandle
          ? this.resizeCursor(resizeHandle)
          : this.hitVelocityHandle(point) || this.hitForceHandle(point)
            ? "pointer" : this.hitTest(point) ? "grab" : "crosshair";
        return;
      }
      const object = this.objects.get(this.draggedId);
      const body = this.simulation.getBody(this.draggedId);
      if (!object || !body) return;
      if (this.dragGuidedBody(this.draggedId, point)) {
        this.syncObjects();
        this.recordGraphSample(true);
        this.notify();
        return;
      }
      const previousPosition = { ...body.state.position };
      const { x: halfWidth, y: halfHeight } = this.objectHalfExtents(object);
      body.state.position = {
        x: Math.max(14 + halfWidth, Math.min(this.canvas.width - 14 - halfWidth, point.x)),
        y: Math.max(14 + halfHeight, Math.min(this.floorY - halfHeight, point.y)),
      };
      body.state.velocity = { x: 0, y: 0 };
      this.gravitySources.get(object.id)?.field.setSourcePosition(body.state.position);
      const draggedSpring = this.springForBody(this.draggedId);
      if (draggedSpring) this.resolveSpringMount(draggedSpring, previousPosition);
      this.simulation.satisfyConstraints();
      this.syncObjects();
      this.trails.set(object.id, [{ ...body.state.position }]);
      this.simulation.refreshAccelerations();
      this.recordGraphSample(true);
      this.notify();
    });

    const release = (event: PointerEvent, autoPlay: boolean) => {
      if (event.pointerId !== this.pointerId) return;
      const velocityBody = this.velocityDraggedId
        ? this.simulation.getBody(this.velocityDraggedId)
        : undefined;
      const launchesVelocity = Boolean(
        velocityBody
        && Math.hypot(velocityBody.state.velocity.x, velocityBody.state.velocity.y) >= VELOCITY_IDLE_EPSILON,
      );
      const releasesSpring = Boolean(
        this.draggedId
        && this.springForBody(this.draggedId),
      );
      const releasesGuided = Boolean(this.draggedId && this.isGuidedBody(this.draggedId));
      const releasesForce = Boolean(this.forceDraggedId);
      if (this.challengeDrag === "friction") {
        this.frictionLaw?.setAppliedForce(0);
        this.simulation.refreshAccelerations();
      }
      this.pointerId = null;
      this.draggedId = null;
      this.velocityDraggedId = null;
      this.forceDraggedId = null;
      this.rotatingId = null;
      this.resizingId = null;
      this.resizeHandle = null;
      this.resizeAnchor = null;
      this.challengeDrag = null;
      this.challengeDragOrigin = null;
      this.challengeDragPoint = null;
      this.challengeDragStartPullDistance = 0;
      this.challengeDragStartHandleDistance = 0;
      this.challengeScene = null;
      this.canvas.style.cursor = "grab";
      if (autoPlay && this.directManipulationAutoPlay && (launchesVelocity || releasesSpring || releasesGuided || releasesForce)) {
        this.paused = false;
      }
    };
    this.canvas.addEventListener("pointerup", (event) => release(event, true));
    this.canvas.addEventListener("pointercancel", (event) => release(event, false));
  }

  private hitTest(point: Vector2): PlaygroundObject | null {
    for (const object of [...this.objects.values()].reverse()) {
      const local = this.worldToLocal(object, point);
      const hit = object.shape === "circle"
        ? local.x * local.x + local.y * local.y <= object.radius ** 2
        : Math.abs(local.x) <= object.width / 2 && Math.abs(local.y) <= object.height / 2;
      if (hit) return object;
    }
    return null;
  }

  private hitVelocityHandle(point: Vector2): PlaygroundObject | null {
    if (!this.selectedId) return null;
    const object = this.objects.get(this.selectedId);
    const body = this.simulation.getBody(this.selectedId);
    if (!object || !body || body.fixed || this.isGuidedBody(object.id) || this.frictionLaw?.bodyId === object.id) return null;
    const vector = this.velocityControlVector(object, body.state.velocity);
    const dx = point.x - object.x - vector.x;
    const dy = point.y - object.y - vector.y;
    return dx * dx + dy * dy <= CONTROL_HIT_RADIUS ** 2 ? object : null;
  }

  private forceHandlePoint(law: ConstantBodyForceLaw, origin: Vector2): Vector2 {
    const vector = this.fitVectorInsideCanvas(origin, {
      x: law.vector.x * FORCE_VECTOR_SCALE,
      y: law.vector.y * FORCE_VECTOR_SCALE,
    }, 14);
    return {
      x: origin.x + vector.x,
      y: origin.y + vector.y,
    };
  }

  private fitVectorInsideCanvas(origin: Vector2, vector: Vector2, margin: number): Vector2 {
    let scale = 1;
    const right = this.canvas.width - margin - origin.x;
    const left = margin - origin.x;
    const bottom = this.floorY - margin - origin.y;
    const top = margin - origin.y;
    if (vector.x > 0) scale = Math.min(scale, Math.max(0, right / vector.x));
    if (vector.x < 0) scale = Math.min(scale, Math.max(0, left / vector.x));
    if (vector.y > 0) scale = Math.min(scale, Math.max(0, bottom / vector.y));
    if (vector.y < 0) scale = Math.min(scale, Math.max(0, top / vector.y));
    return { x: vector.x * scale, y: vector.y * scale };
  }

  private hitForceHandle(point: Vector2): PlaygroundObject | null {
    if (!this.selectedId) return null;
    const object = this.objects.get(this.selectedId);
    const body = this.simulation.getBody(this.selectedId);
    const law = this.forceLaws.get(this.selectedId);
    if (!object || !body || !law || body.fixed) return null;
    const handle = this.forceHandlePoint(law, body.state.position);
    return Math.hypot(point.x - handle.x, point.y - handle.y) <= CONTROL_HIT_RADIUS ? object : null;
  }

  private updateForceFromPoint(id: string, point: Vector2): void {
    const body = this.simulation.getBody(id);
    const law = this.forceLaws.get(id);
    if (!body || !law) return;
    let dx = point.x - body.state.position.x;
    let dy = point.y - body.state.position.y;
    const length = Math.hypot(dx, dy);
    if (length > MAX_VELOCITY_VECTOR_LENGTH) {
      dx *= MAX_VELOCITY_VECTOR_LENGTH / length;
      dy *= MAX_VELOCITY_VECTOR_LENGTH / length;
    }
    law.setVector({ x: dx / FORCE_VECTOR_SCALE, y: dy / FORCE_VECTOR_SCALE });
    this.simulation.refreshAccelerations();
    this.notify();
  }

  private isResizableBlock(object: PlaygroundObject, body: Body): boolean {
    return object.shape === "box" && Boolean(body.fixed) && !this.isGuidedBody(object.id);
  }

  private resizeHandles(object: PlaygroundObject): Array<Vector2 & { kind: ResizeHandle }> {
    return [
      { kind: "both", ...this.localToWorld(object, { x: object.width / 2, y: object.height / 2 }) },
      { kind: "width", ...this.localToWorld(object, { x: object.width / 2, y: 0 }) },
      { kind: "height", ...this.localToWorld(object, { x: 0, y: object.height / 2 }) },
    ];
  }

  private rotationHandlePoint(object: PlaygroundObject): Vector2 {
    return this.localToWorld(object, { x: 0, y: -object.height / 2 - ROTATION_HANDLE_OFFSET });
  }

  private hitRotationHandle(point: Vector2): PlaygroundObject | null {
    if (!this.selectedId) return null;
    const object = this.objects.get(this.selectedId);
    const body = this.simulation.getBody(this.selectedId);
    if (!object || !body || !this.isResizableBlock(object, body)) return null;
    const handle = this.rotationHandlePoint(object);
    return Math.hypot(point.x - handle.x, point.y - handle.y) <= CONTROL_HIT_RADIUS ? object : null;
  }

  private hitResizeHandle(point: Vector2): ResizeHandle | null {
    if (!this.selectedId) return null;
    const object = this.objects.get(this.selectedId);
    const body = this.simulation.getBody(this.selectedId);
    if (!object || !body || !this.isResizableBlock(object, body)) return null;
    let nearest: { kind: ResizeHandle; distanceSquared: number } | null = null;
    for (const handle of this.resizeHandles(object)) {
      const dx = point.x - handle.x;
      const dy = point.y - handle.y;
      const distanceSquared = dx * dx + dy * dy;
      if (
        distanceSquared <= CONTROL_HIT_RADIUS ** 2
        && (!nearest || distanceSquared < nearest.distanceSquared)
      ) {
        nearest = { kind: handle.kind, distanceSquared };
      }
    }
    return nearest?.kind ?? null;
  }

  private resizeCursor(handle: ResizeHandle): string {
    if (handle === "width") return "ew-resize";
    if (handle === "height") return "ns-resize";
    return "nwse-resize";
  }

  private resizeBlockFromPoint(id: string, point: Vector2): void {
    const object = this.objects.get(id);
    const body = this.simulation.getBody(id);
    const handle = this.resizeHandle;
    const anchor = this.resizeAnchor;
    if (!object || !body || !handle || !anchor || !this.isResizableBlock(object, body)) return;

    const angle = object.angle;
    const relative = { x: point.x - anchor.x, y: point.y - anchor.y };
    const local = {
      x: relative.x * Math.cos(angle) + relative.y * Math.sin(angle),
      y: -relative.x * Math.sin(angle) + relative.y * Math.cos(angle),
    };
    const width = handle === "height"
      ? object.width
      : Math.max(MIN_BLOCK_WIDTH, Math.min(this.canvas.width - 28, local.x));
    const height = handle === "width"
      ? object.height
      : Math.max(MIN_BLOCK_HEIGHT, Math.min(this.floorY - 28, local.y));
    object.width = width;
    object.height = height;
    object.radius = Math.min(width, height) / 2;
    object.x = anchor.x + Math.cos(angle) * width / 2 - Math.sin(angle) * height / 2;
    object.y = anchor.y + Math.sin(angle) * width / 2 + Math.cos(angle) * height / 2;
    body.radius = object.radius;
    body.collider = this.boxCollider(object);
    body.state.position = { x: object.x, y: object.y };
    body.state.velocity = { x: 0, y: 0 };
    this.trails.set(id, [{ x: object.x, y: object.y }]);
    this.simulation.refreshAccelerations();
    this.notify();
  }

  private rotateBlockFromPoint(id: string, point: Vector2): void {
    const object = this.objects.get(id);
    const body = this.simulation.getBody(id);
    if (!object || !body || !this.isResizableBlock(object, body)) return;
    let angle = Math.atan2(point.y - object.y, point.x - object.x) + Math.PI / 2;
    while (angle > Math.PI / 2) angle -= Math.PI;
    while (angle < -Math.PI / 2) angle += Math.PI;
    object.angle = Math.round(angle / BLOCK_ANGLE_SNAP_RADIANS) * BLOCK_ANGLE_SNAP_RADIANS;
    body.collider = this.boxCollider(object);
    body.state.velocity = { x: 0, y: 0 };
    this.simulation.refreshAccelerations();
    this.notify();
  }

  private localToWorld(object: PlaygroundObject, point: Vector2): Vector2 {
    return {
      x: object.x + point.x * Math.cos(object.angle) - point.y * Math.sin(object.angle),
      y: object.y + point.x * Math.sin(object.angle) + point.y * Math.cos(object.angle),
    };
  }

  private worldToLocal(object: PlaygroundObject, point: Vector2): Vector2 {
    const dx = point.x - object.x;
    const dy = point.y - object.y;
    return {
      x: dx * Math.cos(object.angle) + dy * Math.sin(object.angle),
      y: -dx * Math.sin(object.angle) + dy * Math.cos(object.angle),
    };
  }

  private objectHalfExtents(object: PlaygroundObject): Vector2 {
    if (object.shape === "circle") return { x: object.radius, y: object.radius };
    return {
      x: Math.abs(Math.cos(object.angle)) * object.width / 2
        + Math.abs(Math.sin(object.angle)) * object.height / 2,
      y: Math.abs(Math.sin(object.angle)) * object.width / 2
        + Math.abs(Math.cos(object.angle)) * object.height / 2,
    };
  }

  private boxCollider(object: PlaygroundObject): Extract<BodyCollider, { kind: "box" }> {
    return object.angle === 0
      ? { kind: "box", halfWidth: object.width / 2, halfHeight: object.height / 2 }
      : { kind: "box", halfWidth: object.width / 2, halfHeight: object.height / 2, angle: object.angle };
  }

  private updateVelocityFromPoint(id: string, point: Vector2): void {
    const object = this.objects.get(id);
    const body = this.simulation.getBody(id);
    if (!object || !body) return;
    let x = point.x - object.x;
    let y = point.y - object.y;
    const length = Math.hypot(x, y);
    if (length < 8) {
      body.state.velocity = { x: 0, y: 0 };
    } else {
      const angle = Math.round(Math.atan2(y, x) / VELOCITY_ANGLE_SNAP_RADIANS) * VELOCITY_ANGLE_SNAP_RADIANS;
      x = Math.cos(angle) * length;
      y = Math.sin(angle) * length;
      if (length > MAX_VELOCITY_VECTOR_LENGTH) {
        x *= MAX_VELOCITY_VECTOR_LENGTH / length;
        y *= MAX_VELOCITY_VECTOR_LENGTH / length;
      }
      body.state.velocity = {
        x: x / VELOCITY_VECTOR_SCALE,
        y: y / VELOCITY_VECTOR_SCALE,
      };
    }
    this.trails.set(id, [{ ...body.state.position }]);
    this.simulation.refreshAccelerations();
    if (this.orbitExperiment?.bodyId === id) this.refreshOrbitAnalysis();
    this.recordGraphSample(true);
    this.notify();
  }

  private pointFromEvent(event: PointerEvent): Vector2 {
    const rect = this.canvas.getBoundingClientRect();
    return {
      x: (event.clientX - rect.left) * this.canvas.width / rect.width,
      y: (event.clientY - rect.top) * this.canvas.height / rect.height,
    };
  }

  private roundRect(x: number, y: number, width: number, height: number, radius: number): void {
    const { ctx } = this;
    const r = Math.min(radius, width / 2, height / 2);
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.lineTo(x + width - r, y);
    ctx.quadraticCurveTo(x + width, y, x + width, y + r);
    ctx.lineTo(x + width, y + height - r);
    ctx.quadraticCurveTo(x + width, y + height, x + width - r, y + height);
    ctx.lineTo(x + r, y + height);
    ctx.quadraticCurveTo(x, y + height, x, y + height - r);
    ctx.lineTo(x, y + r);
    ctx.quadraticCurveTo(x, y, x + r, y);
    ctx.closePath();
  }

  private toPixels(vector: Vector2): Vector2 {
    return { x: vector.x * PIXELS_PER_METER, y: vector.y * PIXELS_PER_METER };
  }

  private nextColor(): string { return COLORS[this.objects.size % COLORS.length]; }

  private nextObjectId(): string {
    this.objectSequence += 1;
    return `body-${this.objectSequence}`;
  }

  private shadeColor(hex: string, amount: number): string {
    const value = Number.parseInt(hex.slice(1), 16);
    const channels = [
      Math.max(0, Math.min(255, (value >> 16) + amount)),
      Math.max(0, Math.min(255, ((value >> 8) & 0xff) + amount)),
      Math.max(0, Math.min(255, (value & 0xff) + amount)),
    ];
    return `#${channels.map((channel) => channel.toString(16).padStart(2, "0")).join("")}`;
  }

  private notify(): void { this.onUpdate?.(this.snapshot()); }
}
