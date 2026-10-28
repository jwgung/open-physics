## The surface material a box slides on, as a thin skin over the slide's top or the push track
## (2026-10-28 user request: the conditions should read at a glance; steel, wood, rubber and clay looked the
## same, yellow). Drawn like the picture buttons (PickPictures): steel = grey with white shine
## streaks, wood = brown with grain lines along the way, rubber = dark with ridges across it, clay =
## terracotta with light smears. Visual only: the skin's top is SKIN_LIFT over the surface it covers,
## the bodies, their shapes and the friction are the lab's. It is added to the surface's own mesh
## (no extra node); the labs keep one mesh per material.
class_name SurfaceSkin
extends RefCounted

const SKIN := 0.02                 # m: the skin's thickness (it sinks into the surface under it)
const SKIN_LIFT := 0.001           # m: its top over the surface (no z-fighting; marks and ticks are higher)
const PATTERN := 0.0015            # m: the pattern over the skin's top
const IDS := ["steel", "wood", "rubber", "clay"]


## The skin colour of material `id` (ArtPalette; unknown: wood).
static func colour(id: String) -> Color:
	return {"steel": ArtPalette.STEEL, "wood": ArtPalette.WOOD, "rubber": ArtPalette.RUBBER, "clay": ArtPalette.CLAY}.get(id, ArtPalette.WOOD)


## Adds the skin of material `id`, `length` (x) by `width` (z), to `b`: its top SKIN_LIFT over `xf`'s
## origin (the surface), in xf's frame.
static func add_to(b: ArtMeshBuilder, xf: Transform3D, id: String, length: float, width: float) -> void:
	var ao := b.ao_min
	b.ao_min = 1.0
	var top := SKIN_LIFT
	b.add_rounded_box(xf * Transform3D(Basis(), Vector3(0.0, top - SKIN * 0.5, 0.0)), Vector3(length, SKIN, width), 0.0, 1, colour(id))
	var y := top + PATTERN * 0.5 - 0.0005   # pattern strips: 1 mm over the skin, their base inside it
	var half := length * 0.5
	match id:
		"steel":
			# Diagonal shine streaks, two by two.
			var x := -half + 0.6
			while x < half - 0.6:
				for k in [0.0, 0.22]:
					var at := Vector3(x + k, y, -width * 0.12)
					b.add_rounded_box(xf * Transform3D(Basis(Vector3.UP, 0.55), at), Vector3(0.7 - k, PATTERN, 0.06), 0.0, 1, ArtPalette.STEEL_SHINE)
				x += 1.7
		"wood":
			# Grain lines along the way, broken and staggered.
			var rows := maxi(3, int(width / 0.28))
			for r in rows:
				var z := -width * 0.5 + width * (r + 0.5) / rows
				var x := -half + 0.15 + fmod(r * 0.73, 1.1)
				while x < half - 0.3:
					var l := minf(0.9 + fmod(r * 0.37 + x, 0.6), half - 0.15 - x)
					b.add_rounded_box(xf * Transform3D(Basis(), Vector3(x + l * 0.5, y, z)), Vector3(l, PATTERN, 0.035), 0.0, 1, ArtPalette.WOOD_GRAIN)
					x += l + 0.35
		"rubber":
			# Ridges across the way.
			var x := -half + 0.2
			while x < half - 0.1:
				b.add_rounded_box(xf * Transform3D(Basis(), Vector3(x, y, 0.0)), Vector3(0.07, PATTERN, width - 0.12), 0.0, 1, ArtPalette.RUBBER_RIDGE)
				x += 0.3
		"clay":
			# Light smears, scattered.
			var i := 0
			var x := -half + 0.4
			while x < half - 0.4:
				var z := (fmod(i * 0.61, 1.0) - 0.5) * (width - 0.4)
				b.add_rounded_box(xf * Transform3D(Basis(Vector3.UP, 0.3 * (i % 3 - 1)), Vector3(x, y, z)), Vector3(0.45, PATTERN, 0.16), 0.0, 1, ArtPalette.CLAY_SMEAR)
				x += 0.85
				i += 1
	b.ao_min = ao
