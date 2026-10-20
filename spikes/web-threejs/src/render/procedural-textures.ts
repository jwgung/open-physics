/**
 * Procedural stand-ins for real planet textures (no external assets in the spike).
 * Albedo: 2D canvas drawing (bands, blobs, craters) at full size, e.g. 2048².
 * Normal: Sobel filter over a procedural height canvas.
 * Equirectangular seams and poles are not treated; this is a load stand-in, not art.
 */
import {
  CanvasTexture,
  ClampToEdgeWrapping,
  LinearMipmapLinearFilter,
  NoColorSpace,
  RepeatWrapping,
  SRGBColorSpace,
} from "three/webgpu";
import { seededRandom } from "../random";

export type SurfaceKind = "rocky" | "gas" | "icy";

const makeCanvas = (width: number, height: number): [HTMLCanvasElement, CanvasRenderingContext2D] => {
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext("2d", { willReadFrequently: true });
  if (!context) throw new Error("2D canvas is unavailable.");
  return [canvas, context];
};

const pick = <T>(random: () => number, items: readonly T[]): T => items[Math.floor(random() * items.length)];

function paintSurface(
  context: CanvasRenderingContext2D,
  size: number,
  kind: SurfaceKind,
  palette: readonly string[],
  random: () => number,
  heightOnly: boolean,
): void {
  const width = size;
  const height = size / 2;
  context.fillStyle = heightOnly ? "#808080" : palette[0];
  context.fillRect(0, 0, width, height);

  if (kind === "gas") {
    for (let i = 0; i < 70; i += 1) {
      const y = random() * height;
      const bandHeight = 4 + random() * height * 0.08;
      context.globalAlpha = 0.25 + random() * 0.5;
      context.fillStyle = heightOnly ? `rgb(${120 + random() * 40 | 0},0,0)` : pick(random, palette);
      context.fillRect(0, y, width, bandHeight);
    }
    for (let i = 0; i < 900; i += 1) {
      context.globalAlpha = 0.08 + random() * 0.2;
      context.fillStyle = heightOnly ? `rgb(${100 + random() * 80 | 0},0,0)` : pick(random, palette);
      context.beginPath();
      context.ellipse(random() * width, random() * height, 8 + random() * 90, 1 + random() * 6, 0, 0, Math.PI * 2);
      context.fill();
    }
  } else {
    for (let i = 0; i < 700; i += 1) {
      const x = random() * width;
      const y = random() * height;
      const r = 6 + random() * size * 0.05;
      const gradient = context.createRadialGradient(x, y, 0, x, y, r);
      const color = heightOnly ? `rgb(${80 + random() * 100 | 0},0,0)` : pick(random, palette);
      gradient.addColorStop(0, color);
      gradient.addColorStop(1, "rgba(0,0,0,0)");
      context.globalAlpha = 0.15 + random() * 0.3;
      context.fillStyle = gradient;
      context.fillRect(x - r, y - r, r * 2, r * 2);
    }
    const craters = kind === "rocky" ? 260 : 60;
    for (let i = 0; i < craters; i += 1) {
      const x = random() * width;
      const y = random() * height;
      const r = 2 + random() ** 2 * size * 0.025;
      context.globalAlpha = 0.5;
      context.lineWidth = Math.max(1, r * 0.25);
      context.strokeStyle = heightOnly ? "#d0d0d0" : "rgba(255,255,255,0.35)";
      context.beginPath();
      context.arc(x, y, r, 0, Math.PI * 2);
      context.stroke();
      context.fillStyle = heightOnly ? "#303030" : "rgba(0,0,0,0.25)";
      context.beginPath();
      context.arc(x, y, r * 0.8, 0, Math.PI * 2);
      context.fill();
    }
    if (kind === "icy") {
      for (let i = 0; i < 160; i += 1) {
        context.globalAlpha = 0.25;
        context.strokeStyle = heightOnly ? "#404040" : "rgba(120,80,60,0.6)";
        context.lineWidth = 1 + random() * 3;
        context.beginPath();
        const x = random() * width;
        const y = random() * height;
        context.moveTo(x, y);
        context.quadraticCurveTo(x + random() * 300 - 150, y + random() * 80 - 40, x + random() * 500 - 250, y + random() * 120 - 60);
        context.stroke();
      }
    }
  }
  context.globalAlpha = 1;
}

function finish(texture: CanvasTexture, color: boolean): CanvasTexture {
  texture.colorSpace = color ? SRGBColorSpace : NoColorSpace;
  texture.wrapS = RepeatWrapping;
  texture.wrapT = ClampToEdgeWrapping;
  texture.minFilter = LinearMipmapLinearFilter;
  texture.anisotropy = 4;
  texture.generateMipmaps = true;
  texture.needsUpdate = true;
  return texture;
}

/** Equirectangular albedo, `size` × `size` (spec: 2048²). */
export function planetAlbedo(size: number, kind: SurfaceKind, palette: readonly string[], seed: number): CanvasTexture {
  const [canvas, context] = makeCanvas(size, size);
  // Paint a 2:1 map into the top half, then stretch to the full square texture.
  paintSurface(context, size, kind, palette, seededRandom(seed), false);
  context.drawImage(canvas, 0, 0, size, size / 2, 0, 0, size, size);
  return finish(new CanvasTexture(canvas), true);
}

/** Tangent-space normal map from a procedural height field (Sobel). */
export function surfaceNormal(size: number, kind: SurfaceKind, seed: number, strength = 2.5): CanvasTexture {
  const [heightCanvas, heightContext] = makeCanvas(size, size);
  paintSurface(heightContext, size, kind, ["#808080"], seededRandom(seed), true);
  heightContext.drawImage(heightCanvas, 0, 0, size, size / 2, 0, 0, size, size);
  const source = heightContext.getImageData(0, 0, size, size).data;
  const [canvas, context] = makeCanvas(size, size);
  const output = context.createImageData(size, size);
  const out = output.data;
  const h = (x: number, y: number): number => source[(((y + size) % size) * size + ((x + size) % size)) * 4] / 255;
  for (let y = 0; y < size; y += 1) {
    for (let x = 0; x < size; x += 1) {
      const dx = (h(x + 1, y - 1) + 2 * h(x + 1, y) + h(x + 1, y + 1)) - (h(x - 1, y - 1) + 2 * h(x - 1, y) + h(x - 1, y + 1));
      const dy = (h(x - 1, y + 1) + 2 * h(x, y + 1) + h(x + 1, y + 1)) - (h(x - 1, y - 1) + 2 * h(x, y - 1) + h(x + 1, y - 1));
      const nx = -dx * strength;
      const ny = -dy * strength;
      const inv = 1 / Math.hypot(nx, ny, 1);
      const i = (y * size + x) * 4;
      out[i] = (nx * inv * 0.5 + 0.5) * 255;
      out[i + 1] = (ny * inv * 0.5 + 0.5) * 255;
      out[i + 2] = (inv * 0.5 + 0.5) * 255;
      out[i + 3] = 255;
    }
  }
  context.putImageData(output, 0, 0);
  return finish(new CanvasTexture(canvas), false);
}

/** 1D radial ring texture (alpha bands), sampled with u = radius. */
export function ringTexture(seed: number): CanvasTexture {
  const [canvas, context] = makeCanvas(1024, 4);
  const random = seededRandom(seed);
  for (let x = 0; x < 1024; x += 1) {
    const alpha = Math.max(0, Math.min(1, 0.35 + Math.sin(x * 0.05) * 0.2 + random() * 0.5 - (x < 60 || x > 980 ? 0.6 : 0)));
    const shade = 180 + random() * 60 | 0;
    context.fillStyle = `rgba(${shade},${shade * 0.9 | 0},${shade * 0.75 | 0},${alpha})`;
    context.fillRect(x, 0, 1, 4);
  }
  const texture = new CanvasTexture(canvas);
  texture.colorSpace = SRGBColorSpace;
  texture.needsUpdate = true;
  return texture;
}
