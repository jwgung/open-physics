extends SceneTree
# Godot callback order with Jolt: when does a force / impulse / velocity set in _physics_process vs _integrate_forces reach the body?
# Precise timing: record vx in _physics_process each step for each mode.
class Probe extends RigidBody3D:
	var mode := ""
	var vx := []
	var step := 0
	func _physics_process(_d):
		step += 1
		vx.append(snappedf(linear_velocity.x, 0.0001))
		if mode == "pp_force" and step == 3: apply_central_force(Vector3(60, 0, 0))
		if mode == "pp_vel" and step == 3: linear_velocity.x = 1.0
		if mode == "pp_impulse" and step == 3: apply_central_impulse(Vector3(1, 0, 0))
	func _integrate_forces(s):
		if mode == "if_force" and step == 3: s.apply_central_force(Vector3(60, 0, 0))
		if mode == "if_vel" and step == 3: s.linear_velocity.x = 1.0
func _initialize(): _run.call_deferred()
func _run():
	var bs := []
	for m in ["pp_force", "pp_vel", "pp_impulse", "if_force", "if_vel"]:
		var b := Probe.new(); b.mode = m; b.gravity_scale = 0; b.can_sleep = false
		var c := CollisionShape3D.new(); c.shape = SphereShape3D.new(); b.add_child(c)
		b.position = Vector3(bs.size()*5, 0, 0); root.add_child(b); bs.append(b)
	for i in 7: await physics_frame
	for b in bs: print(b.mode, " vx seen in _physics_process steps 1..: ", b.vx)
	quit()
