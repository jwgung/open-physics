# src/physics — the formula oracle

`src/physics` holds the TypeScript formulas and models that the 3D app (`apps/lab3d`) checks its GDScript port against. `apps/lab3d/tools/*-vectors.test.ts` compute the expected values from these files into `apps/lab3d/tests/*_vectors.json`, and the Godot tests compare the GDScript results with those tables. Change a formula here only together with those tests (`npm test`, then the Godot suite).

- `laws/`, `core.ts`, `fields.ts`, `world.ts`, `simulation.ts`, `quantities.ts`: the formula core.
- `mechanics-challenges.ts` (lever, pulley, orbit), `mechanics-scenes.ts` (pendulum), `materials.ts` (restitution and friction of rubber, wood, steel, clay): moved from the web 2D app.

The 2D web labs (`src/app`, `index.html`, the Vite site) were removed on 2026-10-30 ([ADR 0002](../docs/adr/0002-drop-web-2d.md)). The product is the 3D app: [`apps/lab3d/README.md`](../apps/lab3d/README.md).
