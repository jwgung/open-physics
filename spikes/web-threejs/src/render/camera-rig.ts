/**
 * Spherical camera rig: two-finger (or one-finger on empty space / mouse) orbit,
 * pinch or wheel zoom. Kept tiny instead of OrbitControls so the S2 drag gesture
 * and the camera gesture can share one pointer stream.
 */
import { PerspectiveCamera, Vector3 } from "three/webgpu";

export class CameraRig {
  azimuth: number;
  elevation: number;
  distance: number;
  readonly target: Vector3;

  constructor(
    readonly camera: PerspectiveCamera,
    start: { azimuth: number; elevation: number; distance: number; target: Vector3 },
    private readonly limits = { minDistance: 3, maxDistance: 40 },
  ) {
    this.azimuth = start.azimuth;
    this.elevation = start.elevation;
    this.distance = start.distance;
    this.target = start.target.clone();
    this.apply();
  }

  rotate(dx: number, dy: number): void {
    this.azimuth -= dx * 0.006;
    this.elevation = Math.min(1.45, Math.max(0.05, this.elevation + dy * 0.006));
    this.apply();
  }

  zoom(factor: number): void {
    this.distance = Math.min(this.limits.maxDistance, Math.max(this.limits.minDistance, this.distance * factor));
    this.apply();
  }

  apply(): void {
    const cosE = Math.cos(this.elevation);
    this.camera.position.set(
      this.target.x + this.distance * cosE * Math.sin(this.azimuth),
      this.target.y + this.distance * Math.sin(this.elevation),
      this.target.z + this.distance * cosE * Math.cos(this.azimuth),
    );
    this.camera.lookAt(this.target);
  }
}

interface PointerTrack { x: number; y: number }

/**
 * Pointer router. `onSinglePointerDown` may claim a one-finger gesture (S2 drag);
 * unclaimed one-finger gestures and all two-finger gestures drive the camera.
 */
export class GestureInput {
  private readonly pointers = new Map<number, PointerTrack>();
  private claimed: number | null = null;
  private pinchDistance = 0;
  private center: PointerTrack | null = null;

  constructor(
    private readonly element: HTMLElement,
    private readonly rig: CameraRig,
    private readonly handlers: {
      onSinglePointerDown?: (event: PointerEvent) => boolean;
      onDrag?: (event: PointerEvent) => void;
      onDragEnd?: (event: PointerEvent) => void;
    } = {},
  ) {
    element.addEventListener("pointerdown", this.down);
    element.addEventListener("pointermove", this.move);
    element.addEventListener("pointerup", this.up);
    element.addEventListener("pointercancel", this.up);
    element.addEventListener("wheel", this.wheel, { passive: false });
  }

  dispose(): void {
    this.element.removeEventListener("pointerdown", this.down);
    this.element.removeEventListener("pointermove", this.move);
    this.element.removeEventListener("pointerup", this.up);
    this.element.removeEventListener("pointercancel", this.up);
    this.element.removeEventListener("wheel", this.wheel);
  }

  private readonly down = (event: PointerEvent): void => {
    this.element.setPointerCapture(event.pointerId);
    this.pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
    if (this.pointers.size === 1 && this.handlers.onSinglePointerDown?.(event)) {
      this.claimed = event.pointerId;
      return;
    }
    if (this.pointers.size >= 2 && this.claimed !== null) {
      this.handlers.onDragEnd?.(event);
      this.claimed = null;
    }
    this.resetMulti();
  };

  private readonly move = (event: PointerEvent): void => {
    const track = this.pointers.get(event.pointerId);
    if (!track) return;
    if (this.claimed === event.pointerId) {
      track.x = event.clientX;
      track.y = event.clientY;
      this.handlers.onDrag?.(event);
      return;
    }
    if (this.pointers.size === 1) {
      this.rig.rotate(event.clientX - track.x, event.clientY - track.y);
      track.x = event.clientX;
      track.y = event.clientY;
      return;
    }
    track.x = event.clientX;
    track.y = event.clientY;
    const [a, b] = [...this.pointers.values()];
    const center = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
    const distance = Math.hypot(a.x - b.x, a.y - b.y);
    if (this.center) this.rig.rotate(center.x - this.center.x, center.y - this.center.y);
    if (this.pinchDistance > 0 && distance > 0) this.rig.zoom(this.pinchDistance / distance);
    this.center = center;
    this.pinchDistance = distance;
  };

  private readonly up = (event: PointerEvent): void => {
    if (this.claimed === event.pointerId) {
      this.handlers.onDragEnd?.(event);
      this.claimed = null;
    }
    this.pointers.delete(event.pointerId);
    this.resetMulti();
  };

  private readonly wheel = (event: WheelEvent): void => {
    event.preventDefault();
    this.rig.zoom(event.deltaY > 0 ? 1.1 : 1 / 1.1);
  };

  private resetMulti(): void {
    if (this.pointers.size >= 2) {
      const [a, b] = [...this.pointers.values()];
      this.center = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
      this.pinchDistance = Math.hypot(a.x - b.x, a.y - b.y);
    } else {
      this.center = null;
      this.pinchDistance = 0;
    }
  }
}
