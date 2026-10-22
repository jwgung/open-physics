extends SceneTree
# Order of _physics_process, the Jolt step and _integrate_forces, from the body position.
# Does a velocity set in _integrate_forces move the body in the same step (pre-step) or after (post-step)?
class Probe extends RigidBody3D:
	var mode := ""
	var rows := []
	var step := 0
	func _physics_process(_d):
		step += 1
		rows.append("pp%d x=%.4f" % [step, global_position.x])
	func _integrate_forces(s):
		rows.append("if%d x=%.4f" % [step, s.transform.origin.x])
		if mode == "if_vel" and step == 3: s.linear_velocity.x = 6.0
func _initialize(): _run.call_deferred()
func _run():
	var b := Probe.new(); b.mode = "if_vel"; b.gravity_scale = 0; b.can_sleep = false
	var c := CollisionShape3D.new(); c.shape = SphereShape3D.new(); b.add_child(c); root.add_child(b)
	for i in 6: await physics_frame
	print(b.rows)
	quit()
