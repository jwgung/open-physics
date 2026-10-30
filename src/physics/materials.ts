/**
 * Educational materials (rubber, wood, steel, clay): restitution and friction coefficients of the
 * simple contact model. The 3D app's formula parity vectors (apps/lab3d/tools/*-vectors.test.ts)
 * read them from here; the GDScript port keeps the same values. Moved from the deprecated web 2D
 * playground (src/app/physics-playground.ts) on 2026-10-30 (docs/adr/0002-drop-web-2d.md).
 */
export type PlaygroundMaterial = "rubber" | "wood" | "steel" | "clay";

export const MATERIALS: Readonly<Record<PlaygroundMaterial, {
  restitution: number;
  friction: number;
}>> = {
  rubber: { restitution: 0.88, friction: 0.42 },
  wood: { restitution: 0.5, friction: 0.22 },
  steel: { restitution: 0.72, friction: 0.08 },
  clay: { restitution: 0.08, friction: 0.58 },
};
