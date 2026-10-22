extends SceneTree
# Gravity-only body: velocity and position after k steps (symplectic Euler check).
var ys := []
var vs := []
var b: RigidBody3D
func _initialize(): _run.call_deferred()
func _physics_process(_d) -> bool:
	return false
func _run():
	b = RigidBody3D.new(); b.can_sleep = false
	var c := CollisionShape3D.new(); c.shape = SphereShape3D.new(); b.add_child(c)
	b.position = Vector3(0, 100, 0); b.freeze = true; root.add_child(b)
	await physics_frame
	b.freeze = false
	for i in 7:
		await physics_frame
		ys.append(b.global_position.y); vs.append(b.linear_velocity.y)
	var dt := 1.0/60; var g := 9.81
	for k in range(ys.size()):
		print("after await %d: v=%.9f y-100=%.9f | v/(g dt)=%.4f (y-100)/(g dt^2)=%.4f" % [k+1, vs[k], ys[k]-100.0, vs[k]/(g*dt), (ys[k]-100.0)/(g*dt*dt)])
	quit()
