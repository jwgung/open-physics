## The conditions read at a glance (2026-10-28 user requests: "공이 크기가 같던가 아니면 무게에 따라
## 달라지게", then the other labs' conditions too), run by run_tests.gd. Visual only, so every check
## pairs what is seen with "the physics did not change":
## 1. mass looks (MassLook): per lab the look's size follows the mass (heavier = bigger, equal masses
##    equal, the cube root of the ratio), the look stands where the body is (the free-fall balls'
##    and the boxes' bottoms on the floor or the beam in flight and at rest, the spring ball about
##    its centre on the rod with the coil to its surface, the pulley's block on the load's top), the
##    collision balls' looks touch exactly at the model's contact and meet the bumpers at the model's
##    wall bounce, the friction bumpers BUMPER_GAP beyond the stopped look; the buoyancy drum keeps
##    its volume's size and shows the mass as the weight's width and the number tag.
## 2. physics unchanged: the collision model (with the looks) against a bare CollisionModel step by
##    step; each other lab's run with its looks against the same run with every look reset to the
##    body's own size (positions every step and the panel's values).
## 3. the picture buttons draw a mass like the lab: size = (m / the lab's heaviest button)^(1/3).
## 4. the other cues follow their controls: the gravity's signpost (PlanetSign) in free fall and the
##    pendulums, the slide's and the push track's surface material (SurfaceSkin); none is a body.
extends RefCounted

const STEP_HZ := 60

var tree: SceneTree
var expect: Callable


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	await check_collision_looks()
	await check_collision_physics()
	await check_free_fall_looks()
	await check_free_fall_physics()
	await check_box_looks("friction")
	await check_box_looks("rotation")
	await check_box_looks("pulley")
	await check_spring_look()
	await check_buoyancy_look()
	check_pick_sizes()
	await check_planet_signs()
	await check_surfaces()


func _lab(id: String) -> Experiment:
	var lab := ExperimentRegistry.instantiate(ExperimentRegistry.find(id))
	tree.root.add_child(lab)
	await tree.process_frame
	await tree.physics_frame
	return lab


func _free(node: Node) -> void:
	node.queue_free()
	await tree.process_frame


func _frames(n: int) -> void:
	for i in n:
		await tree.physics_frame
		await tree.process_frame


## Strictly increasing sizes for increasing masses, and the cube root of each ratio (to 1e-6).
static func _follows(masses: Array, sizes: Array) -> String:
	for i in range(1, masses.size()):
		if not sizes[i] > sizes[i - 1]:
			return "size %s at %s kg not above %s at %s kg" % [sizes[i], masses[i], sizes[i - 1], masses[i - 1]]
		var want := pow(masses[i] / masses[0], 1.0 / 3.0)
		if absf(sizes[i] / sizes[0] - want) > 1e-6:
			return "ratio %s at %s kg, cube root %s" % [sizes[i] / sizes[0], masses[i], want]
	return ""


## World AABB of a mesh instance (its mesh's box through its global transform).
static func _box(mesh: MeshInstance3D) -> AABB:
	return mesh.global_transform * mesh.mesh.get_aabb()


# --- 1, 2. collision ------------------------------------------------------------------------------

func check_collision_looks() -> void:
	var lab: Experiment = await _lab("collision")
	var problems := []
	# Sizes: equal masses equal, heavier bigger, the cube root of the ratio; resting on the floor.
	for pair in [[1.0, 1.0], [2.0, 2.0], [3.0, 0.5], [0.5, 3.0], [1.0, 2.0], [10.0, 0.5], [0.5, 10.0]]:
		lab.set_control("mass_a", pair[0])
		lab.set_control("mass_b", pair[1])
		await _frames(1)
		var look: Vector2 = lab.props.look
		if pair[0] == pair[1] and absf(look.x - look.y) > 1e-9:
			problems.append("%s: equal masses, radii %s" % [pair, look])
		if pair[0] != pair[1] and (look.x > look.y) != (pair[0] > pair[1]):
			problems.append("%s: radii %s" % [pair, look])
		if absf(look.x / look.y - pow(pair[0] / pair[1], 1.0 / 3.0)) > 1e-6:   # (32-bit radii)
			problems.append("%s: ratio %s" % [pair, look.x / look.y])
		for a in [true, false]:
			var spin: MeshInstance3D = lab.props.spin_a if a else lab.props.spin_b
			var r: float = look.x if a else look.y
			var box := _box(spin)
			var centre: Vector3 = lab.props.look_centre(lab.ball_a if a else lab.ball_b, a)
			if absf(box.position.y) > 1e-4 or absf(box.size.y - 2.0 * r) > 0.02 * r or box.get_center().distance_to(centre) > 1e-4:
				problems.append("%s %s: drawn %s, look centre %s radius %s" % [pair, "A" if a else "B", box, centre, r])
	# Contact and walls for the mission's masses and the extremes: at the model's contact step the
	# looks touch (3D distance of the centres = the sum of the radii), the step before they do not;
	# at a wall bounce the look meets its bumper's face.
	var worst_touch := 0.0
	var worst_wall := 0.0
	var hits := 0
	var walls := 0
	for pair in [[1.0, 1.0], [3.0, 1.0], [1.0, 0.5], [10.0, 0.5], [0.5, 10.0]]:
		lab.set_control("mass_a", pair[0])
		lab.set_control("mass_b", pair[1])
		lab.set_control("velocity_a", 6.0)
		lab.set_control("velocity_b", -4.0)
		lab.run_action("release")
		var collisions: int = lab.model.collisions
		for i in 5 * STEP_HZ:
			await tree.physics_frame
			var look: Vector2 = lab.props.look
			var ca: Vector3 = lab.props.look_centre(lab.ball_a, true)
			var cb: Vector3 = lab.props.look_centre(lab.ball_b, false)
			if lab.model.collisions != collisions and lab.model.last_collision_step == lab.model.steps:
				collisions = lab.model.collisions
				if lab.model.last_closing >= 0.3:
					hits += 1
					worst_touch = maxf(worst_touch, absf(ca.distance_to(cb) - (look.x + look.y)))
			for b in [false, true]:
				var x: float = lab.model.xb if b else lab.model.xa
				var r: float = lab.RADIUS_B if b else lab.RADIUS_A
				if absf(absf(x) - (lab.WALL - r)) < 1e-9:
					walls += 1
					var edge: float = x + look.y if b else x - look.x
					var face: float = lab.props.bumper_right.position.x if b else lab.props.bumper_left.position.x
					worst_wall = maxf(worst_wall, absf(edge - face))
		lab.run_action("reset")
	expect.call(problems.is_empty() and hits >= 5 and walls > 0 and worst_touch <= 1e-4 and worst_wall <= 1e-4,
		"mass look (collision): equal masses look equal, heavier bigger by the cube root, on the floor; the looks touch at the model's contact and meet the bumpers at its wall bounce",
		"%s; touch %s m over %d hits, wall %s m over %d steps" % ["; ".join(problems), String.num_scientific(worst_touch), hits, String.num_scientific(worst_wall), walls])
	await _free(lab)


## The lab's model with the looks against a bare CollisionModel (no lab, no visuals) step by step:
## the same positions, velocities and collisions (the looks never reach the model), and the engine
## balls where the model is.
func check_collision_physics() -> void:
	var lab: Experiment = await _lab("collision")
	var worst := 0.0
	var engine := 0.0
	var steps := 0
	for pair in [[1.0, 1.0], [3.0, 0.5], [0.5, 10.0]]:
		lab.set_control("mass_a", pair[0])
		lab.set_control("mass_b", pair[1])
		var bare := CollisionModel.new()
		bare.mass_a = pair[0]
		bare.mass_b = pair[1]
		bare.radius_a = lab.RADIUS_A
		bare.radius_b = lab.RADIUS_B
		bare.restitution_a = lab.model.restitution_a
		bare.restitution_b = lab.model.restitution_b
		bare.wall = lab.WALL
		bare.reset(lab.start_a, lab.start_b, lab.velocity_a, lab.velocity_b)
		lab.run_action("release")
		var dt := 1.0 / float(STEP_HZ)
		for i in 4 * STEP_HZ:
			await tree.physics_frame
			while bare.steps < lab.model.steps:
				bare.step(dt)
			steps += 1
			worst = maxf(worst, maxf(absf(bare.xa - lab.model.xa), absf(bare.xb - lab.model.xb)))
			worst = maxf(worst, maxf(absf(bare.va - lab.model.va), absf(bare.vb - lab.model.vb)))
			worst = maxf(worst, float(absi(bare.collisions - lab.model.collisions)))
			engine = maxf(engine, maxf(absf(lab.ball_a.global_position.x - lab.model.xa), absf(lab.ball_b.global_position.x - lab.model.xb)))
		lab.run_action("reset")
	expect.call(worst == 0.0 and engine <= 1e-5 and steps > 0,
		"mass look (collision): physics unchanged: the model with the looks equals a bare CollisionModel every step (positions, velocities, collisions), the engine balls on it",
		"max diff %s over %d steps, engine %s m" % [String.num_scientific(worst), steps, String.num_scientific(engine)])
	await _free(lab)


# --- free fall ------------------------------------------------------------------------------------

func check_free_fall_looks() -> void:
	var lab: Experiment = await _lab("free-fall")
	var problems := []
	var masses := []
	var radii := []
	for option in ["light", "normal", "heavy"]:
		lab.set_control("mass", option)
		masses.append(lab.mass_of("red"))
		radii.append(lab.look_radius("red"))
	var follows := _follows(masses, radii)
	if follows != "":
		problems.append(follows)
	lab.set_control("mass", "normal")   # red 1 kg = the look's 1 kg (BALL_RADIUS); yellow 0.5 kg
	if not is_equal_approx(lab.look_radius("red"), lab.BALL_RADIUS) or not lab.look_radius("yellow") < lab.look_radius("red"):
		problems.append("red %s (radius %s), yellow %s" % [lab.look_radius("red"), lab.BALL_RADIUS, lab.look_radius("yellow")])
	lab.set_control("mass", "heavy")
	# Every ball's drawn bottom is its body's bottom: waiting, falling, landing and bouncing.
	lab.release()
	var worst := 0.0
	var sizes := 0.0
	for i in 4 * STEP_HZ:
		await tree.physics_frame
		await tree.process_frame
		for id in lab.ORDER:
			var ball: RigidBody3D = lab.balls[id]
			var visual: MeshInstance3D = ball.get_node("Visual")
			var box := _box(visual)
			worst = maxf(worst, absf(box.position.y - (ball.global_position.y - lab.BALL_RADIUS)))
			if not lab.fall_props().juices[id].is_animating():
				sizes = maxf(sizes, absf(box.size.y - 2.0 * lab.look_radius(id)))
	expect.call(problems.is_empty() and worst <= 2e-3 and sizes <= 0.02 * lab.BALL_RADIUS and lab.has_landed("red"),
		"mass look (free fall): the red ball's look follows its mass (cube root; 1 kg = the violet ball), every ball's drawn bottom is its body's bottom in flight, at the landing and at rest",
		"%s; bottom off by %s m, size off by %s m" % ["; ".join(problems), String.num_scientific(worst), String.num_scientific(sizes)])
	await _free(lab)


## A free-fall run with the looks against the same run with every look the body's own size: the
## bodies' positions every step and the panel's values are the same.
func check_free_fall_physics() -> void:
	var runs := []
	for looks in [true, false]:
		var lab: Experiment = await _lab("free-fall")
		lab.set_control("mass", "heavy")
		if not looks:
			for id in lab.ORDER:
				lab.fall_props().set_look(id, lab.BALL_RADIUS)
		lab.release()
		var track := PackedFloat64Array()
		for i in 3 * STEP_HZ:
			await tree.physics_frame
			for id in lab.ORDER:
				var p: Vector3 = lab.balls[id].global_position
				track.append_array([p.x, p.y, p.z])
		runs.append([track, lab.observations()])
		await _free(lab)
	var worst := 0.0
	for i in runs[0][0].size():
		worst = maxf(worst, absf(runs[0][0][i] - runs[1][0][i]))
	expect.call(worst <= 1e-5 and runs[0][1] == runs[1][1],
		"mass look (free fall): physics unchanged: the run with the looks and with the bodies' own sizes have the same positions every step and the same panel",
		"max %s m; panel %s vs %s" % [String.num_scientific(worst), runs[0][1], runs[1][1]])


# --- boxes: friction, lever, pulley ---------------------------------------------------------------

## The control values of a box lab's mass, light to heavy.
static func _box_masses(id: String) -> Array:
	return ["light", "normal", "start", "heavy"] if id == "friction" else [1.0, 5.0, 12.0, 20.0]


func _set_box_mass(lab: Experiment, id: String, value: Variant) -> void:
	lab.set_control("mass", value)
	await _frames(2)


func _box_parts(lab: Experiment, id: String) -> Array:
	match id:
		"friction":
			return [lab.box, lab.box.get_node("Visual"), lab.BOX, lab.props.juice]
		"rotation":
			return [lab.load_body, lab.load_body.get_node("Visual"), lab.LOAD_SIZE, lab.props.juice]
	return [lab.load_body, lab.load_body.get_node("Visual"), lab.LOAD_SIZE, lab.props.juice]


func check_box_looks(id: String) -> void:
	var lab: Experiment = await _lab(id)
	var problems := []
	var masses := []
	var sides := []
	for value in _box_masses(id):
		await _set_box_mass(lab, id, value)
		var parts := _box_parts(lab, id)
		var body: Node3D = parts[0]
		var visual: MeshInstance3D = parts[1]
		var size: float = parts[2]
		var k: float = (parts[3] as ArtJuice).look_scale
		masses.append(float(lab.model.mass))
		sides.append(k * size)
		# The look stands on the body's bottom (along the body's up: the lever's beam turns).
		var bottom := body.global_transform * Vector3(0.0, -size * 0.5, 0.0)
		var drawn_bottom := visual.global_transform * Vector3(0.0, -size * 0.5, 0.0)
		var drawn_side := (visual.global_transform.basis * Vector3.RIGHT).length() * size
		if drawn_bottom.distance_to(bottom) > 1e-4 or absf(drawn_side - k * size) > 1e-4:
			problems.append("%s kg: bottom %s vs body %s, side %s vs %s" % [lab.model.mass, drawn_bottom, bottom, drawn_side, k * size])
		match id:
			"friction":
				# Each bumper face BUMPER_GAP beyond where the formula stops the look.
				var stop: float = lab.TRACK_HALF - lab.BOX * 0.5 - lab.END_PADDING
				var face := (lab.props.bumpers.mesh as Mesh).get_aabb().end.x - 0.3
				if absf(face - (stop + k * size * 0.5 + FrictionProps.BUMPER_GAP)) > 2e-3:
					problems.append("%s kg: bumper face %s" % [lab.model.mass, face])
			"pulley":
				# The moving block stands HOOK_UP - LOAD_SIZE / 2 over the look's top.
				var top := body.global_position.y - size * 0.5 + k * size
				if absf(body.global_position.y + lab.props.hook_up - top - (lab.HOOK_UP - size * 0.5)) > 1e-6 \
						or absf(lab.props.moving_block.position.y - lab.props.hook_up) > 1e-6:
					problems.append("%s kg: hook %s over the top %s" % [lab.model.mass, lab.props.hook_up, top])
	var follows := _follows(masses, sides)
	if follows != "":
		problems.append(follows)
	await _free(lab)
	# Physics unchanged: the same run (the heaviest mass's look against the body's own size).
	var runs := []
	for looks in [true, false]:
		var run: Experiment = await _lab(id)
		await _set_box_mass(run, id, _box_masses(id)[0])
		if not looks:
			(_box_parts(run, id)[3] as ArtJuice).set_look_scale(1.0)
		var track := PackedFloat64Array()
		for i in 2 * STEP_HZ:
			match id:
				"friction":
					run.set_applied_force(30.0)
				"rotation":
					run.set_hand(mini(i, 60) * 5.0)   # the old handle's 5 N cells, one per step
				"pulley":
					run.model.holding = true
					run.model.stroke_cells = mini(i, 60)   # the hand pulls 1 cell per step
			await tree.physics_frame
			var body: Node3D = _box_parts(run, id)[0]
			track.append_array([body.global_position.x, body.global_position.y, body.global_position.z])
		runs.append([track, run.observations()])
		await _free(run)
	var worst := 0.0
	for i in runs[0][0].size():
		worst = maxf(worst, absf(runs[0][0][i] - runs[1][0][i]))
	expect.call(problems.is_empty() and worst <= 1e-5 and runs[0][1] == runs[1][1],
		"mass look (%s): the box looks as heavy as it is (cube root, heavier bigger), standing on its body's bottom; physics unchanged against the body's own size (positions every step, the panel)" % id,
		"%s; run diff %s m; panel %s vs %s" % ["; ".join(problems), String.num_scientific(worst), runs[0][1], runs[1][1]])


# --- spring ---------------------------------------------------------------------------------------

func check_spring_look() -> void:
	var problems := []
	var masses := [0.5, 1.0, 3.0, 5.0]
	var radii := []
	var runs := []
	for looks in [true, false]:
		var lab: Experiment = await _lab("spring")
		# Both runs go through the same conditions; only what is drawn differs.
		for m in masses:
			lab.set_control("mass", m)
			await _frames(1)
			if looks:
				radii.append(lab.look_radius())
			var yarn: MeshInstance3D = lab.ball.get_node("Visual/Yarn")
			var box := _box(yarn)
			# About its centre on the rod; the coil ends at its surface.
			if box.get_center().distance_to(lab.ball.global_position) > 1e-4 or absf(box.size.y - 2.0 * lab.look_radius()) > 0.04 * lab.look_radius():
				problems.append("%s kg: drawn %s" % [m, box])
			var coil_end: float = lab.props.coil.position.x + lab.props.coil.scale.x * lab.props._coil_base
			if absf(coil_end - (lab.ball.global_position.x - lab.look_radius())) > 1e-4:
				problems.append("%s kg: coil ends at %s" % [m, coil_end])
		lab.set_control("mass", 3.0)
		if not looks:
			lab.props.set_look(lab.BALL_RADIUS)
		lab.release()
		var track := PackedFloat64Array()
		for i in 2 * STEP_HZ:
			await tree.physics_frame
			track.append(lab.ball.global_position.x)
		runs.append([track, lab.observations()])
		await _free(lab)
	var follows := _follows(masses, radii)
	if follows != "":
		problems.append(follows)
	expect.call(problems.is_empty() and runs[0][0] == runs[1][0] and runs[0][1] == runs[1][1],
		"mass look (spring): the ball looks as heavy as it is (cube root) about its centre on the rod, the coil to its surface; physics unchanged against the body's own size",
		"; ".join(problems))


# --- buoyancy -------------------------------------------------------------------------------------

func check_buoyancy_look() -> void:
	var problems := []
	var masses := [5.0, 45.0, 80.0, 95.0, 150.0]
	var widths := []
	var runs := []
	for looks in [true, false]:
		var lab: Experiment = await _lab("buoyancy")
		# Both runs go through the same conditions; only what is drawn differs.
		for volume in ["big", "small"]:
			lab.set_control("volume", volume)
			var drum: float = lab.drum_radius()
			var w := []
			for m in masses:
				lab.set_control("mass", m)
				await _frames(1)
				w.append(lab.props.weight.scale.x)
				# The drum keeps its volume's size; the tag says the mass in the mission's words.
				if lab.drum_radius() != drum or lab.props.tag.text != "%d킬로그램" % int(m):
					problems.append("%s %s kg: radius %s, tag %s" % [volume, m, lab.drum_radius(), lab.props.tag.text])
				if absf(lab.props.weight.position.y - lab.drum_height() * 0.5) > 1e-6:
					problems.append("%s %s kg: the weight is not on the lid" % [volume, m])
			if widths.is_empty() or not looks:
				widths = w
			elif w != widths:
				problems.append("weight widths depend on the drum: %s vs %s" % [w, widths])
		lab.set_control("volume", "big")
		lab.set_control("mass", 80.0)
		if not looks:
			lab.props.set_mass(5.0)   # what is drawn only
		lab.release()
		var track := PackedFloat64Array()
		for i in 3 * STEP_HZ:
			await tree.physics_frame
			track.append(lab.drum.global_position.y)
		runs.append([track, lab.observations()])
		await _free(lab)
	var follows := _follows(masses, widths)
	if follows != "":
		problems.append(follows)
	if runs[0][1] != runs[1][1]:
		problems.append("panel %s vs %s" % [runs[0][1], runs[1][1]])
	for i in runs[0][0].size():
		if runs[0][0][i] != runs[1][0][i]:
			problems.append("step %d: drum at %s vs %s" % [i, runs[0][0][i], runs[1][0][i]])
			break
	expect.call(problems.is_empty() and runs[0][0] == runs[1][0] and runs[0][1] == runs[1][1],
		"mass look (buoyancy): the drum keeps its volume's size; the weight on its lid is as wide as the mass says (cube root), the tag names it; physics unchanged whatever is drawn",
		"; ".join(problems))


# --- 3. picture buttons ---------------------------------------------------------------------------

func check_pick_sizes() -> void:
	var problems := []
	var checked := 0
	for id in ["collision", "spring", "friction", "buoyancy", "free-fall"]:
		var definition := ExperimentRegistry.find(id)
		var picks := ConditionPicks.picks(definition)
		var entries := []
		for control in definition.controls:
			if not picks.has(control.id) or not (control.id as String).begins_with("mass"):
				continue
			for preset in picks[control.id]:
				var m: float
				if control.type == "choice":
					for option in control.options:
						if option.id == preset.value:
							m = float(option.kg)
				else:
					m = float(preset.value)
				entries.append([m, float(preset.get("size", -1.0)), preset.picture])
		var top := 0.0
		for e in entries:
			top = maxf(top, e[0])
		for e in entries:
			checked += 1
			if absf(e[1] - pow(e[0] / top, 1.0 / 3.0)) > 6e-4 or not e[2] in ["ball_blue", "ball_orange", "ball_red", "box", "weight"]:
				problems.append("%s %s kg: size %s, picture %s" % [id, e[0], e[1], e[2]])
	expect.call(problems.is_empty() and checked >= 15,
		"mass look (picture buttons): a mass's picture is as big as the lab draws it, (m / the heaviest button)^(1/3): equal masses equal (the two 1 kg collision balls), heavier bigger",
		"; ".join(problems))


# --- 4. the other cues ----------------------------------------------------------------------------

## Nothing physical: no collision object under the node.
static func _no_body(node: Node) -> bool:
	return node.find_children("*", "CollisionObject3D", true, false).is_empty() and not node is CollisionObject3D


func check_planet_signs() -> void:
	var problems := []
	for id in ["free-fall", "constraints"]:
		var lab: Experiment = await _lab(id)
		var sign: PlanetSign = lab.planet_sign
		var meshes := {}
		for option in lab._find_control("gravity").options:
			lab.set_control("gravity", option.id)
			if sign.planet != option.id or sign.mesh != PlanetSign.sign_mesh(option.id):
				problems.append("%s %s: sign shows %s" % [id, option.id, sign.planet])
			meshes[sign.mesh] = true
		if meshes.size() != lab._find_control("gravity").options.size() or not _no_body(sign):
			problems.append("%s: %d different globes, a body: %s" % [id, meshes.size(), not _no_body(sign)])
		await _free(lab)
	# Each globe's colours are its picture button's (PickPictures): the earth's sea and land, the
	# moon's grey, Jupiter's tan.
	var want := {"earth": [ArtPalette.SEA, ArtPalette.GRASS], "moon": [Color("d9dbe2")], "jupiter": [Color("e8b77d"), Color("c4573a")]}
	for world in want:
		var colours := PackedColorArray()
		for c: Color in PlanetSign.sign_mesh(world).surface_get_arrays(0)[Mesh.ARRAY_COLOR]:
			colours.append(c.linear_to_srgb())
		for c: Color in want[world]:
			if not Array(colours).any(func(v: Color) -> bool: return maxf(maxf(absf(v.r - c.r), absf(v.g - c.g)), absf(v.b - c.b)) < 0.03):
				problems.append("%s globe lacks %s" % [world, c.to_html(false)])
	expect.call(problems.is_empty(),
		"condition look (gravity): the free-fall and pendulum labs' signpost shows the chosen world's globe (its picture button's colours), one per world, no body",
		"; ".join(problems))


## The surface's colour among a mesh's vertex colours (sRGB, to a few 8-bit steps).
static func _has_colour(mesh: Mesh, c: Color) -> bool:
	for v: Color in mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]:
		var s := v.linear_to_srgb()
		if maxf(maxf(absf(s.r - c.r), absf(s.g - c.g)), absf(s.b - c.b)) < 0.03:
			return true
	return false


func check_surfaces() -> void:
	var problems := []
	for id in ["incline-friction", "friction"]:
		var lab: Experiment = await _lab(id)
		var node: MeshInstance3D = lab.props.incline_visual if id == "incline-friction" else lab.props.track_visual
		var meshes := {}
		for option in lab._find_control("material").options:
			lab.set_control("material", option.id)
			var stuff := SurfaceSkin.colour(option.id)
			if lab.props.surface != option.id or not _has_colour(node.mesh, stuff):
				problems.append("%s %s: surface %s" % [id, option.id, lab.props.surface])
			for other in SurfaceSkin.IDS:
				if other != option.id and _has_colour(node.mesh, SurfaceSkin.colour(other)):
					problems.append("%s %s: also %s's colour" % [id, option.id, other])
			meshes[node.mesh] = true
		if meshes.size() != lab._find_control("material").options.size() or not _no_body(node):
			problems.append("%s: %d different surfaces" % [id, meshes.size()])
		await _free(lab)
	expect.call(problems.is_empty(),
		"condition look (surface material): the slide and the push track are drawn in the chosen material's colour and pattern (SurfaceSkin), one mesh per material, no body",
		"; ".join(problems))
