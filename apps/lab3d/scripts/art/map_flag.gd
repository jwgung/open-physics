## The flag that stands at a map spot with all its stamps (island_home_screen.gd): a pole with a
## yellow knob and one plain red cloth banner off its top (2026-10-28 user: a single colour; the old
## 4-sided cone read as a red diamond). Built once per spot into the spot's flag mesh.
class_name MapFlag
extends RefCounted

const POLE_HEIGHT := 2.2
const POLE_RADIUS := 0.05
## The banner: its centre off the pole, its size (x along the cloth, y up, z thickness).
const CENTRE := Vector3(0.47, 1.83, 0.0)
const SIZE := Vector3(0.8, 0.52, 0.06)


static func build(fb: ArtMeshBuilder) -> void:
	fb.add_cylinder(Transform3D.IDENTITY, POLE_RADIUS, POLE_RADIUS, POLE_HEIGHT, 6, ArtPalette.TRUNK)
	fb.add_sphere(Transform3D(Basis(), Vector3(0.0, POLE_HEIGHT + 0.04, 0.0)), 0.09, 4, 8, ArtPalette.YELLOW)
	fb.add_rounded_box(Transform3D(Basis(), CENTRE), SIZE, 0.03, 1, ArtPalette.RED)
