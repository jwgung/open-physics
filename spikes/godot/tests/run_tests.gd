## Headless S3 checks (benchmark-spec.md section 4) + TS/GDScript formula parity.
## Run: godot --headless --path spikes/godot --fixed-fps 60 -s res://tests/run_tests.gd
## Times are engine fixed steps (60 Hz), independent of rendering FPS.
extends SceneTree

const VECTORS_PATH := "res://tests/s3_vectors.json"
const STEP_HZ := 60

var _failures := 0
var _lab: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("== parity: GDScript PhysicsLaws vs TS core vectors ==")
	_check_parity()
	print("== S3 physics (Jolt + correction layer, %d Hz fixed step) ==" % STEP_HZ)
	_lab = load("res://scenes/s3_incline.tscn").instantiate()
	_lab.headless_ui = true
	if OS.get_cmdline_user_args().has("--no-leapfrog"):
		_lab.corrector.leapfrog_start = false
	root.add_child(_lab)
	await process_frame
	await _check_hold(26.0, 3.0, "26.0deg holds (3 s)")
	await _check_slide_starts(27.0)
	await _check_slide_35()
	await _check_hold(20.0, 10.0, "20.0deg drift over 10 s")
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _expect(ok: bool, label: String, detail: String) -> void:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		_failures += 1


func _within(value: float, expected: float, rel: float) -> bool:
	return absf(value - expected) <= absf(expected) * rel


func _check_parity() -> void:
	var vectors: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(VECTORS_PATH))
	var g: float = vectors.g
	var mu_s: float = vectors.mu_s
	var mu_k: float = vectors.mu_k
	var mass: float = vectors.mass
	var dt: float = vectors.dt
	var worst := 0.0
	for case in vectors.cases:
		var theta := deg_to_rad(case.theta_deg)
		var force := PhysicsLaws.corrected_tangential_force(
			PhysicsLaws.incline_tangential_gravity(mass, g, theta), case.speed,
			PhysicsLaws.incline_normal_load(mass, g, theta), mu_s, mu_k, mass, dt)
		worst = maxf(worst, absf(force / mass - float(case.tangential_accel)))
	_expect(worst < 1e-9, "friction modifier parity", "%d cases, max |diff| = %s m/s^2" % [vectors.cases.size(), str(worst)])
	var critical := rad_to_deg(PhysicsLaws.critical_angle(mu_s))
	_expect(absf(critical - float(vectors.critical_angle_deg)) < 1e-9, "critical angle", "%.3f deg" % critical)
	var a35 := PhysicsLaws.incline_acceleration(g, deg_to_rad(35.0), mu_s, mu_k)
	_expect(absf(a35 - float(vectors.accel_35)) < 1e-9, "a(35deg) formula", "%.4f m/s^2 (TS %.4f)" % [a35, vectors.accel_35])
	for row in vectors.displacement_35:
		var s := PhysicsLaws.constant_acceleration_displacement(0.0, a35, row.t)
		_expect(absf(s - float(row.s)) < 1e-9, "s(%ds) formula" % row.t, "%.4f m" % s)


func _run_steps(angle: float, steps: int) -> InclineFrictionCorrector:
	_lab.set_angle(angle)
	await physics_frame
	_lab.release()
	while _lab.corrector.steps <= steps:
		await physics_frame
	return _lab.corrector


func _check_hold(angle: float, seconds: float, label: String) -> void:
	var c: InclineFrictionCorrector = await _run_steps(angle, int(seconds * STEP_HZ))
	_expect(c.max_offset <= 0.001 and c.status == "holding", label,
		"max displacement %.6f mm, status %s" % [c.max_offset * 1000.0, c.status])


func _check_slide_starts(angle: float) -> void:
	var c: InclineFrictionCorrector = await _run_steps(angle, STEP_HZ)
	var start_step := -1
	for k in c.samples.size():
		if c.samples[k] > 0.001:
			start_step = k
			break
	var ok := start_step >= 0 and start_step <= STEP_HZ
	var a := PhysicsLaws.incline_acceleration(9.81, deg_to_rad(angle), 0.5, 0.4)
	_expect(ok, "%.1fdeg slides within 1 s" % angle,
		"moved >1 mm at step %d (%.3f s), s(1s) = %.4f m (formula %.4f)" % [
			start_step, start_step / float(STEP_HZ), c.samples[STEP_HZ],
			PhysicsLaws.constant_acceleration_displacement(0.0, a, 1.0)])


func _check_slide_35() -> void:
	var c: InclineFrictionCorrector = await _run_steps(35.0, 2 * STEP_HZ)
	var a := PhysicsLaws.incline_acceleration(9.81, deg_to_rad(35.0), 0.5, 0.4)
	var s1 := c.samples[STEP_HZ]
	var s2 := c.samples[2 * STEP_HZ]
	var measured_a := 2.0 * s2 / 4.0
	var velocity_a := c.velocities[2 * STEP_HZ] - c.velocities[STEP_HZ]
	_expect(_within(measured_a, 2.412, 0.01), "a(35deg) measured 2s/t^2",
		"%.4f m/s^2 vs 2.412 (%.3f%%)" % [measured_a, (measured_a / 2.412 - 1.0) * 100.0])
	_expect(_within(velocity_a, 2.412, 0.01), "a(35deg) measured dv/dt (1-2 s)",
		"%.4f m/s^2 vs 2.412 (%.3f%%)" % [velocity_a, (velocity_a / 2.412 - 1.0) * 100.0])
	_expect(_within(s1, 1.206, 0.01), "s(1s) at 35deg", "%.4f m vs 1.206 (%.3f%%)" % [s1, (s1 / 1.206 - 1.0) * 100.0])
	_expect(_within(s2, 4.825, 0.01), "s(2s) at 35deg", "%.4f m vs 4.825 (%.3f%%)" % [s2, (s2 / 4.825 - 1.0) * 100.0])
	_expect(absf(a - 2.412) < 0.0005, "a(35deg) displayed formula", "%.4f m/s^2" % a)
