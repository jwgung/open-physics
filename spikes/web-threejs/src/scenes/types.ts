import type { PerspectiveCamera, Scene, WebGPURenderer } from "three/webgpu";
import type { WebGLRenderer } from "three";

/** Either the node renderer (WebGPU / forced WebGL2) or the classic WebGLRenderer. */
export type AnyRenderer = WebGPURenderer | WebGLRenderer;

export type SceneId = "S1" | "S2" | "S3";

export interface SceneContext {
  renderer: AnyRenderer;
  /** True when `renderer` is the classic WebGLRenderer (no TSL / node materials). */
  classic: boolean;
  canvas: HTMLCanvasElement;
  /** Container for scene-specific UI (S3 panel). */
  panel: HTMLElement;
}

export interface BenchScene {
  readonly id: SceneId;
  readonly scene: Scene;
  readonly camera: PerspectiveCamera;
  /** Called once per animation frame with frame delta (s, clamped). */
  update(dt: number): void;
  /** Renders the frame (scenes with post-processing override the default). */
  render(): void;
  resize(width: number, height: number): void;
  dispose(): void;
}

/** Same portrait framing for all scenes (benchmark-spec §3). */
export const CAMERA_FOV = 55;

/** Fixed-step accumulator shared by S2/S3: physics always advances in 1/60 s steps. */
export class FixedStepper {
  private accumulator = 0;

  constructor(readonly dt: number, private readonly maxSteps = 4) {}

  advance(frameDt: number, step: () => void): number {
    this.accumulator = Math.min(this.accumulator + frameDt, this.dt * this.maxSteps);
    let steps = 0;
    while (this.accumulator >= this.dt) {
      step();
      this.accumulator -= this.dt;
      steps += 1;
    }
    return steps;
  }
}
