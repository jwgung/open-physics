extends SceneTree
# Pendulum with PinJoint3D (Jolt point constraint): period, length drift, amplitude loss over 30 s.
const L := 2.0
func _bob(pos: Vector3) -> RigidBody3D:
	var b := RigidBody3D.new(); b.mass = 1.0; b.can_sleep = false
	var c := CollisionShape3D.new(); var s := SphereShape3D.new(); s.radius = 0.1; c.shape = s; b.add_child(c)
	b.position = pos; root.add_child(b); return b
func _anchor(pos: Vector3) -> StaticBody3D:
	var a := StaticBody3D.new(); a.position = pos; a.collision_layer = 0; root.add_child(a); return a
func _initialize(): _run.call_deferred()
func _run():
	var theta := deg_to_rad(10.0)
	var a := _anchor(Vector3(0, 5, 0))
	var bob := _bob(Vector3(L * sin(theta), 5 - L * cos(theta), 0))
	var j := PinJoint3D.new(); j.position = Vector3(0, 5, 0); root.add_child(j)
	j.node_a = a.get_path(); j.node_b = bob.get_path()
	await physics_frame
	var crossings := []; var prev_x := bob.global_position.x; var max_len_err := 0.0
	var first_amp := 0.0; var last_amp := 0.0
	for i in 60 * 30:
		await physics_frame
		var t := (i + 1) / 60.0
		var x := bob.global_position.x
		if prev_x < 0.0 and x >= 0.0: crossings.append(t)
		prev_x = x
		max_len_err = maxf(max_len_err, absf(bob.global_position.distance_to(Vector3(0, 5, 0)) - L))
		var ang := rad_to_deg(atan2(absf(x), 5.0 - bob.global_position.y))
		if t <= 3.0: first_amp = maxf(first_amp, ang)
		if t >= 27.0: last_amp = maxf(last_amp, ang)
	var T_meas: float = (crossings[-1] - crossings[0]) / (crossings.size() - 1)
	var T_small := TAU * sqrt(L / 9.81)
	# exact large-angle period series
	var k := sin(theta / 2.0)
	var T_exact := T_small * (1.0 + k*k/4.0 + 9.0*pow(k,4)/64.0)
	print("PinJoint pendulum L=2 theta0=10deg: T measured %.4f s, small-angle formula %.4f, finite-amp %.4f, rel err vs finite %.3f%%, max |len-L| %.5f m, amplitude first 3 s %.2f deg, last 3 s %.2f deg" % [T_meas, T_small, T_exact, (T_meas/T_exact-1)*100, max_len_err, first_amp, last_amp])
	quit()
