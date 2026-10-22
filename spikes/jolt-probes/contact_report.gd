extends SceneTree
class Box extends RigidBody3D:
	var rows := []
	func _integrate_forces(s):
		var imp := Vector3.ZERO
		for i in s.get_contact_count(): imp += s.get_contact_impulse(i)
		rows.append([s.get_contact_count(), imp, s.get_contact_local_normal(0) if s.get_contact_count() > 0 else Vector3.ZERO])
func _initialize(): _run.call_deferred()
func _run():
	var floor := StaticBody3D.new(); var fc := CollisionShape3D.new(); var fs := BoxShape3D.new(); fs.size = Vector3(10, 1, 10); fc.shape = fs; floor.add_child(fc); floor.position.y = -0.5; root.add_child(floor)
	var b := Box.new(); b.mass = 2.0; b.contact_monitor = true; b.max_contacts_reported = 8; b.can_sleep = false
	var c := CollisionShape3D.new(); var s := BoxShape3D.new(); s.size = Vector3.ONE * 0.4; c.shape = s; b.add_child(c); b.position.y = 0.2; root.add_child(b)
	var entered := []
	b.body_entered.connect(func(n): entered.append(Engine.get_physics_frames()))
	for i in 30: await physics_frame
	print("contacts per step / summed impulse (m g dt = %.5f): " % (2*9.81/60.0), b.rows.slice(20, 24))
	print("body_entered frames: ", entered)
	quit()
