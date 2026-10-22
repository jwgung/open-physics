## A surface objects are dragged on (Task 2b manipulation plane): the floor, an incline's top face.
## The experiment builds it (manipulation_surface) from its geometry; the shell's Manipulator uses
## it to turn a finger ray into a position on the surface. Plane coordinates: `frame` is a world
## transform whose origin lies on the surface, basis.y is the surface normal and basis.x / basis.z
## span the surface. A position on the surface is a Vector2 (frame x, frame z).
## `region_min` / `region_max` bound where an object's centre may be placed (plane coordinates).
## A region with no extent along z (region_min.y == region_max.y) is a line: objects move along
## frame x only (the incline's start position).
## `snap` is the grid step along frame x / z, measured from the frame origin (0 = no snap).
class_name ManipSurface
extends RefCounted

## A ray closer to the plane than this (|dir . normal| = sin of the angle between them) does not
## move the object: the intersection would race off towards the horizon (grazing view).
const GRAZING := 0.12
## Rays almost parallel to a line (|dir . axis| above this) do not move the object along it.
const LINE_PARALLEL := 0.985

var frame := Transform3D.IDENTITY
var region_min := Vector2.ZERO
var region_max := Vector2.ZERO
var snap := Vector2.ZERO
## Collision objects that may touch a placed object without blocking it (the surface's own body).
var exclude: Array[RID] = []


func _init(surface_frame := Transform3D.IDENTITY, min_point := Vector2.ZERO, max_point := Vector2.ZERO, grid := Vector2.ZERO) -> void:
	frame = surface_frame.orthonormalized()
	region_min = min_point
	region_max = max_point
	snap = grid


func normal() -> Vector3:
	return frame.basis.y


func is_line() -> bool:
	return is_equal_approx(region_min.y, region_max.y)


## Plane coordinates of a world point (its height above the surface is dropped).
func to_plane(world: Vector3) -> Vector2:
	var local := frame.affine_inverse() * world
	return Vector2(local.x, local.z)


## Height of a world point above the surface (along the normal).
func height_of(world: Vector3) -> float:
	return (frame.affine_inverse() * world).y


## World transform of an object whose centre is at plane point `p`, `above` metres over the
## surface, upright on it (basis = the frame's).
func pose(p: Vector2, above: float) -> Transform3D:
	return Transform3D(frame.basis, frame * Vector3(p.x, above, p.y))


## Where a finger ray meets the surface at `above` metres over it (the plane the object's centre
## moves in), in plane coordinates; null when the ray is too close to parallel (grazing) or points
## away. On a line region this is the point of the line closest to the ray.
func project_ray(origin: Vector3, direction: Vector3, above: float) -> Variant:
	var dir := direction.normalized()
	var base := frame * Vector3(0.0, above, region_min.y)
	if is_line():
		var s: Variant = closest_on_line(base, frame.basis.x, origin, dir)
		return null if s == null else Vector2(s, region_min.y)
	var n := normal()
	var facing := dir.dot(n)
	if absf(facing) < GRAZING:
		return null
	var t := (base - origin).dot(n) / facing
	if t < 0.0:
		return null
	var hit := frame.affine_inverse() * (origin + dir * t)
	return Vector2(hit.x, hit.z)


## Parameter s of the point base + axis * s closest to the ray origin + dir * t (unit vectors);
## null when the ray is nearly parallel to the line or the point is behind the ray origin.
static func closest_on_line(base: Vector3, axis: Vector3, origin: Vector3, dir: Vector3) -> Variant:
	var along := dir.dot(axis)
	if absf(along) > LINE_PARALLEL:
		return null
	var w := base - origin
	var denom := 1.0 - along * along
	var t := (w.dot(dir) - along * w.dot(axis)) / denom
	if t < 0.0:
		return null
	return (along * w.dot(dir) - w.dot(axis)) / denom


## Nearest grid point (per axis; an axis with step 0 is left as is). A line keeps its z.
func snap_point(p: Vector2) -> Vector2:
	var result := p
	if snap.x > 0.0:
		result.x = roundf(p.x / snap.x) * snap.x
	if snap.y > 0.0 and not is_line():
		result.y = roundf(p.y / snap.y) * snap.y
	return result


func contains(p: Vector2) -> bool:
	const EPS := 0.0001
	return p.x >= region_min.x - EPS and p.x <= region_max.x + EPS and p.y >= region_min.y - EPS and p.y <= region_max.y + EPS


## `p` kept within `margin` metres outside the region (a dragged object may leave the region a
## little to show it cannot be placed there, but never flies away).
func clamp_soft(p: Vector2, margin: float) -> Vector2:
	var lo := region_min - Vector2(margin, 0.0 if is_line() else margin)
	var hi := region_max + Vector2(margin, 0.0 if is_line() else margin)
	return p.clamp(lo, hi)


## The grid point nearest to `p` inside the region (the region's own bounds when no grid point fits).
func nearest_inside(p: Vector2) -> Vector2:
	var q := snap_point(p.clamp(region_min, region_max))
	if contains(q):
		return q
	# Rounding went past an edge that is not on the grid: step one cell back inwards.
	for axis in 2:
		if snap[axis] > 0.0:
			if q[axis] > region_max[axis]:
				q[axis] -= snap[axis]
			elif q[axis] < region_min[axis]:
				q[axis] += snap[axis]
	return q.clamp(region_min, region_max)
