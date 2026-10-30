/**
 * S2 mechanics sandbox (physics + rendering mix): floor, 30° incline, 3 fixed blocks,
 * 50 dynamic bodies (25 boxes, 25 balls) in rubber/wood/steel, one shadow-casting
 * directional light. Seeded drops from 3–6 m; every 20 s ten bodies are dropped again.
 * One finger on a body drags it on the manipulation surface (ray-cast down onto floor,
 * incline or block tops) and snaps to a 0.25 m grid on release; two fingers orbit/zoom.
 */
import type RAPIER_NS from "@dimforge/rapier3d-compat";
import {
  AmbientLight,
  BoxGeometry,
  Color,
  DirectionalLight,
  HemisphereLight,
  Mesh,
  MeshStandardMaterial,
  PCFShadowMap,
  PerspectiveCamera,
  Plane,
  Raycaster,
  Scene,
  SphereGeometry,
  Vector2,
  Vector3,
  type Material,
} from "three/webgpu";
import { MATERIALS, type PlaygroundMaterial } from "../../../../src/physics/materials";
import { CameraRig, GestureInput } from "../render/camera-rig";
import { applyRoomEnvironment } from "../render/environment";
import { seededRandom } from "../random";
import { CAMERA_FOV, FixedStepper, type BenchScene, type SceneContext } from "./types";

type Rapier = typeof RAPIER_NS;

const BODY_COUNT = 50;
const REDROP_COUNT = 10;
const REDROP_INTERVAL_S = 20;
const HALF = 0.2;
const SNAP = 0.25;
const SCENE_MATERIALS: readonly PlaygroundMaterial[] = ["rubber", "wood", "steel"];
const LOOK: Record<string, { color: string; roughness: number; metalness: number }> = {
  rubber: { color: "#d8483b", roughness: 0.85, metalness: 0 },
  wood: { color: "#b98a54", roughness: 0.65, metalness: 0 },
  steel: { color: "#c9ced6", roughness: 0.25, metalness: 1 },
};

interface DynamicItem {
  body: RAPIER_NS.RigidBody;
  mesh: Mesh;
}

export class SandboxScene implements BenchScene {
  readonly id = "S2" as const;
  readonly scene = new Scene();
  readonly camera = new PerspectiveCamera(CAMERA_FOV, 9 / 16, 0.1, 200);
  private readonly world: RAPIER_NS.World;
  private readonly items: DynamicItem[] = [];
  private readonly stepper = new FixedStepper(1 / 60);
  private readonly random = seededRandom(20260);
  private readonly rig: CameraRig;
  private readonly input: GestureInput;
  private readonly raycaster = new Raycaster();
  private readonly disposables: { dispose(): void }[] = [];
  private time = 0;
  private nextRedrop = REDROP_INTERVAL_S;
  private redropCursor = 0;
  private dragged: DynamicItem | null = null;

  constructor(private readonly rapier: Rapier, private readonly context: SceneContext) {
    context.renderer.shadowMap.enabled = true;
    context.renderer.shadowMap.type = PCFShadowMap;
    this.track(applyRoomEnvironment(context.renderer, this.scene));
    this.scene.background = new Color("#c9d6e3");
    this.world = new rapier.World({ x: 0, y: -9.81, z: 0 });
    this.world.timestep = this.stepper.dt;

    this.scene.add(new HemisphereLight("#eef4ff", "#6b5a48", 0.9));
    this.scene.add(new AmbientLight("#ffffff", 0.15));
    const sun = new DirectionalLight("#ffffff", 2.4);
    sun.position.set(6, 12, 5);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    const shadowCamera = sun.shadow.camera;
    shadowCamera.left = -10;
    shadowCamera.right = 10;
    shadowCamera.top = 10;
    shadowCamera.bottom = -10;
    shadowCamera.near = 1;
    shadowCamera.far = 40;
    sun.shadow.bias = -0.0005;
    this.scene.add(sun);

    const staticMaterial = this.track(new MeshStandardMaterial({ color: "#8f9aa6", roughness: 0.8 }));
    const floorMaterial = this.track(new MeshStandardMaterial({ color: "#e7e3da", roughness: 0.95 }));
    this.addStatic({ x: 10, y: 0.1, z: 10 }, { x: 0, y: -0.1, z: 0 }, 0, floorMaterial, "wood");
    this.addStatic({ x: 2.2, y: 0.1, z: 1.5 }, { x: -4.5, y: 1.0, z: 0 }, Math.PI / 6, staticMaterial, "wood");
    this.addStatic({ x: 0.5, y: 0.5, z: 0.5 }, { x: 3, y: 0.5, z: -2 }, 0, staticMaterial, "steel");
    this.addStatic({ x: 0.8, y: 0.4, z: 0.4 }, { x: 1, y: 0.4, z: 3 }, 0, staticMaterial, "wood");
    this.addStatic({ x: 0.4, y: 0.75, z: 0.6 }, { x: 4.5, y: 0.75, z: 2 }, 0, staticMaterial, "rubber");

    const boxGeometry = this.track(new BoxGeometry(HALF * 2, HALF * 2, HALF * 2));
    const ballGeometry = this.track(new SphereGeometry(HALF, 32, 16));
    const looks = Object.fromEntries(SCENE_MATERIALS.map((name) => [
      name,
      this.track(new MeshStandardMaterial(LOOK[name])),
    ])) as Partial<Record<PlaygroundMaterial, Material>>;

    for (let i = 0; i < BODY_COUNT; i += 1) {
      const isBox = i % 2 === 0;
      const materialName = SCENE_MATERIALS[i % SCENE_MATERIALS.length];
      const physical = MATERIALS[materialName];
      const body = this.world.createRigidBody(rapier.RigidBodyDesc.dynamic());
      const collider = isBox ? rapier.ColliderDesc.cuboid(HALF, HALF, HALF) : rapier.ColliderDesc.ball(HALF);
      this.world.createCollider(
        collider.setDensity(500).setFriction(physical.friction).setRestitution(physical.restitution),
        body,
      );
      const mesh = new Mesh(isBox ? boxGeometry : ballGeometry, looks[materialName] as Material);
      mesh.castShadow = true;
      mesh.receiveShadow = true;
      mesh.userData.index = i;
      this.scene.add(mesh);
      const item = { body, mesh };
      this.items.push(item);
      this.drop(item);
    }

    this.rig = new CameraRig(this.camera, {
      azimuth: 0.5,
      elevation: 0.55,
      distance: 17,
      target: new Vector3(0, 0.8, 0),
    });
    this.input = new GestureInput(context.canvas, this.rig, {
      onSinglePointerDown: (event) => this.beginDrag(event),
      onDrag: (event) => this.drag(event),
      onDragEnd: () => this.endDrag(),
    });
  }

  private track<T extends { dispose(): void }>(item: T): T {
    this.disposables.push(item);
    return item;
  }

  private addStatic(
    half: { x: number; y: number; z: number },
    position: { x: number; y: number; z: number },
    angleZ: number,
    material: Material,
    physical: PlaygroundMaterial,
  ): void {
    const rotation = { x: 0, y: 0, z: Math.sin(angleZ / 2), w: Math.cos(angleZ / 2) };
    const body = this.world.createRigidBody(
      this.rapier.RigidBodyDesc.fixed().setTranslation(position.x, position.y, position.z).setRotation(rotation),
    );
    this.world.createCollider(
      this.rapier.ColliderDesc.cuboid(half.x, half.y, half.z)
        .setFriction(MATERIALS[physical].friction)
        .setRestitution(MATERIALS[physical].restitution),
      body,
    );
    const mesh = new Mesh(this.track(new BoxGeometry(half.x * 2, half.y * 2, half.z * 2)), material);
    mesh.position.set(position.x, position.y, position.z);
    mesh.rotation.z = angleZ;
    mesh.receiveShadow = true;
    mesh.castShadow = half.y > 0.2;
    this.scene.add(mesh);
  }

  private drop(item: DynamicItem): void {
    const r = this.random;
    item.body.setTranslation({ x: -4 + r() * 8, y: 3 + r() * 3, z: -3 + r() * 6 }, true);
    item.body.setRotation({ x: 0, y: 0, z: 0, w: 1 }, true);
    item.body.setLinvel({ x: 0, y: 0, z: 0 }, true);
    item.body.setAngvel({ x: (r() - 0.5) * 4, y: (r() - 0.5) * 4, z: (r() - 0.5) * 4 }, true);
  }

  private pointerRay(event: PointerEvent): void {
    const rect = this.context.canvas.getBoundingClientRect();
    const ndc = new Vector2(
      (event.clientX - rect.left) / rect.width * 2 - 1,
      -((event.clientY - rect.top) / rect.height) * 2 + 1,
    );
    this.raycaster.setFromCamera(ndc, this.camera);
  }

  private beginDrag(event: PointerEvent): boolean {
    this.pointerRay(event);
    const hit = this.raycaster.intersectObjects(this.items.map((item) => item.mesh), false)[0];
    if (!hit) return false;
    const item = this.items[hit.object.userData.index as number];
    item.body.setBodyType(this.rapier.RigidBodyType.KinematicPositionBased, true);
    this.dragged = item;
    return true;
  }

  /** Height of the manipulation surface (floor, incline or block top) below (x, z). */
  private surfaceY(x: number, z: number, exclude: RAPIER_NS.RigidBody): number {
    const ray = new this.rapier.Ray({ x, y: 20, z }, { x: 0, y: -1, z: 0 });
    const hit = this.world.castRay(ray, 40, true, this.rapier.QueryFilterFlags.EXCLUDE_DYNAMIC, undefined, undefined, exclude);
    return hit ? 20 - hit.timeOfImpact : 0;
  }

  private drag(event: PointerEvent): void {
    if (!this.dragged) return;
    this.pointerRay(event);
    const point = new Vector3();
    if (!this.raycaster.ray.intersectPlane(new Plane(new Vector3(0, 1, 0), -HALF), point)) return;
    const x = Math.max(-9.5, Math.min(9.5, point.x));
    const z = Math.max(-9.5, Math.min(9.5, point.z));
    const y = this.surfaceY(x, z, this.dragged.body) + HALF + 0.05;
    this.dragged.body.setNextKinematicTranslation({ x, y, z });
  }

  private endDrag(): void {
    const item = this.dragged;
    if (!item) return;
    const p = item.body.translation();
    const x = Math.round(p.x / SNAP) * SNAP;
    const z = Math.round(p.z / SNAP) * SNAP;
    const y = this.surfaceY(x, z, item.body) + HALF + 0.01;
    item.body.setBodyType(this.rapier.RigidBodyType.Dynamic, true);
    item.body.setTranslation({ x, y, z }, true);
    item.body.setRotation({ x: 0, y: 0, z: 0, w: 1 }, true);
    item.body.setLinvel({ x: 0, y: 0, z: 0 }, true);
    item.body.setAngvel({ x: 0, y: 0, z: 0 }, true);
    this.dragged = null;
  }

  update(dt: number): void {
    this.time += dt;
    if (this.time >= this.nextRedrop) {
      this.nextRedrop += REDROP_INTERVAL_S;
      for (let i = 0; i < REDROP_COUNT; i += 1) {
        const item = this.items[this.redropCursor];
        this.redropCursor = (this.redropCursor + 1) % this.items.length;
        if (item !== this.dragged) this.drop(item);
      }
    }
    this.stepper.advance(dt, () => this.world.step());
    for (const item of this.items) {
      const p = item.body.translation();
      if (p.y < -5) this.drop(item);
      const q = item.body.rotation();
      item.mesh.position.set(p.x, p.y, p.z);
      item.mesh.quaternion.set(q.x, q.y, q.z, q.w);
    }
  }

  render(): void {
    this.context.renderer.render(this.scene, this.camera);
  }

  resize(width: number, height: number): void {
    this.camera.aspect = width / height;
    this.camera.updateProjectionMatrix();
  }

  dispose(): void {
    this.input.dispose();
    this.world.free();
    for (const item of this.disposables) item.dispose();
    this.context.renderer.shadowMap.enabled = false;
  }
}
