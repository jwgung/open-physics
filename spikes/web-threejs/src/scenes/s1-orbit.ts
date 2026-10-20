/**
 * S1 orbit (graphics ceiling): emissive sun + bloom, 8 PBR planets with 2048² albedo
 * and normal maps, one ringed planet, 8 orbit lines, 5,000 star sprites, and a 30 s
 * automatic camera loop (overview → follow a planet).
 * Positions come from the formula core's circular-orbit solution.
 */
import {
  AmbientLight,
  BufferGeometry,
  Color,
  DoubleSide,
  Float32BufferAttribute,
  Group,
  InstancedBufferAttribute,
  LineBasicMaterial,
  Line,
  Mesh,
  MeshStandardMaterial,
  PerspectiveCamera,
  PointLight,
  PointsNodeMaterial,
  RenderPipeline,
  RingGeometry,
  Scene,
  SphereGeometry,
  Sprite,
  Vector3,
  type Texture,
} from "three/webgpu";
import { instancedBufferAttribute, pass } from "three/tsl";
import { bloom } from "three/addons/tsl/display/BloomNode.js";
import { circularOrbitSpeed } from "../../../../src/physics/laws/orbit";
import { planetAlbedo, ringTexture, surfaceNormal, type SurfaceKind } from "../render/procedural-textures";
import { seededRandom } from "../random";
import { CAMERA_FOV, type BenchScene, type SceneContext } from "./types";

/** Scene units: G = 1, M = 300 → inner orbit ≈ 4 s, outer orbit ≈ 63 s. */
const G = 1;
const SUN_MASS = 300;
const CAMERA_CYCLE_S = 30;

interface PlanetSpec {
  radius: number;
  orbit: number;
  kind: SurfaceKind;
  palette: string[];
  ring?: boolean;
}

const PLANETS: PlanetSpec[] = [
  { radius: 0.35, orbit: 5, kind: "rocky", palette: ["#8a7f72", "#5d554d", "#a89a88"] },
  { radius: 0.55, orbit: 7.5, kind: "rocky", palette: ["#c9a46a", "#a07b45", "#e0c08a"] },
  { radius: 0.6, orbit: 10, kind: "icy", palette: ["#2f6bb3", "#3d8a4a", "#e8edf2"] },
  { radius: 0.45, orbit: 12.5, kind: "rocky", palette: ["#b5532e", "#7a3420", "#d08050"] },
  { radius: 1.4, orbit: 17, kind: "gas", palette: ["#c8a27a", "#9c6b45", "#efdcc0", "#7d4e30"] },
  { radius: 1.2, orbit: 22, kind: "gas", palette: ["#e3cf98", "#c2a466", "#f3e6c2"], ring: true },
  { radius: 0.9, orbit: 27, kind: "icy", palette: ["#9fd8e0", "#7cc0cc", "#d4f1f4"] },
  { radius: 0.85, orbit: 31, kind: "gas", palette: ["#3f66c9", "#2d4fa3", "#6f8fe0"] },
];

export function textureSize(): number {
  const param = Number(new URLSearchParams(location.search).get("tex"));
  return param === 512 || param === 1024 || param === 2048 ? param : 2048;
}

export class OrbitScene implements BenchScene {
  readonly id = "S1" as const;
  readonly scene = new Scene();
  readonly camera = new PerspectiveCamera(CAMERA_FOV, 9 / 16, 0.1, 2000);
  private readonly pipeline: RenderPipeline;
  private readonly planets: { mesh: Group; omega: number; phase: number; spec: PlanetSpec }[] = [];
  private readonly disposables: { dispose(): void }[] = [];
  private time = 0;

  constructor(context: SceneContext) {
    this.scene.background = new Color("#020308");
    const size = textureSize();
    const random = seededRandom(1101);

    const sunTexture = this.track(planetAlbedo(1024, "gas", ["#ffcc55", "#ff9922", "#fff0a0"], 7));
    const sun = new Mesh(
      this.track(new SphereGeometry(2.2, 64, 32)),
      this.track(new MeshStandardMaterial({
        color: "#000000",
        emissive: new Color("#ffaa33"),
        emissiveMap: sunTexture,
        emissiveIntensity: 3,
      })),
    );
    this.scene.add(sun);
    this.scene.add(new PointLight("#fff1dd", 3, 0, 0));
    this.scene.add(new AmbientLight("#334466", 0.15));

    const normals: Record<SurfaceKind, Texture> = {
      rocky: this.track(surfaceNormal(size, "rocky", 21)),
      icy: this.track(surfaceNormal(size, "icy", 22)),
      gas: this.track(surfaceNormal(size, "gas", 23, 0.8)),
    };
    const sphere = this.track(new SphereGeometry(1, 96, 48));

    PLANETS.forEach((spec, index) => {
      const albedo = this.track(planetAlbedo(size, spec.kind, spec.palette, 100 + index));
      const material = this.track(new MeshStandardMaterial({
        map: albedo,
        normalMap: normals[spec.kind],
        roughness: spec.kind === "gas" ? 0.85 : 0.7,
        metalness: 0,
      }));
      const group = new Group();
      const mesh = new Mesh(sphere, material);
      mesh.scale.setScalar(spec.radius);
      mesh.rotation.z = 0.2 + index * 0.05;
      group.add(mesh);
      if (spec.ring) {
        const ring = new RingGeometry(spec.radius * 1.4, spec.radius * 2.4, 128, 1);
        const positions = ring.getAttribute("position");
        const uvs = ring.getAttribute("uv");
        for (let i = 0; i < positions.count; i += 1) {
          const r = Math.hypot(positions.getX(i), positions.getY(i));
          uvs.setXY(i, (r - spec.radius * 1.4) / spec.radius, 0.5);
        }
        const ringMesh = new Mesh(this.track(ring), this.track(new MeshStandardMaterial({
          map: this.track(ringTexture(55)),
          transparent: true,
          side: DoubleSide,
          roughness: 0.9,
        })));
        ringMesh.rotation.x = -Math.PI / 2 + 0.45;
        group.add(ringMesh);
      }
      this.scene.add(group);
      const speed = circularOrbitSpeed(SUN_MASS, spec.orbit, G);
      this.planets.push({ mesh: group, omega: speed / spec.orbit, phase: random() * Math.PI * 2, spec });

      const points: number[] = [];
      for (let i = 0; i <= 256; i += 1) {
        const a = i / 256 * Math.PI * 2;
        points.push(Math.cos(a) * spec.orbit, 0, Math.sin(a) * spec.orbit);
      }
      const lineGeometry = this.track(new BufferGeometry());
      lineGeometry.setAttribute("position", new Float32BufferAttribute(points, 3));
      this.scene.add(new Line(lineGeometry, this.track(new LineBasicMaterial({
        color: "#4a6a9a",
        transparent: true,
        opacity: 0.45,
      }))));
    });

    this.scene.add(this.createStars(random));

    const scenePass = pass(this.scene, this.camera);
    const color = scenePass.getTextureNode("output");
    this.pipeline = new RenderPipeline(context.renderer, color.add(bloom(color, 0.9, 0.4, 0.85)));
    this.disposables.push(this.pipeline);
    this.update(0);
  }

  private createStars(random: () => number): Sprite {
    const count = 5000;
    const positions = new Float32Array(count * 3);
    const colors = new Float32Array(count * 3);
    const sizes = new Float32Array(count);
    for (let i = 0; i < count; i += 1) {
      const u = random() * 2 - 1;
      const a = random() * Math.PI * 2;
      const s = Math.sqrt(1 - u * u);
      const r = 600 + random() * 200;
      positions.set([Math.cos(a) * s * r, u * r, Math.sin(a) * s * r], i * 3);
      const tint = 0.6 + random() * 0.4;
      colors.set([tint, tint * (0.85 + random() * 0.15), tint * (0.8 + random() * 0.2)], i * 3);
      sizes[i] = 1 + random() ** 3 * 3;
    }
    const material = this.track(new PointsNodeMaterial({ sizeAttenuation: false, transparent: false }));
    material.positionNode = instancedBufferAttribute(new InstancedBufferAttribute(positions, 3));
    material.colorNode = instancedBufferAttribute<"vec3">(new InstancedBufferAttribute(colors, 3));
    material.sizeNode = instancedBufferAttribute(new InstancedBufferAttribute(sizes, 1));
    const stars = new Sprite(material);
    stars.count = count;
    stars.frustumCulled = false;
    return stars;
  }

  private track<T extends { dispose(): void }>(item: T): T {
    this.disposables.push(item);
    return item;
  }

  update(dt: number): void {
    this.time += dt;
    for (const planet of this.planets) {
      const angle = planet.phase + planet.omega * this.time;
      planet.mesh.position.set(Math.cos(angle) * planet.spec.orbit, 0, Math.sin(angle) * planet.spec.orbit);
      planet.mesh.children[0].rotation.y += dt * 0.3;
    }
    this.updateCamera();
  }

  /** 0–15 s overview orbit, 15–30 s follow one planet (next planet each cycle). */
  private updateCamera(): void {
    const cycle = Math.floor(this.time / CAMERA_CYCLE_S);
    const local = this.time % CAMERA_CYCLE_S;
    if (local < CAMERA_CYCLE_S / 2) {
      const a = this.time * 0.05;
      this.camera.position.set(Math.sin(a) * 48, 34, Math.cos(a) * 48);
      this.camera.lookAt(0, 0, 0);
      return;
    }
    const planet = this.planets[cycle % this.planets.length];
    const p = planet.mesh.position;
    const out = new Vector3(p.x, 0, p.z).normalize();
    const distance = planet.spec.radius * 5;
    this.camera.position.set(
      p.x + out.x * distance - out.z * distance * 0.6,
      planet.spec.radius * 1.6,
      p.z + out.z * distance + out.x * distance * 0.6,
    );
    this.camera.lookAt(p);
  }

  render(): void {
    this.pipeline.render();
  }

  resize(width: number, height: number): void {
    this.camera.aspect = width / height;
    this.camera.updateProjectionMatrix();
  }

  dispose(): void {
    for (const item of this.disposables) item.dispose();
  }
}
