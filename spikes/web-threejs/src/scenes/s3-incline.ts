/**
 * S3 guided incline friction lab. Rapier + formula correction layer (InclineRig).
 * Displayed quantities (angle, mg·sinθ, μs·N, a) come from the formula core; the
 * measured distance comes from Rapier and is shown next to the formula's ½at².
 * For continuous benchmarking the box is put back at the top once it leaves the plank.
 */
import type RAPIER_NS from "@dimforge/rapier3d-compat";
import {
  BoxGeometry,
  Color,
  DirectionalLight,
  HemisphereLight,
  Mesh,
  MeshStandardMaterial,
  PCFShadowMap,
  PerspectiveCamera,
  Scene,
  Vector3,
} from "three/webgpu";
import { expectedDistance, S3_PARAMS } from "../physics/incline-formula";
import { BOX_HALF, FIXED_DT, InclineRig, PLANK_HALF } from "../physics/incline-rig";
import { CameraRig, GestureInput } from "../render/camera-rig";
import { applyRoomEnvironment } from "../render/environment";
import { CAMERA_FOV, FixedStepper, type BenchScene, type SceneContext } from "./types";

type Rapier = typeof RAPIER_NS;

const DEFAULT_ANGLE = 35;
const PRESETS = [20, 26, 27, 35];

export class InclineScene implements BenchScene {
  readonly id = "S3" as const;
  readonly scene = new Scene();
  readonly camera = new PerspectiveCamera(CAMERA_FOV, 9 / 16, 0.1, 200);
  private readonly rig: InclineRig;
  private readonly stepper = new FixedStepper(FIXED_DT);
  private readonly cameraRig: CameraRig;
  private readonly input: GestureInput;
  private readonly plankMesh: Mesh;
  private readonly boxMesh: Mesh;
  private readonly readoutElement: HTMLElement;
  private readonly slider: HTMLInputElement;
  private readonly disposables: { dispose(): void }[] = [];
  private frameCount = 0;

  constructor(rapier: Rapier, private readonly context: SceneContext) {
    context.renderer.shadowMap.enabled = true;
    context.renderer.shadowMap.type = PCFShadowMap;
    this.track(applyRoomEnvironment(context.renderer, this.scene));
    this.scene.background = new Color("#d7dfe8");
    this.rig = new InclineRig(rapier, DEFAULT_ANGLE);

    this.scene.add(new HemisphereLight("#f2f6ff", "#6f6250", 1));
    const sun = new DirectionalLight("#ffffff", 2.2);
    sun.position.set(3, 10, 6);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    Object.assign(sun.shadow.camera, { left: -8, right: 8, top: 8, bottom: -8, near: 1, far: 30 });
    this.scene.add(sun);

    const floor = new Mesh(
      this.track(new BoxGeometry(20, 0.2, 8)),
      this.track(new MeshStandardMaterial({ color: "#ebe6dc", roughness: 0.95 })),
    );
    floor.position.y = -3.6;
    floor.receiveShadow = true;
    this.scene.add(floor);

    this.plankMesh = new Mesh(
      this.track(new BoxGeometry(PLANK_HALF.x * 2, PLANK_HALF.y * 2, PLANK_HALF.z * 2)),
      this.track(new MeshStandardMaterial({ color: "#a77b4f", roughness: 0.7 })),
    );
    this.plankMesh.receiveShadow = true;
    this.plankMesh.castShadow = true;
    this.scene.add(this.plankMesh);
    this.boxMesh = new Mesh(
      this.track(new BoxGeometry(BOX_HALF * 2, BOX_HALF * 2, BOX_HALF * 2)),
      this.track(new MeshStandardMaterial({ color: "#2f7fd1", roughness: 0.45, metalness: 0.1 })),
    );
    this.boxMesh.castShadow = true;
    this.scene.add(this.boxMesh);

    this.cameraRig = new CameraRig(this.camera, {
      azimuth: 0.15,
      elevation: 0.25,
      distance: 18,
      target: new Vector3(0, -1.4, 0),
    });
    this.input = new GestureInput(context.canvas, this.cameraRig);

    const panel = document.createElement("section");
    panel.className = "lab-panel";
    panel.innerHTML = `
      <label>빗면 각도 <input type="range" min="0" max="45" step="0.5" value="${DEFAULT_ANGLE}" /></label>
      <div class="presets">${PRESETS.map((a) => `<button data-angle="${a}">${a}°</button>`).join("")}
        <button data-reset>다시</button></div>
      <dl class="readout"></dl>`;
    context.panel.replaceChildren(panel);
    this.slider = panel.querySelector("input") as HTMLInputElement;
    this.readoutElement = panel.querySelector(".readout") as HTMLElement;
    this.slider.addEventListener("input", () => this.setAngle(Number(this.slider.value)));
    panel.querySelectorAll<HTMLButtonElement>("button[data-angle]").forEach((button) => {
      button.addEventListener("click", () => this.setAngle(Number(button.dataset.angle)));
    });
    panel.querySelector("button[data-reset]")?.addEventListener("click", () => this.setAngle(this.rig.angleDeg));
    this.syncMeshes();
    this.renderReadout();
  }

  private track<T extends { dispose(): void }>(item: T): T {
    this.disposables.push(item);
    return item;
  }

  private setAngle(angleDeg: number): void {
    this.slider.value = String(angleDeg);
    this.rig.setAngle(angleDeg);
    this.syncMeshes();
    this.renderReadout();
  }

  private syncMeshes(): void {
    this.plankMesh.rotation.z = this.rig.angleDeg * Math.PI / 180;
    const p = this.rig.box.translation();
    this.boxMesh.position.set(p.x, p.y, p.z);
    this.boxMesh.rotation.z = this.plankMesh.rotation.z;
  }

  private renderReadout(): void {
    const r = this.rig.readout;
    const sample = this.rig.sample();
    const t = sample.slideTime ?? 0;
    const status = sample.phase === "holding" ? "정지 유지" : "미끄러짐";
    this.readoutElement.innerHTML = `
      <dt>빗면 각도</dt><dd>${r.angleDeg.toFixed(1)}° (임계각 ${r.criticalAngleDeg.toFixed(2)}°)</dd>
      <dt>중력 접선 성분 mg·sinθ</dt><dd>${r.tangentialGravity.toFixed(3)} N</dd>
      <dt>최대 정지 마찰력 μs·N</dt><dd>${r.maxStaticFriction.toFixed(3)} N</dd>
      <dt>가속도 g(sinθ−μk·cosθ)</dt><dd>${r.slidingAcceleration.toFixed(3)} m/s²</dd>
      <dt>이동 거리 (엔진 / 공식 ½at²)</dt><dd>${Math.max(0, sample.distance).toFixed(3)} m / ${expectedDistance(r.slidingAcceleration, t).toFixed(3)} m</dd>
      <dt>상태</dt><dd>${status} · t=${t.toFixed(2)} s · μs=${S3_PARAMS.staticCoefficient}, μk=${S3_PARAMS.kineticCoefficient}</dd>`;
  }

  update(dt: number): void {
    this.stepper.advance(dt, () => this.rig.step());
    if (this.rig.finished) this.rig.setAngle(this.rig.angleDeg);
    this.syncMeshes();
    // DOM readout at ~10 Hz so the panel does not dominate frame cost.
    this.frameCount += 1;
    if (this.frameCount % 6 === 0) this.renderReadout();
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
    this.rig.dispose();
    this.context.panel.replaceChildren();
    for (const item of this.disposables) item.dispose();
    this.context.renderer.shadowMap.enabled = false;
  }
}
