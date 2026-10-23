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
extends RefCounted

const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const UI_THEME := "res://scripts/app/ui_theme.gd"
const STEP_HZ := 60
const CARRY_TOL := 1e-4      # m: carried ball centre vs the paw's held point (frame by frame)
const RELEASE_TOL := 1e-4    # m: the paw's held point vs the ball (launch point) on the release frame
const CONTACT_TOL := 1e-4    # m: paw front vs the box face plane
const RELEASE_DIR_DEG := 10.0  # deg: paw direction over the last frame vs the launch direction
## Frames (at 60 fps) from "공 놓기" to the release: CatActor.WINDUP_S + SWING_S = 0.48 s.
const THROW_FRAMES := 29
## The BreadCat look (the user's glb, 2026-10-23): 3,290 model vertices + the shadow.
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
	await check_layout("projectile")
	await check_layout("friction")


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
		frames_ok = frames_ok and absi(frames - THROW_FRAMES) <= 1 and not at_release.is_empty()
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
	expect.call(still and no_release and picked and regrip,
		"bread cat: 처음으로 / picking up the ball stop the throw (no late release), a press during the throw is ignored, the paw grips the ball again when it is put down",
		"%s %s %s %s" % [still, no_release, picked, regrip])
	await _free(lab)


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
