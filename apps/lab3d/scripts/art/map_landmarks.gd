## The island map's spot landmarks (2026-10-27 user decision "지도 전체 손보기"): one small,
## chunky model per lab, readable from the map camera (about 1-2 m), so a child sees what is done
## there before reading its name. Built into the caller's builder (MapIsland merges all 11 into one
## mesh); the shapes echo each lab's own props and colours (experiments/*/..._props.gd).
## Visual only: the labs' physics never sees these.
class_name MapLandmarks
extends RefCounted

## Radius of the round stage (MapIsland builds it) each landmark stands on; 0 = no stage (the
## buoyancy dock reaches into the pond instead).
const STAGE := {
	"free-fall": 0.8, "projectile": 0.95, "collision": 1.15, "incline-friction": 1.05,
	"friction": 1.15, "spring": 0.8, "rotation": 1.1, "pulley": 0.95, "constraints": 0.95,
	"buoyancy": 0.0, "orbit": 0.85,
}
const DEFAULT_STAGE := 0.9


static func stage_radius(id: String) -> float:
	return STAGE.get(id, DEFAULT_STAGE)


## Adds the landmark of lab `id` at `xf` (origin = the stage top; for the drum, the pond's water
## with its dock along +x) and returns its height above xf (where the name label goes). Unknown ids get a ball on a post.
static func add(b: ArtMeshBuilder, id: String, xf: Transform3D) -> float:
	b.ao_min = 0.8
	b.ao_height = 0.3
	match id:
		"free-fall":
			return _free_fall(b, xf)
		"projectile":
			return _projectile(b, xf)
		"collision":
			return _collision(b, xf)
		"incline-friction":
			return _incline(b, xf)
		"friction":
			return _friction(b, xf)
		"spring":
			return _spring(b, xf)
		"rotation":
			return _seesaw(b, xf)
		"pulley":
			return _pulley(b, xf)
		"constraints":
			return _pendulum(b, xf)
		"buoyancy":
			return _dock(b, xf)
		"orbit":
			return _star(b, xf)
	_rod(b, xf, Vector3.ZERO, Vector3(0.0, 1.0, 0.0), 0.08, ArtPalette.BLUE)
	_ball(b, xf, Vector3(0.0, 1.15, 0.0), 0.2, ArtPalette.WHITE)
	return 1.35


## A drop tower: a striped blue tower, a white ledge at the top and the red ball waiting on it.
static func _free_fall(b: ArtMeshBuilder, xf: Transform3D) -> float:
	_box(b, xf, Vector3(0.0, 1.0, 0.0), Vector3(0.42, 2.0, 0.42), ArtPalette.BLUE, ArtPalette.BLUE)
	for y in [0.55, 1.25]:
		_box(b, xf, Vector3(0.0, y, 0.0), Vector3(0.46, 0.14, 0.46), ArtPalette.WHITE)
	_box(b, xf, Vector3(0.18, 2.05, 0.0), Vector3(0.85, 0.1, 0.5), ArtPalette.ROCK, ArtPalette.WHITE)
	_ball(b, xf, Vector3(0.38, 2.32, 0.0), 0.22, ArtPalette.RED)
	return 2.55


## A slingshot with its ball and, ahead of it, a red and white target.
static func _projectile(b: ArtMeshBuilder, xf: Transform3D) -> float:
	var base := Vector3(-0.45, 0.0, 0.1)
	var fork := base + Vector3(0.0, 0.5, 0.0)
	_rod(b, xf, base, fork, 0.07, ArtPalette.TRUNK)
	var left := fork + Vector3(-0.05, 0.38, -0.2)
	var right := fork + Vector3(-0.05, 0.38, 0.2)
	_rod(b, xf, fork, left, 0.055, ArtPalette.TRUNK)
	_rod(b, xf, fork, right, 0.055, ArtPalette.TRUNK)
	var pouch := fork + Vector3(-0.28, 0.3, 0.0)
	_rod(b, xf, left, pouch, 0.025, ArtPalette.RED)
	_rod(b, xf, right, pouch, 0.025, ArtPalette.RED)
	_ball(b, xf, pouch, 0.15, ArtPalette.ORANGE)
	# The target faces the slingshot and leans back to the sky (the map looks down on it).
	var at := Vector3(0.5, 0.0, -0.1)
	_rod(b, xf, at, at + Vector3(0.05, 0.65, 0.0), 0.05, ArtPalette.TRUNK)
	var face := Basis(Vector3.BACK, deg_to_rad(40.0))   # its axis (local y) towards -x, mostly up
	var center := at + Vector3(0.0, 0.8, 0.0)
	var rings := [[0.42, ArtPalette.RED], [0.29, ArtPalette.WHITE], [0.15, ArtPalette.RED]]
	for i in rings.size():
		var offset := face * Vector3(0.0, 0.03 * i, 0.0)
		b.add_cylinder(xf * Transform3D(face, center + offset), rings[i][0], rings[i][0], 0.05, 14, rings[i][1])
	return 1.3


## A collision track with two balls rolling at each other.
static func _collision(b: ArtMeshBuilder, xf: Transform3D) -> float:
	_box(b, xf, Vector3(0.0, 0.06, 0.0), Vector3(2.0, 0.12, 0.42), ArtPalette.BLUE_DARK, ArtPalette.WHITE)
	for z in [-0.17, 0.17]:
		_box(b, xf, Vector3(0.0, 0.15, z), Vector3(2.0, 0.06, 0.06), ArtPalette.BLUE)
	_ball(b, xf, Vector3(-0.5, 0.34, 0.0), 0.22, ArtPalette.ORANGE)
	_ball(b, xf, Vector3(0.42, 0.34, 0.0), 0.22, ArtPalette.PURPLE)
	_ball(b, xf, Vector3(-0.03, 0.42, 0.0), 0.07, ArtPalette.YELLOW)   # a little spark where they meet
	return 0.7


## A yellow ramp with a crate on its slope.
static func _incline(b: ArtMeshBuilder, xf: Transform3D) -> float:
	var half := Vector2(0.85, 0.36)
	var top := 0.8
	var a := atan2(top, 2.0 * half.x)
	_wedge(b, xf, half, top, ArtPalette.YELLOW, ArtPalette.YELLOW_TOP)
	var normal := Vector3(-sin(a), cos(a), 0.0)
	var center := Vector3(0.0, top * 0.5, 0.0) + normal * 0.2
	b.add_rounded_box(xf * Transform3D(Basis(Vector3.BACK, a), center), Vector3(0.38, 0.38, 0.38), 0.04, 1, ArtPalette.CRATE, ArtPalette.CRATE_TOP)
	return 1.0


## A crate on a floor strip with a red arrow pushing it.
static func _friction(b: ArtMeshBuilder, xf: Transform3D) -> float:
	_box(b, xf, Vector3(0.0, 0.04, 0.0), Vector3(2.0, 0.08, 0.6), ArtPalette.BLUE, ArtPalette.WHITE)
	_box(b, xf, Vector3(0.1, 0.33, 0.0), Vector3(0.5, 0.5, 0.5), ArtPalette.CRATE, ArtPalette.CRATE_TOP)
	_box(b, xf, Vector3(0.1, 0.585, 0.0), Vector3(0.12, 0.02, 0.52), ArtPalette.TAPE)
	_rod(b, xf, Vector3(-0.85, 0.33, 0.0), Vector3(-0.32, 0.33, 0.0), 0.06, ArtPalette.RED)
	var tip := Basis(Vector3.BACK, -PI * 0.5)   # cone axis (y) along +x
	b.add_cylinder(xf * Transform3D(tip, Vector3(-0.36, 0.33, 0.0)), 0.15, 0.0, 0.2, 6, ArtPalette.RED)
	return 0.75


## A coiled spring on a base with a purple block on top.
static func _spring(b: ArtMeshBuilder, xf: Transform3D) -> float:
	_box(b, xf, Vector3(0.0, 0.06, 0.0), Vector3(0.75, 0.12, 0.75), ArtPalette.BLUE_DARK, ArtPalette.BLUE)
	var turns := 5
	var steps := 9
	var bottom := 0.14
	var height := 0.8
	var radius := 0.24
	var last := Vector3(radius, bottom, 0.0)
	for k in range(1, turns * steps + 1):
		var t := float(k) / (turns * steps)
		var angle := TAU * turns * t
		var p := Vector3(radius * cos(angle), bottom + height * t, radius * sin(angle))
		_rod(b, xf, last, p, 0.04, ArtPalette.WHITE, 4)
		last = p
	_box(b, xf, Vector3(0.0, bottom + height + 0.13, 0.0), Vector3(0.58, 0.26, 0.58), ArtPalette.PURPLE, ArtPalette.PURPLE_TOP)
	return 1.25


## A seesaw: a yellow pivot, a tilted red plank and a block on its low end.
static func _seesaw(b: ArtMeshBuilder, xf: Transform3D) -> float:
	b.add_cylinder(xf * Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3.ZERO), 0.32, 0.05, 0.45, 4, ArtPalette.YELLOW)
	var tilt := Basis(Vector3.BACK, deg_to_rad(-12.0))
	var plank := Vector3(0.0, 0.5, 0.0)
	b.add_rounded_box(xf * Transform3D(tilt, plank), Vector3(2.0, 0.1, 0.4), 0.03, 1, ArtPalette.RED, ArtPalette.RED_TOP)
	var low := plank + tilt * Vector3(0.74, 0.2, 0.0)
	b.add_rounded_box(xf * Transform3D(tilt, low), Vector3(0.32, 0.3, 0.32), 0.03, 1, ArtPalette.BLUE, ArtPalette.BLUE)
	var high := plank + tilt * Vector3(-0.78, 0.12, 0.0)
	b.add_rounded_box(xf * Transform3D(tilt, high), Vector3(0.2, 0.14, 0.2), 0.03, 1, ArtPalette.YELLOW, ArtPalette.YELLOW_TOP)
	return 1.0


## A pulley frame: two posts and a beam, the white wheel, its rope and the red load.
static func _pulley(b: ArtMeshBuilder, xf: Transform3D) -> float:
	for x in [-0.55, 0.55]:
		_box(b, xf, Vector3(x, 0.8, 0.0), Vector3(0.14, 1.6, 0.14), ArtPalette.BLUE_DARK)
	_box(b, xf, Vector3(0.0, 1.62, 0.0), Vector3(1.32, 0.13, 0.18), ArtPalette.BLUE_DARK, ArtPalette.BLUE)
	_rod(b, xf, Vector3(0.0, 1.56, 0.0), Vector3(0.0, 1.4, 0.0), 0.03, ArtPalette.INK)
	var wheel := Basis(Vector3.RIGHT, PI * 0.5)   # axis along z
	b.add_cylinder(xf * Transform3D(wheel, Vector3(0.0, 1.34, -0.06)), 0.2, 0.2, 0.12, 12, ArtPalette.WHITE)
	b.add_cylinder(xf * Transform3D(wheel, Vector3(0.0, 1.34, -0.08)), 0.07, 0.07, 0.16, 6, ArtPalette.RED)
	_rod(b, xf, Vector3(0.2, 1.34, 0.0), Vector3(0.2, 0.62, 0.0), 0.025, ArtPalette.INK)
	_box(b, xf, Vector3(0.2, 0.45, 0.0), Vector3(0.34, 0.34, 0.34), ArtPalette.RED, ArtPalette.RED_TOP)
	_rod(b, xf, Vector3(-0.2, 1.34, 0.0), Vector3(-0.2, 0.9, 0.0), 0.025, ArtPalette.INK)
	_ball(b, xf, Vector3(-0.2, 0.86, 0.0), 0.08, ArtPalette.YELLOW)
	return 1.75


## A pendulum: a post with an arm and a yellow bob swung out on its rod.
static func _pendulum(b: ArtMeshBuilder, xf: Transform3D) -> float:
	_box(b, xf, Vector3(0.0, 0.05, 0.0), Vector3(0.6, 0.1, 0.5), ArtPalette.BLUE_DARK, ArtPalette.BLUE)
	_box(b, xf, Vector3(-0.15, 0.85, 0.0), Vector3(0.14, 1.6, 0.14), ArtPalette.BLUE_DARK)
	_box(b, xf, Vector3(0.15, 1.6, 0.0), Vector3(0.75, 0.12, 0.14), ArtPalette.BLUE_DARK, ArtPalette.BLUE)
	var pivot := Vector3(0.42, 1.54, 0.0)
	var bob := pivot + Vector3(sin(deg_to_rad(28.0)), -cos(deg_to_rad(28.0)), 0.0) * 0.95
	_rod(b, xf, pivot, bob, 0.025, ArtPalette.INK)
	_ball(b, xf, bob, 0.22, ArtPalette.YELLOW)
	return 1.75


## A red and white drum floating in the pond (origin = the water) with a ripple ring, and a
## little dock from it to the shore (+x).
static func _dock(b: ArtMeshBuilder, xf: Transform3D) -> float:
	_box(b, xf, Vector3(1.05, 0.08, 0.0), Vector3(1.5, 0.08, 0.7), ArtPalette.CRATE, ArtPalette.CRATE_TOP)
	for x in [0.6, 1.1, 1.6]:
		_box(b, xf, Vector3(x, 0.125, 0.0), Vector3(0.05, 0.01, 0.7), ArtPalette.TAPE)
	for x in [0.4, 1.7]:
		for z in [-0.29, 0.29]:
			_rod(b, xf, Vector3(x, -0.2, z), Vector3(x, 0.16, z), 0.05, ArtPalette.TRUNK)
	b.add_cylinder(xf * Transform3D(Basis(), Vector3(0.0, 0.005, 0.0)), 0.55, 0.55, 0.02, 16, ArtPalette.WATER_TOP)
	b.add_cylinder(xf * Transform3D(Basis(), Vector3(0.0, -0.15, 0.0)), 0.32, 0.32, 0.6, 12, ArtPalette.RED, true, ArtPalette.RED_TOP)
	b.add_cylinder(xf * Transform3D(Basis(), Vector3(0.0, 0.08, 0.0)), 0.33, 0.33, 0.13, 12, ArtPalette.WHITE, false)
	return 0.5


## The lookout's tower with a star on top and a planet going round it.
static func _star(b: ArtMeshBuilder, xf: Transform3D) -> float:
	b.add_cylinder(xf, 0.52, 0.42, 1.4, 8, ArtPalette.ROCK, true, ArtPalette.WHITE)
	b.add_cylinder(xf * Transform3D(Basis(), Vector3(0.0, 1.4, 0.0)), 0.6, 0.6, 0.12, 8, ArtPalette.WHITE)
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		_box(b, xf, Vector3(0.52 * cos(a), 1.59, 0.52 * sin(a)), Vector3(0.15, 0.15, 0.15), ArtPalette.WHITE)
	var sun := Vector3(0.0, 2.1, 0.0)
	_ball(b, xf, sun, 0.36, ArtPalette.YELLOW)
	for i in 6:   # star points around the ball, in the plane that faces the map camera
		var a := TAU * i / 6.0
		var dir := Vector3(cos(a), sin(a) * 0.8, sin(a) * 0.6).normalized()
		b.add_cylinder(xf * Transform3D(_along(dir), sun + dir * 0.26), 0.13, 0.0, 0.3, 4, ArtPalette.YELLOW)
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(20.0))
	var ring := 0.72
	var last := sun + tilt * Vector3(ring, 0.0, 0.0)
	for k in range(1, 19):
		var a := TAU * k / 18.0
		var p := sun + tilt * Vector3(ring * cos(a), 0.0, ring * sin(a))
		_rod(b, xf, last, p, 0.02, ArtPalette.WHITE, 4)
		last = p
	_ball(b, xf, sun + tilt * Vector3(ring * cos(2.2), 0.0, ring * sin(2.2)), 0.14, ArtPalette.BLUE)
	return 2.55


# --- helpers ---------------------------------------------------------------------------------

static func _box(b: ArtMeshBuilder, xf: Transform3D, at: Vector3, size: Vector3, color: Color, top: Variant = null) -> void:
	b.add_rounded_box(xf * Transform3D(Basis(), at), size, 0.03, 1, color, top)


static func _ball(b: ArtMeshBuilder, xf: Transform3D, at: Vector3, radius: float, color: Color) -> void:
	b.add_sphere(xf * Transform3D(Basis(), at), radius, 4, 7, color)


## A cylinder from `from` to `to` (local to xf).
static func _rod(b: ArtMeshBuilder, xf: Transform3D, from: Vector3, to: Vector3, radius: float, color: Color, sides := 6) -> void:
	var d := to - from
	if d.length() < 1e-5:
		return
	b.add_cylinder(xf * Transform3D(_along(d.normalized()), from), radius, radius, d.length(), sides, color)


## A basis whose y axis is `dir` (unit).
static func _along(dir: Vector3) -> Basis:
	var x := dir.cross(Vector3.BACK if absf(dir.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, dir, x.cross(dir))


## A ramp: a wedge over [-half.x, half.x] x [-half.y, half.y] rising to `top` at +x.
static func _wedge(b: ArtMeshBuilder, xf: Transform3D, half: Vector2, top: float, color: Color, slope_color: Color) -> void:
	var p := func(x: float, y: float, z: float) -> Vector3: return xf * Vector3(x, y, z)
	var a0: Vector3 = p.call(-half.x, 0.0, -half.y)
	var a1: Vector3 = p.call(-half.x, 0.0, half.y)
	var b0: Vector3 = p.call(half.x, 0.0, -half.y)
	var b1: Vector3 = p.call(half.x, 0.0, half.y)
	var c0: Vector3 = p.call(half.x, top, -half.y)
	var c1: Vector3 = p.call(half.x, top, half.y)
	var up := xf.basis * Vector3(-top, 2.0 * half.x, 0.0).normalized()
	var back := xf.basis * Vector3.RIGHT
	var side := xf.basis * Vector3.BACK
	var sc := [slope_color, slope_color, slope_color]
	var cc := [color, color, color]
	b.add_triangle([a0, a1, c1], sc, up)
	b.add_triangle([a0, c1, c0], sc, up)
	b.add_triangle([b0, b1, c1], cc, back)
	b.add_triangle([b0, c1, c0], cc, back)
	b.add_triangle([a1, b1, c1], cc, side)
	b.add_triangle([a0, b0, c0], cc, -side)
