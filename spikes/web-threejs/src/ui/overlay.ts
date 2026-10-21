import type { OpbenchLine } from "../bench/frame-stats";
import type { SceneId } from "../scenes/types";

export interface OverlayOptions {
  backend: string;
  backendChoice: "auto" | "webgl" | "webgpu";
  navigatorGpu: boolean;
  onScene(id: SceneId): void;
  onBackend(choice: "auto" | "webgl" | "webgpu"): void;
}

export interface Overlay {
  setScene(id: SceneId): void;
  setStats(line: OpbenchLine): void;
}

/** Top bar: scene buttons, FPS overlay toggle, backend switch (reloads the page). */
export function createOverlay(root: HTMLElement, options: OverlayOptions): Overlay {
  const bar = document.createElement("header");
  bar.className = "bar";
  bar.innerHTML = `
    <nav>${(["S1", "S2", "S3"] as const).map((id) => `<button data-scene="${id}">${id}</button>`).join("")}</nav>
    <button data-fps aria-pressed="true">FPS</button>
    <select data-backend aria-label="렌더 백엔드">
      <option value="auto">auto</option><option value="webgpu">WebGPU</option><option value="webgl">WebGL2</option>
    </select>`;
  const stats = document.createElement("output");
  stats.className = "fps";
  stats.textContent = `${options.backend} · 측정 중…`;
  root.append(bar, stats);

  bar.querySelectorAll<HTMLButtonElement>("button[data-scene]").forEach((button) => {
    button.addEventListener("click", () => options.onScene(button.dataset.scene as SceneId));
  });
  const fpsButton = bar.querySelector<HTMLButtonElement>("button[data-fps]");
  fpsButton?.addEventListener("click", () => {
    const visible = stats.hidden;
    stats.hidden = !visible;
    fpsButton.setAttribute("aria-pressed", String(visible));
  });
  const select = bar.querySelector<HTMLSelectElement>("select[data-backend]");
  if (select) {
    select.value = options.backendChoice;
    select.addEventListener("change", () => options.onBackend(select.value as OverlayOptions["backendChoice"]));
  }

  return {
    setScene(id) {
      bar.querySelectorAll<HTMLButtonElement>("button[data-scene]").forEach((button) => {
        button.setAttribute("aria-current", String(button.dataset.scene === id));
      });
      stats.textContent = `${options.backend} · ${id} · 측정 중…`;
    },
    setStats(line) {
      if (stats.hidden) return;
      stats.textContent = `${options.backend}${options.navigatorGpu ? "" : " (gpu 없음)"} · ${line.scene} · ${line.fps.toFixed(1)} fps · p95 ${line.p95ms} ms · long ${line.long}`;
    },
  };
}
