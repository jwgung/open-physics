## Formula model of the orbit lab (Phase 1 Task 4d; web preset "orbit"): a small planet (1 kg) launched
## in a level plane around a big star under the web's PointGravityField (fields.ts: a = G M / r^2
## towards the star, G = 1, M = mu), in the plane's (x, z) axes.
## Stepping: velocity Verlet (half kick, drift, half kick) with SUBSTEPS per fixed step (h = dt / 8):
## a circular orbit keeps its radius and its period 2 pi sqrt(r^3 / GM) to about 1e-6, and the energy
## v^2 / 2 - GM / r and angular momentum do not drift. The web's explicit Euler (120 Hz) spirals a
## circular orbit outwards (tools/orbit-lab-vectors.test.ts, "web integrator").
## The run ends when the planet reaches the star's surface plus its own radius (crash: it stops on
## it, the OrbitChallenge collision radius) or FAR from the star (it left the scene).
class_name OrbitModel
extends BodyModel

const SUBSTEPS := 8
## The lab's scene (one place: Orbit takes them from here; a model made without a lab uses them too).
const DEFAULT_MU := 27.0                  # G M (m^3/s^2): 3 m/s circular speed at 3 m
const STAR_RADIUS := 0.9
const PLANET_RADIUS := 0.3
const DEFAULT_CRASH_RADIUS := STAR_RADIUS + PLANET_RADIUS
const DEFAULT_FAR_RADIUS := 12.0
const DEFAULT_PLANE_Y := 2.0

var cx := 0.0                  # star centre (x, z) and the orbit plane's height
var cz := 0.0
var plane_y := DEFAULT_PLANE_Y
var mu := DEFAULT_MU                 # G M (m^3/s^2)
var mass := 1.0
var crash_radius := DEFAULT_CRASH_RADIUS
var far_radius := DEFAULT_FAR_RADIUS
## "", "crash" or "far" once the run ended.
var outcome := ""
## Angle swept around the star since the launch (rad, counter-clockwise seen from above) and the
## time of the first full turn (s; -1 before it).
var swept := 0.0
var first_lap_time := -1.0
var _a := PackedFloat64Array([0.0, 0.0])   # acceleration (x, z) now, rewritten every substep


## The planet `start_radius` east of the star (+x) with the launch velocity (vx0, vz0) (m/s, plane axes).
func reset(start_radius: float, vx0: float, vz0: float) -> void:
	steps = 0
	stopped = false
	outcome = ""
	swept = 0.0
	first_lap_time = -1.0
	x = cx + start_radius
	y = plane_y
	z = cz
	vx = vx0
	vy = 0.0
	vz = vz0
	_acceleration()


func _acceleration() -> void:
	PhysicsLaws.point_gravity_field_acceleration(mu, mass, cx - x, cz - z, _a)


func advance(step_dt: float) -> void:
	var h := step_dt / SUBSTEPS
	for i in SUBSTEPS:
		var before := atan2(-(z - cz), x - cx)
		vx += _a[0] * (h * 0.5)
		vz += _a[1] * (h * 0.5)
		x += vx * h
		z += vz * h
		_acceleration()
		vx += _a[0] * (h * 0.5)
		vz += _a[1] * (h * 0.5)
		var turned := atan2(-(z - cz), x - cx) - before
		if turned > PI:
			turned -= TAU
		elif turned < -PI:
			turned += TAU
		swept += turned
		if first_lap_time < 0.0 and absf(swept) >= TAU:
			# Interpolated within the substep where the swept angle (either way round) passes 2 pi.
			first_lap_time = (steps - 1) * step_dt + (i + (TAU - absf(swept - turned)) / absf(turned)) * h
		var r := radius()
		if r <= crash_radius:
			outcome = "crash"
			x = cx + (x - cx) / r * crash_radius
			z = cz + (z - cz) / r * crash_radius
			vx = 0.0
			vz = 0.0
			stopped = true
			return
		if r >= far_radius:
			outcome = "far"
			stopped = true
			return


func radius() -> float:
	return sqrt((x - cx) * (x - cx) + (z - cz) * (z - cz))


func speed() -> float:
	return sqrt(vx * vx + vz * vz)


## Specific orbital energy v^2 / 2 - GM / r (J/kg): < 0 bound, >= 0 escapes.
func specific_energy() -> float:
	return speed() * speed() * 0.5 - mu / radius()


## Specific angular momentum about the star (m^2/s, + = counter-clockwise seen from above).
func angular_momentum() -> float:
	return -((x - cx) * vz - (z - cz) * vx)


func circular_speed() -> float:
	return PhysicsLaws.circular_orbit_speed(mu, radius(), 1.0)


func escape_speed() -> float:
	return PhysicsLaws.escape_speed(mu, radius(), 1.0)


## Period of a circular orbit at the current radius: 2 pi sqrt(r^3 / GM).
func circular_period() -> float:
	return PhysicsLaws.circular_orbit_period(mu, radius(), 1.0)



## The model's path for a launch from (x0, z0) with (vx0, vz0) around a star at the origin (plane
## axes, GM `mu`) as the conic of Kepler's law, the one OrbitModel's Verlet steps follow (2026-10-29
## user: show kids the way ahead while pulling, the slingshot's preview): r(f) =
## p / (1 + e cos f) with p = h² / GM and the eccentricity vector e = ((v² − GM/r) r − (r·v) v) / GM,
## swept in the direction the planet goes round. A closed ellipse (between `crash` and `far`) is the
## whole loop back to the start; otherwise the path ends where r reaches `crash` (it hits the star)
## or `far` (it leaves the scene), as the model's run ends there. A launch with no turn (h ≈ 0) goes
## along the line through the star. Points every `step` m of path at most (the start first).
static func conic_path(x0: float, z0: float, vx0: float, vz0: float, mu: float, crash: float, far: float,
		step := 0.1) -> PackedVector2Array:
	var r0 := Vector2(x0, z0)
	var v0 := Vector2(vx0, vz0)
	var r := r0.length()
	var h := r0.cross(v0)   # x vz − z vx
	var fine := PackedVector2Array([r0])
	if absf(h) < 1e-6 * r * maxf(v0.length(), 1.0):
		# Along the line through the star: in to the star, or out (bound: to the top and back in).
		var out := r0 / r
		var energy := v0.length_squared() * 0.5 - mu / r
		var top := far if energy >= 0.0 else minf(far, mu / -energy)
		if v0.dot(out) > 0.0:
			fine.append(out * top)
		if top < far or v0.dot(out) <= 0.0:
			fine.append(out * crash)
		return _even(fine, step)
	var e_vec := ((v0.length_squared() - mu / r) * r0 - r0.dot(v0) * v0) / mu
	var e := e_vec.length()
	var p := h * h / mu
	var omega := e_vec.angle() if e > 1e-9 else r0.angle()
	var f := r0.angle() - omega
	var dir := signf(h)
	var closed := e < 1.0 and p / (1.0 - e) < far and p / (1.0 + e) > crash
	var df := TAU / 1440.0
	var swept := 0.0
	var last := r0
	while swept < TAU:
		var next_f := f + dir * df
		var denominator := 1.0 + e * cos(next_f)
		var radius := p / denominator if denominator > 1e-9 else INF
		var at := Vector2.from_angle(omega + next_f) * radius if radius < INF else last
		if not closed and (radius <= crash or radius >= far):
			# The end on the crash or far circle, between the last point and this one.
			var edge := crash if radius <= crash else far
			var lo := 0.0
			var hi := 1.0
			for i in 30:
				var mid := (lo + hi) * 0.5
				var fm := f + dir * df * mid
				var rm := p / maxf(1.0 + e * cos(fm), 1e-9)
				if (rm <= crash) if edge == crash else (rm >= far):
					hi = mid
				else:
					lo = mid
			fine.append(Vector2.from_angle(omega + f + dir * df * hi) * edge)
			return _even(fine, step)
		fine.append(at)
		last = at
		f = next_f
		swept += df
	fine.append(r0)   # the closed loop back to its start
	return _even(fine, step)


## `line`'s points every `step` m along it (its first and last kept).
static func _even(line: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array([line[0]])
	var walked := 0.0
	var next := step
	for i in range(1, line.size()):
		var a := line[i - 1]
		var b := line[i]
		var length := a.distance_to(b)
		while length > 0.0 and next <= walked + length:
			out.append(a.lerp(b, (next - walked) / length))
			next += step
		walked += length
	if out[out.size() - 1].distance_to(line[line.size() - 1]) > 1e-6:
		out.append(line[line.size() - 1])
	return out
