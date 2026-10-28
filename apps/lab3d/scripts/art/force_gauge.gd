## The press-and-hold gauge (2026-10-28): a kid "power bar" beside the object a finger holds, no
## numbers. A white rounded frame around a dark track; the fill grows from the bottom with the hold's
## force share (HoldRamp.fraction) and turns from yellow to orange to red as it fills. It faces the
## front camera (+z). Meshes only (built once; set_fraction scales the fill and swaps one of three
## cached colour meshes).
class_name ForceGauge
extends Node3D

const HEIGHT := 1.3        # m of track
const WIDTH := 0.34        # m, frame
const DEPTH := 0.12
const TRACK := 0.22        # m, track and fill width
const COLOURS := [[0.5, ArtPalette.YELLOW, ArtPalette.YELLOW_TOP], [0.8, ArtPalette.ORANGE, ArtPalette.ORANGE_TOP], [2.0, ArtPalette.RED, ArtPalette.RED_TOP]]

var fill: MeshInstance3D
var fraction := 0.0
var _fills: Array[Mesh] = []
var _colour := -1


func _init() -> void:
	name = "ForceGauge"
	var b := ArtKit.builder()
	b.ao_min = 0.95
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, HEIGHT * 0.5, 0.0)), Vector3(WIDTH, HEIGHT + WIDTH - TRACK, DEPTH), 0.05, 1, ArtPalette.WHITE)
	b.ao_min = 1.0
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, HEIGHT * 0.5, DEPTH * 0.5)), Vector3(TRACK, HEIGHT, 0.02), 0.0, 1, ArtPalette.INK)
	var frame := ArtKit.instance(b.commit())
	frame.name = "Frame"
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(frame)
	for c in COLOURS:
		var f := ArtKit.builder()
		f.ao_min = 1.0
		# A unit-high bar standing on the node origin (scaled along y to the fill).
		f.add_rounded_box(Transform3D(Basis(), Vector3(0.0, 0.5, DEPTH * 0.5 + 0.015)), Vector3(TRACK - 0.02, 1.0, 0.02), 0.0, 1, c[1], c[2])
		_fills.append(f.commit())
	fill = ArtKit.instance(_fills[0])
	fill.name = "Fill"
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fill)
	visible = false
	set_fraction(0.0)


## The fill for a force share `f` (0..1).
func set_fraction(f: float) -> void:
	fraction = clampf(f, 0.0, 1.0)
	fill.visible = fraction > 0.001
	fill.scale = Vector3(1.0, maxf(fraction * HEIGHT, 0.001), 1.0)
	var c := 0
	while fraction > COLOURS[c][0]:
		c += 1
	if c != _colour:
		_colour = c
		fill.mesh = _fills[c]
