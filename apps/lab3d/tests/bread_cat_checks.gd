## Headless checks of the bread cat (Phase 1 Task 4g: CatActor wearing BreadCat; art-direction.md section 11), run by
## run_tests.gd. "물리는 모델, 고양이는 연기": the cat acts in step with the formula model and never
## changes it.
## 1. throw (projectile, through the "공 놓기" action): before the release the ball's mesh is in the
##    paw (the carried centre = the paw's held point, CARRY_TOL) while the ball body waits at the
##    launch point; on the release frame the held point = the ball body = the launch point
##    (RELEASE_TOL) before any physics step; the run from the release on (engine positions every
##    step, panel values) is the same as a direct release() and the throw takes THROW_FRAMES frames.
## 2. push (friction): both paws on the box mesh's -x face (CONTACT_TOL) and inside the face, on a
##    push, a pull, while sliding and after a stop; with the box reactions off the face is the body's;
##    the cat leans into a push and back on a pull; the box motion and panel are the same without
##    the cat (every step).
## 3. no physics: the cat has no collision object, shape or area (no layer at all), the labs' bodies
##    are the ones they had; mesh budget.
## 4. layout: in the front camera (phone, tablet, tablet with the sidebar open) the cat is in the
##    view, clear of the title, key cards, buttons and actions, and in front of nothing it should not
##    hide (the line of sight to the ball, its formula path and the box misses the cat).
## 5. storybook look (Task 4g2): every cat mesh draws the toon (cel) shader with the brown outline
##    pass (art_outline.gdshader: front faces culled, grown along NORMAL, at least the reference's
##    0.010 m), and the meshes keep the outline's contract (vertices at one position share one normal,
##    so the grown hull does not tear at seams); no other mesh of the lab (ball, box, island) has it.
## 6. every other lab (2026-10-27): a scripted run of each of the 9 labs (and 12 other conditions,
##    ROLE_RUNS) gives the same bodies (every step), panel and graph with and without the cat; in the
##    screen (phone, tablet, tablet with the sidebar) every frame the paws are on what the cat holds
##    (2e-3 m), its arms stretch at most STRETCH_MAX, its bag, head and tail are in no body (all of it
##    once it let go and settled: no moving body passes through it) and clear of the apparatus; on
##    the view it is inside, clear of the overlays, Dugi and Puppy and hides no body position or key
##    apparatus point; it cheers at the result; the orbit's cat stays under the orbit plane; one cat
##    per lab with no physics (nor its stand), 7 drawn nodes and the vertex budget.
extends RefCounted

const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const UI_THEME := "res://scripts/app/ui_theme.gd"
const STEP_HZ := 60
const CARRY_TOL := 1e-4      # m: carried ball centre vs the paw's held point (frame by frame)
const RELEASE_TOL := 1e-4    # m: the paw's held point vs the ball (launch point) on the release frame
const CONTACT_TOL := 1e-4    # m: paw front vs the box face plane
const RELEASE_DIR_DEG := 10.0  # deg: paw direction over the last frame vs the launch direction
## Frames (at 60 fps) before the release frame after "공 놓기": CatActor.WINDUP_S + SWING_S = 0.48 s
## (the release is on the 29th frame; exact, so a one-frame-late release fails).
const THROW_FRAMES := 28
## The BreadCat look (the user's glb, 2026-10-23; outline-ready rebuild 2026-10-24): 3,184 model vertices + the shadow.
const CAT_VERTS_MAX := 3500
const PHONE := Vector2(1560, 720)
const TABLET := Vector2(1152, 720)

var tree: SceneTree
var expect: Callable   # (ok: bool, label: String, detail: String)


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	await check_throw()
	await check_launch_heights()
	await check_throw_motion()
	await check_throw_cancel()
	await check_push()
	await check_push_motion_unchanged()
	await check_no_physics()
	await check_storybook()
	await check_layout("projectile")
	await check_layout("friction")
	await run_roles()


# --- helpers ----------------------------------------------------------------------------------

func _lab(id: String) -> Experiment:
	var lab := ExperimentRegistry.instantiate(ExperimentRegistry.find(id))
	tree.root.add_child(lab)
	await tree.process_frame
	await tree.physics_frame
	return lab


func _free(node: Node) -> void:
	node.queue_free()
	await tree.process_frame


## Projectile conditions: gravity, angle, speed, launch height (ball bottom above the floor).
const THROWS := [
	["earth", 45.0, 9.0, 0.5], ["moon", 30.0, 7.5, 1.5], ["jupiter", 60.0, 6.0, 0.5],
	["earth", 0.0, 9.0, 0.0], ["earth", 90.0, 5.0, 3.0], ["zero", 15.0, 3.0, 0.5], ["earth", 75.0, 9.0, 0.25],
	["earth", 45.0, 9.0, 1.0], ["earth", 30.0, 6.0, 2.0],
]


func _setup_throw(lab: Experiment, c: Array) -> void:
	lab.set_control("gravity", c[0])
	lab.set_control("angle", c[1])
	lab.set_control("speed", c[2])
	lab.manipulation_placed("ball", Transform3D(Basis(), Vector3(lab.START_X, c[3] + lab.BALL_RADIUS, 0.0)))


## Engine positions and panel text over `steps` fixed steps after the release, keyed by the step
## since the release (the corrector's count and the lab's clock: a ball stopped out of bounds counts
## on in the clock).
func _record(lab: Experiment, steps: int) -> Dictionary:
	var rec := {}
	var guard := 0
	while lab.clock() < (steps - 0.5) / float(STEP_HZ) and guard < steps + 10:
		guard += 1
		await tree.physics_frame
		rec["%d/%.6f" % [lab.corrector().steps, lab.clock()]] = [lab.ball.global_position, str(lab.observations())]
	return rec


# --- 1. throw ---------------------------------------------------------------------------------

func check_throw() -> void:
	var worst_carry := 0.0
	var worst_release := 0.0
	var moved := 0.0
	var frames_ok := true
	var body_still := true
	var same := true
	var detail := ""
	var detail_release := ""
	for c in THROWS:
		var lab: Experiment = await _lab("projectile")
		_setup_throw(lab, c)
		await tree.process_frame
		var cat: CatActor = lab.props.cat
		var juice: ArtJuice = lab.props.juice
		var launch: Vector3 = lab.ball_center()
		var at_release := {}
		cat.threw.connect(func() -> void:
			at_release.merge({"held": cat.held_point(), "ball": lab.ball.global_position, "released": lab.released,
				"steps": lab.corrector().steps, "carry": juice.carry()}), CONNECT_ONE_SHOT)
		worst_release = maxf(worst_release, cat.held_point().distance_to(launch))   # holding before the press
		lab.run_action("release")
		var frames := 0
		while not lab.released and frames < 120:
			await tree.process_frame   # the cat's _process ran in the frame before: carry and pose agree
			if lab.released:
				break
			frames += 1
			worst_carry = maxf(worst_carry, (lab.ball.global_position + juice.carry()).distance_to(cat.held_point()))
			moved = maxf(moved, juice.carry().length())
			body_still = body_still and lab.ball.global_position == launch and lab.ball.freeze
		frames_ok = frames_ok and frames == THROW_FRAMES and not at_release.is_empty()
		detail_release += " %d frames %s" % [frames, str(at_release.get("steps", "-"))]
		if not at_release.is_empty():
			worst_release = maxf(worst_release, maxf(at_release.held.distance_to(at_release.ball), at_release.ball.distance_to(launch)))
			frames_ok = frames_ok and at_release.released and at_release.steps == 0 and at_release.carry == Vector3.ZERO
		var thrown := await _record(lab, 3 * STEP_HZ)
		await _free(lab)
		# The same conditions released directly (no throw).
		var direct_lab: Experiment = await _lab("projectile")
		_setup_throw(direct_lab, c)
		await tree.process_frame
		direct_lab.release()
		var direct := await _record(direct_lab, 3 * STEP_HZ)
		await _free(direct_lab)
		# Keyed by the step since the release: the thrown run's recording starts one step later (its
		# release is in a frame's process, the direct one before a physics step); every common step
		# must match, and they cover the 3 s.
		var common := 0
		for key in thrown:
			if direct.has(key):
				common += 1
				if direct[key] != thrown[key]:
					same = false
					detail += " %s differs at %s: %s / %s" % [str(c), key, str(thrown[key]), str(direct[key])]
					break
		if common < 3 * STEP_HZ:
			same = false
			detail += " %s: only %d common steps" % [str(c), common]
	expect.call(worst_carry <= CARRY_TOL and moved > 0.15 and body_still,
		"bread cat: before the release the ball's mesh is in the paw (carried centre = held point), the ball body waits at the launch point",
		"max %s m over %d throws, the paw carries the mesh up to %.2f m" % [String.num_scientific(worst_carry), THROWS.size(), moved])
	expect.call(worst_release <= RELEASE_TOL and frames_ok,
		"bread cat: the ball leaves the paw on the release frame at the launch point (held point = ball = launch point, before any step), %d frames (%.2f s) after 공 놓기" % [THROW_FRAMES, THROW_FRAMES / 60.0],
		"max %s m;%s" % [String.num_scientific(worst_release), detail_release])
	expect.call(same, "bread cat: the thrown run (engine position every step, panel values, 3 s) is the same as a direct release", detail if detail != "" else "%d throws" % THROWS.size())


## The paw is the launch point at every launch height (2026-10-23 user decision: no launch post):
## from the floor up to 3 m the held point = the ball's centre, and above the paw's reach from the
## floor the cat stands on bread crates whose top is exactly under its bag (no crates when it stands
## on the floor), at most CRATE_H each.
func check_launch_heights() -> void:
	var lab: Experiment = await _lab("projectile")
	var cat: CatActor = lab.props.cat
	var crates: MeshInstance3D = lab.props.cat_stand
	var worst := 0.0
	var fit := true
	var detail := ""
	for h in [0.0, 0.5, 1.0, 2.0, 3.0]:
		lab.manipulation_placed("ball", Transform3D(Basis(), Vector3(lab.START_X, h + lab.BALL_RADIUS, 0.0)))
		await tree.process_frame
		worst = maxf(worst, cat.held_point().distance_to(lab.ball.global_position))
		var on_crates: bool = cat.stand_height > 0.01
		fit = fit and crates.visible == on_crates and (not on_crates or (absf(crates.scale.y - cat.position.y) < 1e-6
			and crates.position.x == cat.position.x and crates.position.z == cat.position.z
			and cat.stand_height / ceili(cat.stand_height / ProjectileProps.CRATE_H - 1e-6) <= ProjectileProps.CRATE_H + 1e-6))
		fit = fit and lab.find_children("LaunchPost", "", true, false).is_empty() and lab.find_children("LaunchPad", "", true, false).is_empty()
		detail += " h %.1f: crates %.2f m," % [h, cat.stand_height if on_crates else 0.0]
	expect.call(worst <= RELEASE_TOL and fit,
		"bread cat: the paw is the launch point at launch heights 0-3 m (no launch post / pad), crates under the cat as tall as needed",
		"max %s m;%s" % [String.num_scientific(worst), detail])
	await _free(lab)


## The throw is overhand and into the throw (2026-10-23 user feedback: the release was below the
## arm, so a throw down looked like a throw up): at launch heights 0.5-3 m and angles 0-75 deg the
## paw at the release is above the shoulder; over the swing the paw's speed (sampled every 1/1333 s on
## the cat's own path) only grows and is the largest just before the release; its direction over the
## last 1/60 s is within RELEASE_DIR_DEG of the formula launch direction; the windup goes back
## against the throw (and up over the head for a level throw).
func check_throw_motion() -> void:
	var worst_dir := 0.0
	var rising := true
	var above := true
	var windup_ok := true
	var detail := ""
	for h in [0.5, 1.0, 2.0, 3.0]:
		for a in [0.0, 15.0, 45.0, 75.0]:
			var lab: Experiment = await _lab("projectile")
			lab.set_control("angle", a)
			lab.manipulation_placed("ball", Transform3D(Basis(), Vector3(lab.START_X, h + lab.BALL_RADIUS, 0.0)))
			await tree.process_frame
			var cat: CatActor = lab.props.cat
			var launch: Vector3 = lab.ball_center()
			var d := Vector3(cos(deg_to_rad(a)), sin(deg_to_rad(a)), 0.0)
			above = above and launch.y >= cat.shoulder(CatActor.ARM_HOLD).y - 1e-4
			lab.run_action("release")
			var total := CatActor.WINDUP_S + CatActor.SWING_S
			var top: Vector3 = cat._throw_point(CatActor.WINDUP_S)
			if not ((top - launch).dot(d) < -0.15 and (a > 20.0 or top.y > launch.y + 0.3)):
				windup_ok = false
				detail += " windup h %.1f %d deg: %s" % [h, a, str((top - launch).snapped(Vector3.ONE * 0.01))]
			var last := 0.0
			var steps := 240   # 1/1333 s: the chord is the path length
			for i in range(1, steps + 1):
				var t0 := CatActor.WINDUP_S + CatActor.SWING_S * (i - 1) / steps
				var t1 := CatActor.WINDUP_S + CatActor.SWING_S * i / steps
				var v: float = cat._throw_point(t1).distance_to(cat._throw_point(t0))
				if v < last * 0.98 - 1e-6:   # (2 %: the path is sampled as a polyline; a chord across a corner is shorter)
					rising = false
					detail += " slower at h %.1f %d deg step %d: %.4f < %.4f" % [h, a, i, v, last]
				last = v
			var final_dir: Vector3 = (cat._throw_point(total) - cat._throw_point(total - 1.0 / 60.0)).normalized()
			var err := rad_to_deg(final_dir.angle_to(d))
			worst_dir = maxf(worst_dir, err)
			if err > RELEASE_DIR_DEG:
				detail += " h %.1f %d deg: %.1f deg" % [h, a, err]
			await _free(lab)
	expect.call(worst_dir <= RELEASE_DIR_DEG and rising and above and windup_ok,
		"bread cat: overhand throw (heights 0.5-3 m, 0-75 deg): paw above the shoulder at the release, speed rising to the release, last 1/60 s along the launch direction (<= %.0f deg), windup back (and up for a level throw)" % RELEASE_DIR_DEG,
		"max %.2f deg, rising %s, above %s, windup %s%s" % [worst_dir, rising, above, windup_ok, detail])


## "처음으로" and picking up the ball stop a throw: no late release; a second press during the throw
## does nothing.
func check_throw_cancel() -> void:
	var lab: Experiment = await _lab("projectile")
	var cat: CatActor = lab.props.cat
	lab.run_action("release")
	for i in 5:
		await tree.process_frame
	lab.run_action("release")   # ignored (still throwing)
	var still := cat.throwing()
	lab.run_action("reset")
	for i in THROW_FRAMES + 5:
		await tree.process_frame
	var no_release: bool = not lab.released and cat.mode == "hold" and lab.props.juice.carry() == Vector3.ZERO
	lab.run_action("release")
	for i in 5:
		await tree.process_frame
	lab.manipulation_started("ball")
	for i in THROW_FRAMES + 5:
		await tree.process_frame
	var picked: bool = not lab.released and not cat.throwing() and cat.mode == "free"
	lab.manipulation_placed("ball", Transform3D(Basis(), lab.ball_center()))
	var regrip: bool = cat.mode == "hold" and cat.held_point().distance_to(lab.ball_center()) <= RELEASE_TOL
	# set_cat_grip both ways: the paw stays on the waiting ball's centre (PR #16 review).
	lab.props.set_cat_grip(false)
	lab.props.set_cat_grip(true)
	regrip = regrip and cat.mode == "hold" and cat.held_point().distance_to(lab.ball_center()) <= RELEASE_TOL
	# A condition change during the throw (angle, speed, gravity) puts the ball back in the paw: no late
	# release, the cat holds it at the (new) launch point.
	var changes_ok := true
	for change in [["angle", 30.0], ["speed", 5.0], ["gravity", "moon"]]:
		lab.run_action("release")
		for i in 6:
			await tree.process_frame
		lab.set_control(change[0], change[1])
		for i in THROW_FRAMES + 5:
			await tree.process_frame
		changes_ok = changes_ok and not lab.released and cat.mode == "hold" and lab.props.juice.carry() == Vector3.ZERO \
			and cat.held_point().distance_to(lab.ball_center()) <= RELEASE_TOL
		expect.call(still and no_release and picked and regrip,
		"bread cat: 처음으로 / picking up the ball stop the throw (no late release), a press during the throw is ignored, the paw grips the ball again when it is put down",
		"%s %s %s %s" % [still, no_release, picked, regrip])
	expect.call(changes_ok, "bread cat: a condition change (angle, speed, gravity) during the throw: no late release, the ball back in the paw at the launch point", str(changes_ok))
	await _free(lab)
	await check_rebuild_during_throw()


## The screen is rebuilt during a throw (App rebuilds the 3D view with the screen's saved state): the
## old lab goes with its cat and its pending release (nothing is released later, no error), the new
## screen's cat holds the ball at the restored launch point and nothing is released.
func check_rebuild_during_throw() -> void:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = PHONE
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(ExperimentRegistry.find("projectile"))
	host.add_child(screen)
	await tree.process_frame
	screen.experiment.manipulation_placed("ball", Transform3D(Basis(), Vector3(-5.0, 1.25, 0.0)))
	screen.experiment_action("release")
	for i in 8:
		await tree.process_frame
	var old_lab: Experiment = screen.experiment
	var state: Dictionary = screen.capture_state()
	screen.queue_free()
	await tree.process_frame
	var again: Control = load(EXPERIMENT_SCREEN).new()
	again.setup(ExperimentRegistry.find("projectile"), state)
	host.add_child(again)
	for i in THROW_FRAMES + 10:
		await tree.process_frame
	var lab: Experiment = again.experiment
	var cat: CatActor = lab.props.cat
	var ok: bool = not is_instance_valid(old_lab) and not lab.released and cat.mode == "hold" \
		and cat.held_point().distance_to(lab.ball_center()) <= RELEASE_TOL and lab.ball_center().distance_to(Vector3(-5.0, 1.25, 0.0)) < 1e-3
	expect.call(ok, "bread cat: the screen rebuilt during a throw: the old lab and its pending release are gone, the new cat holds the ball at the restored launch point",
		"old valid %s, released %s, mode %s, ball %s" % [is_instance_valid(old_lab), lab.released, cat.mode, lab.ball_center()])
	host.queue_free()
	await tree.process_frame


# --- 2. push ----------------------------------------------------------------------------------

## Paw contact after this frame's poses (the lab's _process then the cat's, as in a frame).
func _contact(lab: Experiment) -> Dictionary:
	lab._process(0.0)
	var cat: CatActor = lab.props.cat
	cat.advance(0.0)
	var face: float = lab.props.cat_face_x()
	var gap := 0.0
	var inside := true
	for i in 2:
		var p := cat.hand_point(i)
		gap = maxf(gap, absf(p.x - face))
		inside = inside and p.y > 0.05 and p.y < lab.BOX - 0.05 and absf(p.z - lab.box.global_position.z) < lab.BOX * 0.5 - cat.look.paw_radius
	return {"gap": gap, "inside": inside, "body_gap": absf(face - (lab.box.global_position.x - lab.BOX * 0.5))}


func check_push() -> void:
	var lab: Experiment = await _lab("friction")
	var cat: CatActor = lab.props.cat
	var worst := 0.0
	var inside := true
	var lean_push := 0.0
	var lean_pull := 0.0
	var states := {}
	for f in [0.0, 20.0, 36.0, 0.0, -50.0, 0.0]:
		lab.set_applied_force(f)
		for i in 50:
			await tree.process_frame
			var c := _contact(lab)
			worst = maxf(worst, c.gap)
			inside = inside and c.inside
			states[lab.status()] = true
		var forward: float = cat.rig.global_basis.y.x   # the rig faces +x: its up leans to +x on a push
		if f > 0.0:
			lean_push = maxf(lean_push, forward)
		elif f < 0.0:
			lean_pull = minf(lean_pull, forward)
	expect.call(worst <= CONTACT_TOL and inside and states.has("sliding") and states.has("holding"),
		"bread cat: both paws stay on the box face (push, pull, sliding, at rest), inside the face",
		"max gap %s m, states %s" % [String.num_scientific(worst), states.keys()])
	expect.call(lean_push > 0.1 and lean_pull < -0.1,
		"bread cat: it leans into a push and back on a pull", "up.x %.2f / %.2f" % [lean_push, lean_pull])
	# Box reactions off: the mesh face is the body's face.
	lab.props.juice.process_mode = Node.PROCESS_MODE_DISABLED
	lab.props.juice.mesh.transform = Transform3D.IDENTITY
	lab.run_action("reset")
	lab.set_applied_force(40.0)
	var body_worst := 0.0
	for i in 60:
		await tree.process_frame
		var c := _contact(lab)
		body_worst = maxf(body_worst, maxf(c.gap, c.body_gap))
	lab.props.juice.process_mode = Node.PROCESS_MODE_INHERIT
	expect.call(body_worst <= CONTACT_TOL, "bread cat: without the box reactions the paws are on the box body's face",
		"max %s m" % String.num_scientific(body_worst))
	await _free(lab)


func _push_run(with_cat: bool) -> Array:
	var lab: Experiment = await _lab("friction")
	if not with_cat:
		lab.props.cat.queue_free()
		lab.props.cat = null
		await tree.process_frame
	var out := []
	for c in [["wood", "start", [[0, 20.0], [30, 36.0], [90, 0.0], [200, -50.0], [260, 0.0]]], ["steel", "light", [[0, 4.0], [40, -3.0], [120, 0.0]]]]:
		lab.set_control("material", c[0])
		lab.set_control("mass", c[1])
		lab.run_action("reset")
		await tree.physics_frame
		for k in 360:
			for e in c[2]:
				if e[0] == k:
					lab.set_applied_force(e[1])
			await tree.physics_frame
			out.append([lab.box.global_position, str(lab.observations())])
	await _free(lab)
	return out


func check_push_motion_unchanged() -> void:
	var with_cat := await _push_run(true)
	var without := await _push_run(false)
	expect.call(with_cat == without and with_cat.size() == 720,
		"bread cat: friction box motion (every step) and panel are the same with and without the cat", "%d steps" % with_cat.size())


# --- 3. no physics ----------------------------------------------------------------------------

func _verts(node: Node) -> int:
	var n := 0
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := (m as MeshInstance3D).mesh as ArrayMesh
		for s in mesh.get_surface_count():
			n += mesh.surface_get_array_len(s)
	return n


func check_no_physics() -> void:
	for id in ["projectile", "friction"]:
		if id.contains("/"):
			continue
		var lab: Experiment = await _lab(id)
		var cat: CatActor = lab.props.cat
		var physics := cat.find_children("*", "CollisionObject3D", true, false).size() + cat.find_children("*", "CollisionShape3D", true, false).size() \
			+ cat.find_children("*", "Area3D", true, false).size()
		var draws := cat.find_children("*", "GeometryInstance3D", true, false).size()
		var verts := _verts(cat)
		var hands_ok := cat.hands.size() == 2
		for k in 2:
			hands_ok = hands_ok and cat.hands[k].global_position.distance_to(cat.shoulder(k) + cat.arm_dir(k) * cat.look.hand_reach) < 1e-4
		expect.call(physics == 0 and not ((cat as Node) is CollisionObject3D) and draws <= 7 and verts <= CAT_VERTS_MAX and hands_ok,
			"bread cat (%s): no collision object, shape or area (no layer), at most 7 drawn nodes and %d vertices, hand nodes on the arm line" % [id, CAT_VERTS_MAX],
			"%d physics nodes, %d drawn, %d vertices" % [physics, draws, verts])
		await _free(lab)


# --- 5. storybook look --------------------------------------------------------------------------

## Worst normal angle (deg) between vertices of one surface at the same position (UV seam copies).
func _seam_split_deg(mesh: Mesh) -> float:
	var worst := 0.0
	for si in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var seen := {}
		for i in verts.size():
			var key := Vector3i((verts[i] * 1e5).round())
			if seen.has(key):
				worst = maxf(worst, rad_to_deg(normals[seen[key]].angle_to(normals[i])))
			else:
				seen[key] = i
	return worst


func check_storybook() -> void:
	var outline_lin := ArtPalette.OUTLINE.srgb_to_linear()
	for id in ["projectile", "friction"]:
		var lab: Experiment = await _lab(id)
		var cat: CatActor = lab.props.cat
		var meshes := 0
		var wired := true
		var worst_split := 0.0
		var detail := ""
		for node in cat.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi == cat.shadow:
				continue
			meshes += 1
			var toon := mi.material_override as ShaderMaterial
			var outline := toon.next_pass as ShaderMaterial if toon != null else null
			var ok := toon != null and toon.shader == ArtKit.TOON_SHADER and outline != null and outline.shader == ArtKit.OUTLINE_SHADER \
				and toon.get_shader_parameter("albedo_texture") != null
			if ok:
				var c: Vector4 = outline.get_shader_parameter("color")
				ok = is_equal_approx(outline.get_shader_parameter("world_width"), ArtKit.OUTLINE_WORLD) and ArtKit.OUTLINE_WORLD >= 0.010 \
					and is_equal_approx(outline.get_shader_parameter("screen_pixels"), ArtKit.OUTLINE_PIXELS) and ArtKit.OUTLINE_PIXELS >= 1.0 \
					and Vector3(c.x, c.y, c.z).distance_to(Vector3(outline_lin.r, outline_lin.g, outline_lin.b)) < 1e-4
			if not ok:
				wired = false
				detail += " %s not wired;" % mi.name
			worst_split = maxf(worst_split, _seam_split_deg(mi.mesh))
		var code := ArtKit.OUTLINE_SHADER.code
		var hull := code.contains("cull_front") and code.contains("unshaded") and code.contains("VERTEX = view_pos + n * max(world_width")
		var toon_code := ArtKit.TOON_SHADER.code
		var cel := toon_code.contains("unshaded") and toon_code.contains("smoothstep(-edge, edge, ndl)")
		# Characters only: every other mesh of the lab (ball, box, island, props) keeps its material
		# (no outline pass, not the toon shader).
		var props_plain := true
		for node in lab.find_children("*", "MeshInstance3D", true, false):
			if cat.is_ancestor_of(node):
				continue
			var m := (node as MeshInstance3D).material_override
			props_plain = props_plain and (m == null or (m.next_pass == null and not (m is ShaderMaterial and (m as ShaderMaterial).shader == ArtKit.TOON_SHADER)))
		expect.call(meshes == 6 and wired and hull and cel,
			"bread cat (%s): all 6 meshes draw the cel shader with the brown outline pass (cull_front, grown along NORMAL, >= 0.010 m, #6e4630)" % id,
			"%d meshes, wired %s%s, hull code %s, cel code %s" % [meshes, wired, detail, hull, cel])
		expect.call(worst_split < 0.5, "bread cat (%s): no split normals at one position (the outline hull stays closed)" % id,
			"worst seam normal split %.3f deg" % worst_split)
		expect.call(props_plain, "bread cat (%s): no other mesh of the lab (ball, box, island) has the toon shader or an outline" % id,
			"props plain %s" % props_plain)
		await _free(lab)


# --- 4. layout --------------------------------------------------------------------------------

func _open(id: String, size: Vector2, sidebar: bool) -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = size
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.setup(ExperimentRegistry.find(id))
	host.add_child(screen)
	await tree.process_frame
	await tree.physics_frame
	if sidebar:
		screen.open_sidebar(false)
	for i in 3:
		await tree.process_frame
	return screen


func _at(screen: Control, world: Vector3) -> Vector2:
	var view: View3D = screen.view
	return view.rig.unproject_position(world) / (Vector2(view.viewport.size) / view.size)


## World AABB of the cat's drawn meshes.
static func cat_aabb(cat: CatActor) -> AABB:
	var box := AABB()
	var first := true
	for m in cat.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.name == "Shadow":
			continue
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _screen_rect(screen: Control, box: AABB) -> Rect2:
	var r := Rect2(_at(screen, box.position), Vector2.ZERO)
	for i in 8:
		r = r.expand(_at(screen, box.get_endpoint(i)))
	return r


func check_layout(id: String) -> void:
	for setup in [[PHONE, false, "phone"], [TABLET, false, "tablet"], [TABLET, true, "tablet, sidebar open"]]:
		var screen: Control = await _open(id, setup[0], setup[1])
		var lab: Experiment = screen.experiment
		var cat: CatActor = lab.props.cat
		cat.advance(0.0)
		var view_rect := Rect2(Vector2.ZERO, screen.view.size)
		var box := cat_aabb(cat)
		var rect := _screen_rect(screen, box)
		var clear := true
		var hit := ""
		for c: Control in [screen._title_bar, screen._top_buttons, screen._key_row, screen._action_row]:
			if c.visible and c.get_rect().intersects(rect):
				clear = false
				hit += " " + c.name
		# Lines of sight from the camera to what the cat must not hide.
		var eye: Vector3 = screen.view.rig.global_position
		var targets: Array[Vector3] = []
		if id == "projectile":
			targets.append(lab.ball.global_position)
			targets.append_array(Array(lab.formula_path()))
		else:
			for x in [-5.5, -3.0, 0.0, 3.0, 5.5]:
				targets.append(Vector3(x, lab.BOX * 0.5, 0.0))
			targets.append(lab.handle.global_position)
		var hidden := 0
		for t in targets:
			if box.intersects_segment(eye, t):
				hidden += 1
		var on_screen := view_rect.encloses(rect) and rect.size.x > 12.0
		expect.call(on_screen and clear and hidden == 0,
			"bread cat (%s, %s): in the front view, clear of the title, key cards, buttons and actions, hides none of %d points (ball / path / box / handle)" % [id, setup[2], targets.size()],
			"cat %s in view %s%s, hidden %d" % [rect, view_rect.size, hit, hidden])
		screen.get_parent().queue_free()
		await tree.process_frame


# --- 6. every lab (2026-10-27: the cat has a hand in all 11 labs) -------------------------------

## The labs the cat joined on 2026-10-27, each with a scripted run of its primary use: [step, op,
## ...] ops before that fixed step ("act" id: an action; "pick" id: a finger picks a body up; "move"
## id offset: the held body is moved by the offset since the pick, linearly up to that step; "place"
## id: put down) and the run's length in steps.
const ROLE_RUNS := {
	"free-fall": {"steps": 240, "ops": [[30, "act", "release"]]},
	"collision": {"steps": 300, "ops": [[30, "act", "release"]]},
	"incline-friction": {"steps": 240, "ops": [[0, "call", "set_angle", 35.0], [30, "act", "release"]]},
	"spring": {"steps": 360, "ops": [[1, "pick", "ball"], [40, "move", "ball", Vector3(1.3, 0.0, 0.0)], [60, "place", "ball"]]},
	"pulley": {"steps": 240, "ops": [[1, "pick", "handle"], [50, "move", "handle", Vector3(0.0, -2.0, 0.0)], [90, "place", "handle"], [120, "pick", "handle"], [150, "move", "handle", Vector3(0.0, -1.0, 0.0)], [170, "place", "handle"]]},
	"rotation": {"steps": 200, "ops": [[1, "pick", "handle"], [50, "move", "handle", Vector3(0.0, -1.0, 0.0)], [130, "place", "handle"]]},
	"constraints": {"steps": 360, "ops": [[30, "act", "release"]]},
	"buoyancy": {"steps": 600, "ops": [[30, "act", "release"]]},
	"orbit": {"steps": 480, "ops": [[30, "act", "launch"]]},
	# Other conditions (the same checks; `lab` before the slash).
	"free-fall/high": {"steps": 240, "ops": [[0, "call", "set_height", 8.0], [30, "act", "release"]]},
	"free-fall/low": {"steps": 120, "ops": [[0, "call", "set_height", 0.5], [30, "act", "release"]]},
	"collision/back": {"steps": 300, "ops": [[0, "call", "set_control", "velocity_a", -3.0], [30, "act", "release"]]},
	"collision/bumper": {"steps": 300, "ops": [[0, "call", "manipulation_placed", "ball_a", Transform3D(Basis(), Vector3(-6.5, 0.4, 0.0))], [30, "act", "release"]]},
	"incline-friction/flat": {"steps": 120, "ops": [[0, "call", "set_angle", 0.0], [30, "act", "release"]]},
	"incline-friction/steep": {"steps": 240, "ops": [[0, "call", "set_angle", 45.0], [1, "call", "set_run_length", 2.0], [30, "act", "release"]]},
	"spring/in": {"steps": 240, "ops": [[1, "pick", "ball"], [40, "move", "ball", Vector3(-2.6, 0.0, 0.0)], [60, "place", "ball"]]},
	"rotation/far": {"steps": 160, "ops": [[0, "call", "set_control", "effort", "far"], [1, "call", "set_layout", -1.5, -2.5], [2, "pick", "handle"], [50, "move", "handle", Vector3(0.0, -1.0, 0.0)], [120, "place", "handle"]]},
	"rotation/near": {"steps": 160, "ops": [[0, "call", "set_control", "effort", "near"], [2, "pick", "handle"], [50, "move", "handle", Vector3(0.0, -1.0, 0.0)], [120, "place", "handle"]]},
	"constraints/left": {"steps": 420, "ops": [[0, "call", "set_control", "length", 3.5], [20, "pick", "rope"], [40, "move", "rope", Vector3(-2.0, 1.2, 0.0)], [41, "place", "rope"]]},
	"buoyancy/small": {"steps": 600, "ops": [[0, "call", "set_control", "volume", "small"], [1, "call", "set_control", "mass", 60.0], [30, "act", "release"]]},
	"orbit/far": {"steps": 300, "ops": [[0, "call", "manipulation_placed", "planet", Transform3D(Basis(), Vector3(5.0, 2.0, 0.0))], [1, "call", "set_control", "speed", 4.0], [30, "act", "launch"]]},
}
const BODY_CLEAR := 0.01        # m: a body sample this far inside a cat mesh's box is a touch
const SETTLE_STEPS := 40        # after a let-go (0.44 s follow-through and settle, and a margin)
## The most the arms stretch while their paws are on something (2026-10-27: the lever's far effort
## point once lifted with the fulcrum moved fully left, about 2.4, is the longest reach; the lever
## lifted, the orbit's planet held over the head and the ball by a bumper about 1.9-2.0).
const STRETCH_MAX := 2.5


func run_roles() -> void:
	for id in ROLE_RUNS:
		await check_role_unchanged(id)
		await check_role(id)
	await check_role_budget()


## Applies the ops of `run` due before step `k` on `lab`; `held` keeps the picked bodies' start.
func _role_ops(lab: Experiment, run: Dictionary, k: int, held: Dictionary) -> void:
	for op in run.ops:
		match op[1]:
			"act":
				if op[0] == k:
					lab.run_action(op[2])
			"call":
				if op[0] == k:
					lab.callv(op[2], op.slice(3))
			"pick":
				if op[0] == k:
					var body: Node3D = lab.manipulation_body(op[2])
					held[op[2]] = [body.global_position, k]
					lab.manipulation_started(op[2])
			"move":
				if held.has(op[2]) and k <= op[0] and k > held[op[2]][1]:
					var body: Node3D = lab.manipulation_body(op[2])
					var from: Vector3 = held[op[2]][0]
					body.global_position = from + op[3] * clampf(float(k - held[op[2]][1]) / float(op[0] - held[op[2]][1]), 0.0, 1.0)
			"place":
				if op[0] == k and held.has(op[2]):
					var body: Node3D = lab.manipulation_body(op[2])
					lab.manipulation_placed(op[2], body.global_transform)
					held.erase(op[2])


## The lab's bodies (engine transforms) and panel, graph every step of the run.
func _role_record(id: String, with_cat: bool) -> Array:
	var lab: Experiment = await _lab(id.get_slice("/", 0))
	if not with_cat:
		lab.props.cat.queue_free()
		lab.props.cat = null
	await tree.process_frame   # both runs start in the same frame phase
	var run: Dictionary = ROLE_RUNS[id]
	var held := {}
	var out := []
	for k in run.steps:
		_role_ops(lab, run, k, held)
		await tree.physics_frame
		var row := [str(lab.observations()), str(lab.graph_series())]
		for b in lab.find_children("*", "CollisionObject3D", true, false):
			row.append((b as Node3D).global_transform)
		out.append(row)
	await _free(lab)
	return out


## "물리는 모델, 고양이는 연기": every step of the run is the same without the cat.
func check_role_unchanged(id: String) -> void:
	var with_cat := await _role_record(id, true)
	var without := await _role_record(id, false)
	var first := -1
	for k in mini(with_cat.size(), without.size()):
		if with_cat[k] != without[k]:
			first = k
			break
	expect.call(first < 0 and with_cat.size() == ROLE_RUNS[id].steps,
		"bread cat (%s): bodies (every step), panel and graph are the same with and without the cat" % id,
		("first difference at step %d: %s" % [first, _row_diff(with_cat[first], without[first])]) if first >= 0 else "%d steps" % with_cat.size())


static func _row_diff(a: Array, b: Array) -> String:
	if a.size() != b.size():
		return "%d / %d entries" % [a.size(), b.size()]
	for i in a.size():
		if a[i] != b[i]:
			return "entry %d: %s / %s" % [i, str(a[i]).left(200), str(b[i]).left(200)]
	return ""


## The cat's drawn meshes: [mesh, is an arm].
static func _cat_parts(cat: CatActor) -> Array:
	var out := []
	for m in cat.rig.find_children("*", "MeshInstance3D", true, false):
		out.append([m, String(m.name).begins_with("Arm")])
	return out


## The first vertex of mesh `mi` (every 4th, world) inside a collision shape of `body` (BODY_CLEAR
## inside its surface), or INF.
static func _mesh_in_body(mi: MeshInstance3D, body: CollisionObject3D) -> Vector3:
	var v: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for c in body.find_children("*", "CollisionShape3D", false, false):
		var cs := c as CollisionShape3D
		var to_shape := cs.global_transform.affine_inverse() * mi.global_transform
		var shape := cs.shape
		for i in range(0, v.size(), 4):
			var p := to_shape * v[i]
			var inside := false
			if shape is SphereShape3D:
				inside = p.length() < shape.radius - BODY_CLEAR
			elif shape is CylinderShape3D:
				inside = Vector2(p.x, p.z).length() < shape.radius - BODY_CLEAR and absf(p.y) < shape.height * 0.5 - BODY_CLEAR
			elif shape is BoxShape3D:
				var h: Vector3 = shape.size * 0.5 - Vector3.ONE * BODY_CLEAR
				inside = absf(p.x) < h.x and absf(p.y) < h.y and absf(p.z) < h.z
			if inside:
				return mi.global_transform * v[i]
	return Vector3.INF


## The first world point of `points` inside the ellipsoid that fills mesh `mi`'s box (its own
## space: the rounded head, bag and tail without the box's empty corners), or INF.
static func _inside(mi: MeshInstance3D, points: PackedVector3Array) -> Vector3:
	var box := mi.get_aabb()
	var c := box.get_center()
	var half := box.size * 0.5
	var inv := mi.global_transform.affine_inverse()
	for p in points:
		var q := (inv * p - c) / half
		if q.length_squared() < 1.0:
			return p
	return Vector3.INF


## Paws on what they hold: the largest distance of a paw's front from the held body's surface.
static func _contact_gap(id: String, lab: Experiment, cat: CatActor) -> float:
	var gap := 0.0
	match id:
		"free-fall", "constraints", "orbit":
			# (the pendulum's model: its bob body is posed on the next step after a condition change)
			var at: Vector3 = lab.props._ball_nodes[lab.props.cat_ball].global_position if id == "free-fall" else (lab.models[0].position() if id == "constraints" else lab.planet.global_position)
			gap = cat.held_point().distance_to(at)
		"collision", "spring":
			var ball: Node3D = lab.ball_a if id == "collision" else lab.ball
			var r: float = lab.RADIUS_A if id == "collision" else lab.BALL_RADIUS
			for i in 2:
				gap = maxf(gap, absf(cat.hand_point(i).distance_to(ball.global_position) - r))
		"buoyancy":
			for i in 2:
				var p: Vector3 = cat.hand_point(i) - lab.drum.global_position
				var h: float = lab.drum_height() * 0.5
				gap = maxf(gap, maxf(absf(Vector2(p.x, p.z).length() - lab.drum_radius()), maxf(0.0, absf(p.y) - h)))
		"incline-friction":
			var inv: Transform3D = lab.box.global_transform.affine_inverse()
			for i in 2:
				var p: Vector3 = inv * cat.hand_point(i)
				gap = maxf(gap, maxf(absf(p.y - lab.BOX * 0.5), maxf(absf(p.x), absf(p.z)) - lab.BOX * 0.5))
		"pulley":
			var grip: Vector3 = lab.handle.global_position
			for i in 2:
				var p: Vector3 = cat.hand_point(i) - grip
				var h: Vector3 = lab.HANDLE_SIZE * 0.5
				gap = maxf(gap, maxf(absf(p.z + h.z), maxf(absf(p.x) - h.x, absf(p.y) - h.y)))
		"rotation":
			var inv: Transform3D = lab.beam.global_transform.affine_inverse()
			for i in 2:
				var p: Vector3 = inv * cat.hand_point(i)
				gap = maxf(gap, maxf(absf(p.y - lab.BEAM_THICK * 0.5), maxf(absf(p.x) - lab.BEAM_HALF, absf(p.z) - lab.BEAM_DEPTH * 0.5)))
	return gap


## The cat should hold now (the paws on the body) in the scripted run, before its let-go.
static func _role_holds(id: String, lab: Experiment, cat: CatActor) -> bool:
	match id:
		"pulley":
			return lab.holding and not cat.rising()
		"rotation":
			return true
		"spring":
			return not lab.released or lab.holding != ""
	return cat.attached() and not lab.released


## Static points the cat must not hide in the front view (besides the bodies' motion).
static func _role_keep(id: String, lab: Experiment) -> PackedVector3Array:
	var out := PackedVector3Array()
	match id:
		"free-fall":
			for y in range(1, 17):
				out.append(FreeFallProps.RULER_AT + Vector3(0.1, y * 0.5, 0.06))
		"spring":
			for x in range(0, 6):
				out.append(Vector3(lab.ANCHOR_X + 0.3 + x * 0.5, lab.ROD_Y, 0.0))
			for y in range(1, 5):
				out.append(Vector3(SpringProps.BAR_X, y * 0.5, SpringProps.BAR_Z))
		"pulley":
			out.append(lab.handle.global_position)
			out.append(lab.GUIDE)
		"rotation":
			for x in range(-6, 7):
				out.append(Vector3(x * 0.5, lab.PIVOT_Y + lab.BEAM_THICK * 0.5, 0.0))
			out.append(lab.handle.global_position)
		"constraints":
			out.append(lab.anchor(0))
			out.append(lab.anchor(1))
		"buoyancy":
			for y in range(1, 9):
				out.append(Vector3(BuoyancyProps.HALF_X - 0.35, lab.FLOOR_Y + y * 0.2, -BuoyancyProps.HALF_Z))
		"orbit":
			out.append(Vector3(0.0, lab.ORBIT_Y, 0.0))
		"incline-friction":
			for x in range(-7, 8):
				out.append(lab._pivot.global_transform * Vector3(x * 0.5, 0.0, 0.0))
	return out


## The scripted run in the front view of a screen of `size` (sidebar open: `sidebar`): every frame
## the cat's paws on what it holds, its bag, head and tail clear of every body (all of it once it let
## go and settled) and of the apparatus meshes; on the view it stays inside, clear of the overlays,
## Dugi and Puppy, and hides no body position of the run and no key apparatus point; it cheers at
## the run's result.
func check_role(run_id: String) -> void:
	var id := run_id.get_slice("/", 0)
	for setup in [[PHONE, false, "phone"], [TABLET, false, "tablet"], [TABLET, true, "tablet, sidebar open"]]:
		var screen: Control = await _open(id, setup[0], setup[1])
		var lab: Experiment = screen.experiment
		var cat: CatActor = lab.props.cat
		var cats := lab.find_children("*", "CatActor", true, false).size()
		var run: Dictionary = ROLE_RUNS[run_id]
		var held := {}
		var problems := []
		var worst_gap := 0.0
		var gap_step := -1
		var worst_stretch := 0.0
		var holds := 0
		var free_since := -1
		var eye: Vector3 = screen.view.rig.global_position
		var view_rect := Rect2(Vector2.ZERO, screen.view.size)
		var overlays: Array[Rect2] = screen.overlay_rects()
		var cast: IslandCast = screen.cast
		var cheers0 := cat.cheers
		var stand: Node3D = lab.find_child("CatCrates", true, false)
		if stand == null:
			stand = lab.find_child("CatWedge", true, false)
		var apparatus := {}
		for k in run.steps:
			_role_ops(lab, run, k, held)
			await tree.physics_frame
			await tree.process_frame
			if k == 0 or run.ops.any(func(op: Array) -> bool: return op[1] == "call" and op[0] == k):
				apparatus = _apparatus(lab, cat, stand)   # (a condition may have moved it)
			if lab.has_method("_process"):
				lab._process(0.0)
			cat.advance(0.0)
			var holding := _role_holds(id, lab, cat)
			if holding:
				holds += 1
				var gap := _contact_gap(id, lab, cat)
				if gap > worst_gap:
					worst_gap = gap
					gap_step = k
				worst_stretch = maxf(worst_stretch, maxf(cat.stretch(0), cat.stretch(1)))
				free_since = -1
			elif free_since < 0:
				free_since = k
			var settled: bool = free_since >= 0 and k - free_since > SETTLE_STEPS
			var bodies := lab.find_children("*", "RigidBody3D", true, false)
			for part in _cat_parts(cat):
				if part[1] and not settled:
					continue   # the paws hold a body
				for b in bodies:
					var hit := _mesh_in_body(part[0], b)
					if hit != Vector3.INF:
						problems.append("step %d: %s in %s at %s" % [k, part[0].name, b.name, hit.snapped(Vector3.ONE * 0.01)])
						break
				if not part[1]:
					var base_y := cat.global_position.y + 0.05
					var touching := PackedVector3Array()
					var wb: AABB = part[0].global_transform * part[0].get_aabb()
					var lo := Vector3i((wb.position / 0.5).floor())
					var hi := Vector3i((wb.end / 0.5).floor())
					for cx in range(lo.x, hi.x + 1):
						for cy in range(lo.y, hi.y + 1):
							for cz in range(lo.z, hi.z + 1):
								for p in apparatus.get(Vector3i(cx, cy, cz), PackedVector3Array()):
									if p.y > base_y:
										touching.append(p)
					var hit2 := _inside(part[0], touching)
					if hit2 != Vector3.INF:
						problems.append("step %d: %s in the apparatus at %s" % [k, part[0].name, hit2.snapped(Vector3.ONE * 0.01)])
			if id == "orbit" and lab.released and cat_aabb(cat).end.y >= lab.ORBIT_Y - lab.PLANET_RADIUS:
				problems.append("step %d: the cat reaches the orbit plane" % k)
			if k % 6 == 0:
				# On the view: inside, clear of the overlays and the cast; nothing kept behind the cat.
				var rect: Rect2 = screen.view_rect_of(cat_aabb(cat))
				if not view_rect.encloses(rect) or rect.size.x < 12.0:
					problems.append("step %d: cat %s not in the view" % [k, rect])
				for o in overlays:
					if o.intersects(rect):
						problems.append("step %d: cat under an overlay" % k)
						break
				if cast != null and not setup[1]:
					for actor: Node3D in [cast.dugi, cast.puppy]:
						if screen.view_rect_of(actor.bounds()).intersects(rect):
							problems.append("step %d: cat over %s" % [k, actor.name])
				var targets := _role_keep(id, lab)
				for b in bodies:
					targets.append((b as Node3D).global_position)
				for part in _cat_parts(cat):
					var mi: MeshInstance3D = part[0]
					var inv := mi.global_transform.affine_inverse()
					var box := mi.get_aabb()
					for t in targets:
						if box.intersects_segment(inv * eye, inv * t):
							problems.append("step %d: %s hides %s" % [k, mi.name, t.snapped(Vector3.ONE * 0.01)])
							break
			if problems.size() > 6:
				break
		var cheered := cat.cheers > cheers0
		if setup[2] == "phone":
			expect.call(cats == 1 and holds > 10 and worst_gap <= 2e-3 and worst_stretch <= STRETCH_MAX and cheered,
				"bread cat (%s): one cat; its paws on what it holds while it holds (%d frames), it cheers at the result" % [run_id, holds],
				"gap %s m (step %d), stretch %.2f, cheered %s, cats %d" % [String.num_scientific(worst_gap), gap_step, worst_stretch, cheered, cats])
		expect.call(problems.is_empty(),
			"bread cat (%s, %s): never in a body (all of it once it let go), clear of the apparatus; in the front view clear of the overlays, Dugi and Puppy, hiding no body or key point" % [run_id, setup[2]],
			"; ".join(problems.slice(0, 6)))
		screen.get_parent().queue_free()
		await tree.process_frame


## Points of the lab's static apparatus meshes in 0.5 m cells (every static mesh but the island,
## shadows, the cast, the cat and its stand).
static func _apparatus(lab: Experiment, cat: CatActor, stand: Node3D) -> Dictionary:
	var apparatus := {}   # 0.5 m cell -> points
	for m in lab.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.name in ["Island", "IslandShadows"] or String(mi.name).contains("Shadow") or cat.is_ancestor_of(mi) or mi == stand \
				or (stand != null and stand.is_ancestor_of(mi)) or not mi.is_visible_in_tree():
			continue
		var moving := false
		var n: Node = mi
		while n != lab and n != null:
			if n is RigidBody3D:
				moving = true
			n = n.get_parent()
		if moving or mi.mesh == null:
			continue
		var arrays := mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in range(0, v.size(), maxi(1, v.size() / 400)):
			var p: Vector3 = mi.global_transform * v[i]
			var cell := Vector3i((p / 0.5).floor())
			if not apparatus.has(cell):
				apparatus[cell] = PackedVector3Array()
			apparatus[cell].append(p)
	return apparatus


## Every lab: one cat, no physics, at most 7 drawn nodes and the vertex budget.
func check_role_budget() -> void:
	for id in ROLE_RUNS:
		if id.contains("/"):
			continue
		var lab: Experiment = await _lab(id)
		var cat: CatActor = lab.props.cat
		var physics := cat.find_children("*", "CollisionObject3D", true, false).size() + cat.find_children("*", "CollisionShape3D", true, false).size() \
			+ cat.find_children("*", "Area3D", true, false).size()
		var stand_physics := 0
		for name in ["CatCrates", "CatWedge"]:
			var stand := lab.find_child(name, true, false)
			if stand != null:
				stand_physics += stand.find_children("*", "CollisionObject3D", true, false).size() + int(stand is CollisionObject3D)
		var draws := cat.find_children("*", "GeometryInstance3D", true, false).size()
		expect.call(physics == 0 and stand_physics == 0 and draws <= 7 and _verts(cat) <= CAT_VERTS_MAX and lab.find_children("*", "CatActor", true, false).size() == 1,
			"bread cat (%s): one cat, no collision object, shape or area (nor its stand), at most 7 drawn nodes and %d vertices" % [id, CAT_VERTS_MAX],
			"%d physics nodes, %d drawn, %d vertices" % [physics + stand_physics, draws, _verts(cat)])
		await _free(lab)
