/**
 * Open Physics 3D spike A: Three.js WebGPURenderer (WebGL2 fallback) + Rapier + Capacitor.
 * Query params: ?backend=webgl|webgpu|auto  ?scene=S1|S2|S3  ?tex=512|1024|2048
 */
import RAPIER from "@dimforge/rapier3d-compat";
import { ACESFilmicToneMapping, WebGPURenderer } from "three/webgpu";
import { emitOpbench } from "./bench/opbench-log";
import { FrameStats } from "./bench/frame-stats";
import { OrbitScene } from "./scenes/s1-orbit";
import { SandboxScene } from "./scenes/s2-sandbox";
import { InclineScene } from "./scenes/s3-incline";
import type { BenchScene, SceneContext, SceneId } from "./scenes/types";
import { createOverlay } from "./ui/overlay";

type BackendChoice = "auto" | "webgl" | "webgpu";

const SCENE_KEY = "opspike.scene";
const params = new URLSearchParams(location.search);

const readStored = (key: string): string | null => {
  try { return localStorage.getItem(key); } catch { return null; }
};
const writeStored = (key: string, value: string): void => {
  try { localStorage.setItem(key, value); } catch { /* storage unavailable */ }
};

function backendChoice(): BackendChoice {
  const value = params.get("backend") ?? readStored("opspike.backend");
  return value === "webgl" || value === "webgpu" ? value : "auto";
}

function initialScene(): SceneId {
  const value = params.get("scene") ?? readStored(SCENE_KEY);
  return value === "S1" || value === "S2" || value === "S3" ? value : "S1";
}

async function main(): Promise<void> {
  const canvas = document.querySelector<HTMLCanvasElement>("#view");
  const ui = document.querySelector<HTMLElement>("#ui");
  if (!canvas || !ui) throw new Error("Missing #view or #ui.");

  const choice = backendChoice();
  const hasWebGPU = "gpu" in navigator;
  const renderer = new WebGPURenderer({ canvas, antialias: true, forceWebGL: choice === "webgl" });
  await renderer.init();
  const backend = (renderer.backend as { isWebGPUBackend?: boolean }).isWebGPUBackend ? "WebGPU" : "WebGL2";
  if (choice === "webgpu" && backend !== "WebGPU") console.warn("WebGPU requested but unavailable; using WebGL2.");
  renderer.setPixelRatio(window.devicePixelRatio);
  renderer.toneMapping = ACESFilmicToneMapping;
  await RAPIER.init();

  const panel = document.createElement("div");
  const context: SceneContext = { renderer, canvas, panel };
  const stats = new FrameStats(emitOpbench);
  let current: BenchScene | null = null;

  const overlay = createOverlay(ui, {
    backend,
    backendChoice: choice,
    navigatorGpu: hasWebGPU,
    onScene: (id) => switchScene(id),
    onBackend: (next) => {
      writeStored("opspike.backend", next);
      const url = new URL(location.href);
      url.searchParams.set("backend", next);
      location.replace(url.toString());
    },
  });
  ui.append(panel);

  function create(id: SceneId): BenchScene {
    if (id === "S1") return new OrbitScene(context);
    if (id === "S2") return new SandboxScene(RAPIER, context);
    return new InclineScene(RAPIER, context);
  }

  function switchScene(id: SceneId): void {
    current?.dispose();
    current = create(id);
    writeStored(SCENE_KEY, id);
    overlay.setScene(id);
    // Debug hook for headless checks (spike only).
    (window as unknown as { __opspike?: unknown }).__opspike = current;
    resize();
    stats.reset();
  }

  function resize(): void {
    const width = window.innerWidth;
    const height = window.innerHeight;
    renderer.setSize(width, height, false);
    current?.resize(width, height);
  }

  window.addEventListener("resize", resize);
  switchScene(initialScene());

  let last = performance.now();
  await renderer.setAnimationLoop((now) => {
    if (!current) return;
    stats.frame(now, current.id);
    const dt = Math.min(0.1, (now - last) / 1000);
    last = now;
    current.update(dt);
    current.render();
    if (stats.latest) overlay.setStats(stats.latest);
  });
}

main().catch((error: unknown) => {
  console.error(error);
  document.body.insertAdjacentHTML("beforeend", `<pre class="fatal">${String(error)}</pre>`);
});
