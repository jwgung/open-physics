extends SceneTree
# Generic6DOFJoint3D linear spring (k = 5, m = 1): period and energy.
func _initialize(): _run.call_deferred()
func _run():
	var a := StaticBody3D.new(); root.add_child(a)
	var ball := RigidBody3D.new(); ball.mass = 1; ball.gravity_scale = 0; ball.can_sleep = false
	var c := CollisionShape3D.new(); c.shape = SphereShape3D.new(); ball.add_child(c); ball.position = Vector3(0.5,0,0); root.add_child(ball)
	ball.collision_layer = 2; ball.collision_mask = 0
	var g6 := Generic6DOFJoint3D.new(); root.add_child(g6)
	g6.set("linear_limit_x/enabled", true); g6.set("linear_limit_x/upper_distance", 5.0); g6.set("linear_limit_x/lower_distance", -5.0)
	g6.set("linear_spring_x/enabled", true); g6.set("linear_spring_x/stiffness", 5.0); g6.set("linear_spring_x/damping", 0.0)
	g6.set("linear_spring_x/equilibrium_point", -0.5); g6.node_a = a.get_path(); g6.node_b = ball.get_path()
	var cross := []; var prev := 0.5; var emin := 1e9; var emax := -1e9
	for i in 60*20:
		await physics_frame
		var x := ball.global_position.x - 0.0
		if prev < 0 and x >= 0: cross.append((i+1)/60.0)
		prev = x
		var e := 0.5*ball.linear_velocity.length_squared() + 2.5*x*x
		emin = minf(emin, e); emax = maxf(emax, e)
	print("crossings ", cross, " formula T ", TAU/sqrt(5.0), " E ", emin, "..", emax, " formula 0.625")
	quit()
