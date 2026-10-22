extends SceneTree
# custom_integrator = true: does the engine still add gravity? Does a velocity set in
# _integrate_forces still move the body (Jolt integrates the position)?
class Probe extends RigidBody3D:
	var add_half_gravity := false
	var calls := 0
	func _integrate_forces(s):
		calls += 1
		if add_half_gravity:
			s.linear_velocity += s.total_gravity * s.step * 0.5
func _initialize(): _run.call_deferred()
func _run():
	var bodies := []
	for half in [false, true]:
		var b := Probe.new(); b.custom_integrator = true; b.add_half_gravity = half; b.can_sleep = false
		var c := CollisionShape3D.new(); c.shape = SphereShape3D.new(); b.add_child(c)
		b.position = Vector3(bodies.size() * 5.0, 100.0, 0.0); root.add_child(b); bodies.append(b)
	for i in 10: await physics_frame
	for b in bodies:
		print("half gravity %s: %d callbacks, v %.6f (calls * g dt / 2 = %.6f), y moved %.6f m" % [str(b.add_half_gravity), b.calls, b.linear_velocity.y,
			-b.calls * 9.81 / 60.0 * 0.5 if b.add_half_gravity else 0.0, b.global_position.y - 100.0])
	quit()
