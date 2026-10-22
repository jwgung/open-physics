extends SceneTree
# Head-on sphere collision in Jolt: engine result vs postCollisionVelocity1D with Godot-Jolt's
# combine rule e = min(bounceA + bounceB, 1) and with the TS rule e = min(eA, eB).
# Below 1 m/s closing speed (bounce_velocity_threshold) Jolt uses e = 0.
func _ball(m: float, r: float, x: float, v: float, bounce: float) -> RigidBody3D:
	var b := RigidBody3D.new(); b.mass = m; b.gravity_scale = 0; b.can_sleep = false
	var mat := PhysicsMaterial.new(); mat.friction = 0; mat.bounce = bounce; b.physics_material_override = mat
	var c := CollisionShape3D.new(); var s := SphereShape3D.new(); s.radius = r; c.shape = s; b.add_child(c)
	b.position = Vector3(x, 0, 0); b.linear_velocity = Vector3(v, 0, 0)
	root.add_child(b); return b
func _formula(m1, u1, m2, u2, e):
	return [((m1 - e*m2)*u1 + (1+e)*m2*u2)/(m1+m2), ((m2 - e*m1)*u2 + (1+e)*m1*u1)/(m1+m2)]
func _case(m1, u1, m2, u2, e1, e2):
	var a := _ball(m1, 0.67, -3, u1, e1); var b := _ball(m2, 0.83, 3, u2, e2)
	for i in 400: await physics_frame
	var e: float = minf(e1 + e2, 1.0)
	var f = _formula(m1, u1, m2, u2, e); var fmin = _formula(m1, u1, m2, u2, min(e1,e2))
	print("m %.1f/%.1f u %.2f/%.2f bounce %.2f/%.2f -> jolt %.5f / %.5f | formula(e=min(a+b,1)) %.5f / %.5f | formula(e=min(a,b), TS) %.5f / %.5f | p before %.4f after %.4f" % [m1, m2, u1, u2, e1, e2, a.linear_velocity.x, b.linear_velocity.x, f[0], f[1], fmin[0], fmin[1], m1*u1+m2*u2, m1*a.linear_velocity.x+m2*b.linear_velocity.x])
	a.queue_free(); b.queue_free(); await physics_frame
func _initialize(): _run.call_deferred()
func _run():
	await _case(1.0, 3.4, 2.0, -1.7, 0.88, 0.88)
	await _case(1.0, 3.4, 2.0, -1.7, 0.5, 0.5)
	await _case(1.0, 3.4, 2.0, -1.7, 0.44, 0.44)
	await _case(1.0, 3.4, 2.0, -1.7, 0.88, 0.0)
	await _case(1.0, 3.4, 2.0, -1.7, 0.3, 0.0)
	await _case(1.0, 0.8, 2.0, -0.3, 0.88, 0.0)
	await _case(1.0, 0.5, 2.0, -0.2, 0.88, 0.0)
	quit()
