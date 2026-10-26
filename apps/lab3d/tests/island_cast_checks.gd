## Headless checks of the island cast (Phase 1 Task 4h: Dugi explains, Puppy holds the flag;
## art-direction.md section 12), run by run_tests.gd. "물리는 모델, 캐릭터는 연기": the cast never
## changes the labs.
## 1. models: the glb node trees the actors use, the outline mesh contract on every imported mesh
##    (vertices at one position share one normal; closed shells: every edge of the welded mesh has
##    exactly two triangles) and the vertex / triangle budget (tools/mesh_contract.py checks the
##    same in Blender).
## 2. actors: every cast mesh draws the toon shader with the outline pass; no collision object,
##    shape or area; draw nodes.
## 3. explain cycle: rest -> raise -> point -> lower -> rest; the pointer stick is hidden at rest and
##    shows only once the arm is up (its tip above the ground whenever it shows); while pointing the
##    tip is on the line shoulder -> target (also a moving one); stop(true) is at once.
## 4. trigger: the status watch explains once per run after delay_s, a flickering status does not
##    repeat it, it re-arms after REARM_S outside or a user change; the projectile's throw through
##    the screen ends with Dugi pointing at the formula landing point and the dialogue showing the
##    lab's observe text; 처음으로 closes it.
## 5. placement, every listed experiment: Dugi (also pointing) and Puppy face the front camera and
##    stand on the island clear of its trees and rocks, of every apparatus mesh, of the bread cat and
##    of the bodies' motion (a run of the primary action); Puppy stands behind the whole apparatus.
## 6. layout, every listed experiment, phone / tablet / tablet with the sidebar, on the view: both in
##    the front view clear of the title, key cards, buttons, actions and tip; Dugi hides no
##    apparatus cell, sampled body position or the cat farther than him; Puppy overlaps none of them
##    nor Dugi (phone, tablet); the dialogue box and portrait inside the view, clear of the overlays
##    and Dugi (it may cover Puppy for a while), none beside the open sidebar (Dugi points all the same).
##    Dialogue: pages split at spaces, at most 2 lines that fit, joining back to the observe text in
##    every experiment; typewriter, tap = whole page / next / close (Dugi lowers), the read timer,
##    the sidebar closes it.
## 7. physics unchanged, every listed experiment: engine bodies (every step) and panel texts are the
##    same with and without the cast while Dugi explains (from its own trigger, or made to explain
##    at step 120 when the run reaches no result status in 420 steps).
extends RefCounted

const EXPERIMENT_SCREEN := "res://scripts/shell/experiment_screen.gd"
const UI_THEME := "res://scripts/app/ui_theme.gd"
const PHONE := Vector2(1560, 720)
const TABLET := Vector2(1152, 720)
const POINT_TOL_DEG := 1.0
const DUGI_VERTS_MAX := 3300        # 3,050 model vertices + the shadow
const PUPPY_VERTS_MAX := 3450       # 3,199 + the shadow
const TRIS_MAX := 6000
const CELL := 0.25                  # m: apparatus meshes are voxelised at this size
const CLEARANCE := 0.2              # m: cast bounds grown by this must touch no apparatus cell
const MOTION_CLEARANCE := 0.5       # m: horizontal distance to any sampled body position
const POINTING_CLEARANCE := 0.05    # m: each mesh of the pointing pose (arm, stick) from the apparatus
const RUN_STEPS := 600

var tree: SceneTree
var expect: Callable
## Per experiment (check_placement): apparatus cells, sampled motion, the cat's box (for layout).
var _scene := {}
var _explained: Array[Vector3] = []     # explain_point() sampled over the last _motion() run


func _init(scene_tree: SceneTree, expect_fn: Callable) -> void:
	tree = scene_tree
	expect = expect_fn


func run() -> void:
	check_models()
	await check_actors()
	await check_explain_cycle()
	await check_watch()
	await check_projectile_explains()
	for definition in ExperimentRegistry.load_all():
		await check_placement(definition.id)
		await check_layout(definition.id)
	await check_dialogue()
	await check_physics_unchanged()


# --- helpers ----------------------------------------------------------------------------------

func _open(id: String, size: Vector2, sidebar := false, with_cast := true) -> Control:
	var host := Control.new()
	host.theme = load(UI_THEME).build()
	host.size = size
	tree.root.add_child(host)
	var screen: Control = load(EXPERIMENT_SCREEN).new()
	screen.show_cast = with_cast
	screen.setup(ExperimentRegistry.find(id))
	host.add_child(screen)
	await tree.process_frame
	await tree.physics_frame
	if sidebar:
		screen.open_sidebar(false)
	for i in 3:
		await tree.process_frame
	return screen


func _close(screen: Control) -> void:
	screen.get_parent().queue_free()
	await tree.process_frame


## The model-space transform of `node` under `root` (the glb is not in the tree).
static func _model_xf(node: Node3D, root: Node) -> Transform3D:
	var xf := Transform3D()
	var n: Node = node
	while n != root:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## [worst seam normal split (deg), edges not shared by exactly two triangles] of one mesh.
static func mesh_contract(mesh: Mesh) -> Array:
	var worst := 0.0
	var open := 0
	for si in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var index: Variant = arrays[Mesh.ARRAY_INDEX]
		var weld := PackedInt32Array()
		weld.resize(verts.size())
		var seen := {}
		for i in verts.size():
			var key := Vector3i((verts[i] * 1e5).round())
			if seen.has(key):
				worst = maxf(worst, rad_to_deg(normals[seen[key]].angle_to(normals[i])))
				weld[i] = seen[key]
			else:
				seen[key] = i
				weld[i] = i
		var tri: PackedInt32Array = index if index != null else PackedInt32Array(range(verts.size()))
		var edges := {}
		for t in range(0, tri.size(), 3):
			for e in 3:
				var a := weld[tri[t + e]]
				var b := weld[tri[t + (e + 1) % 3]]
				var k := Vector2i(mini(a, b), maxi(a, b))
				edges[k] = edges.get(k, 0) + 1
		for k in edges:
			if edges[k] != 2:
				open += 1
	return [worst, open]


static func _tris(mesh: Mesh) -> int:
	var n := 0
	for si in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(si)
		var index: Variant = arrays[Mesh.ARRAY_INDEX]
		n += (index.size() if index != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n


static func _verts(node: Node) -> int:
	var n := 0
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := (m as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			n += mesh.surface_get_array_len(s)
	return n


## Cells (CELL m) touched by the lab's apparatus meshes (not the island, its shadows, the cast):
## big meshes (the projectile's two fences are one mesh) count only where they are.
static func apparatus_cells(lab: Experiment) -> Dictionary:
	var cells := {}
	for m in lab.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.name in ["Island", "IslandShadows"] or String(mi.name).contains("Shadow") or not mi.is_visible_in_tree():
			continue
		var xf := mi.global_transform
		for si in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var index: Variant = arrays[Mesh.ARRAY_INDEX]
			var tri: PackedInt32Array = index if index != null else PackedInt32Array(range(v.size()))
			for t in range(0, tri.size(), 3):
				var a := xf * v[tri[t]]
				var b := xf * v[tri[t + 1]]
				var c := xf * v[tri[t + 2]]
				var k := int(ceil(maxf(a.distance_to(b), maxf(b.distance_to(c), a.distance_to(c))) / CELL)) + 1
				for i in k + 1:
					for j in k + 1 - i:
						var p := a + (b - a) * (float(i) / k) + (c - a) * (float(j) / k)
						cells[Vector3i((p / CELL).floor())] = true
	return cells


static func _hits_cells(box: AABB, cells: Dictionary) -> bool:
	var lo := Vector3i((box.position / CELL).floor())
	var hi := Vector3i((box.end / CELL).floor())
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				if cells.has(Vector3i(x, y, z)):
					return true
	return false


## Positions of the lab's bodies every 6 steps over a run of its primary action (or at rest).
func _motion(screen: Control) -> Array:
	var lab: Experiment = screen.experiment
	var primary := ""
	for action in screen.definition.actions:
		if action.get("style") == "primary":
			primary = action.id
	if primary != "":
		screen.experiment_action(primary)
	var out := []
	_explained.clear()
	for k in RUN_STEPS:
		await tree.physics_frame
		if k % 6 == 0:
			for b in lab.find_children("*", "RigidBody3D", true, false):
				out.append((b as Node3D).global_position)
			out.append(lab.explain_point())
			_explained.append(lab.explain_point())
	return out


# --- 1. models --------------------------------------------------------------------------------

func check_models() -> void:
	for spec in [["res://assets/characters/dugi.glb", "Dugi", ["Body", "Body/ArmL/HandL", "Body/ArmR/HandR", "Body/ArmR/Pointer/PointerTip", "Body/Head/EarL", "Body/Head/EarR"], DUGI_VERTS_MAX],
			["res://assets/characters/puppy.glb", "Puppy", ["Body", "Body/ArmL/HandL", "Body/ArmR/HandR", "Body/ArmR/Flag/FlagCloth", "Body/Head/EarL", "Body/Head/EarR"], PUPPY_VERTS_MAX]]:
		var model: Node = (load(spec[0]) as PackedScene).instantiate()
		var root := model.get_node(spec[1])
		var missing := []
		for path in spec[2]:
			if root.get_node_or_null(path) == null:
				missing.append(path)
		var worst := 0.0
		var open := 0
		var verts := 0
		var tris := 0
		var meshes := 0
		for m in root.find_children("*", "MeshInstance3D", true, false):
			var c := mesh_contract((m as MeshInstance3D).mesh)
			worst = maxf(worst, c[0])
			open += c[1]
			verts += (m as MeshInstance3D).mesh.surface_get_array_len(0)
			tris += _tris((m as MeshInstance3D).mesh)
			meshes += 1
		model.free()
		expect.call(missing.is_empty(), "cast model %s: the nodes the actor uses" % spec[1], "missing %s" % [missing])
		expect.call(worst < 0.5 and open == 0, "cast model %s: outline mesh contract (one normal per position, closed shells)" % spec[1],
			"worst seam split %.3f deg, %d open / non-manifold edges" % [worst, open])
		expect.call(verts <= spec[3] and tris < TRIS_MAX, "cast model %s: budget (%d meshes)" % [spec[1], meshes], "%d vertices, %d triangles" % [verts, tris])


# --- 2. actors --------------------------------------------------------------------------------

func check_actors() -> void:
	var screen := await _open("projectile", TABLET)
	var cast: IslandCast = screen.cast
	expect.call(cast != null and cast.dugi != null and cast.puppy != null and cast.get_parent() == screen.view.viewport and not screen.experiment.is_ancestor_of(cast),
		"cast: Dugi and Puppy are on the island next to the lab (not inside it)", "")
	if cast == null:
		await _close(screen)
		return
	var physics := cast.find_children("*", "CollisionObject3D", true, false).size() + cast.find_children("*", "CollisionShape3D", true, false).size() \
		+ cast.find_children("*", "Area3D", true, false).size()
	var wired := true
	for node in cast.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.name == "Shadow":
			continue
		var toon := mi.material_override as ShaderMaterial
		wired = wired and toon != null and toon.shader == ArtKit.TOON_SHADER and toon.next_pass is ShaderMaterial \
			and (toon.next_pass as ShaderMaterial).shader == ArtKit.OUTLINE_SHADER
	var dugi_draws := cast.dugi.find_children("*", "GeometryInstance3D", true, false).size()
	var puppy_draws := cast.puppy.find_children("*", "GeometryInstance3D", true, false).size()
	expect.call(physics == 0 and wired, "cast: every mesh draws the toon shader with the outline pass; no collision object, shape or area", "%d physics nodes" % physics)
	expect.call(dugi_draws == 7 and puppy_draws == 3 and _verts(cast.dugi) <= DUGI_VERTS_MAX and _verts(cast.puppy) <= PUPPY_VERTS_MAX
		and not cast.dugi.pointer.visible,
		"cast: Dugi 7 draw nodes (the stick hidden at rest), Puppy 3", "Dugi %d / %d vertices, Puppy %d / %d" % [dugi_draws, _verts(cast.dugi), puppy_draws, _verts(cast.puppy)])
	# Both face the front camera.
	var eye: Vector3 = screen.view.rig.global_position
	var facing_ok := true
	for actor: Node3D in [cast.dugi, cast.puppy]:
		var to_eye := Vector2(eye.x - actor.global_position.x, eye.z - actor.global_position.z).normalized()
		var front := Vector2(actor.global_basis.z.x, actor.global_basis.z.z).normalized()
		facing_ok = facing_ok and rad_to_deg(front.angle_to(to_eye)) < 1.0
	expect.call(facing_ok, "cast: Dugi and Puppy face the front camera", "")
	var wave := []
	for k in 30:
		cast.puppy.advance(0.1)
		wave.append(cast.puppy.wave_angle())
	expect.call(wave.max() > deg_to_rad(3.0) and wave.min() < -deg_to_rad(3.0) and absf(wave.max()) <= deg_to_rad(PuppyActor.WAVE_DEG) + 1e-6,
		"cast: Puppy's banner waves gently about the pole", "%.1f..%.1f deg" % [rad_to_deg(wave.min()), rad_to_deg(wave.max())])
	await _close(screen)


# --- 3. explain cycle -------------------------------------------------------------------------

func _aim_error(dugi: DugiActor, target: Vector3) -> float:
	var s := dugi.shoulder_point()
	return rad_to_deg((dugi.tip_point() - s).angle_to(target - s))


func check_explain_cycle() -> void:
	var holder := Node3D.new()
	tree.root.add_child(holder)
	var dugi := DugiActor.new()
	holder.add_child(dugi)
	dugi.position = Vector3(3.0, 0.0, 1.0)
	var target := Vector3(0.5, 0.6, 0.0)
	var moving := [target]   # a lambda captures locals by value: the moving target lives in an array
	await tree.process_frame
	dugi.set_process(false)
	var dt := 1.0 / 60.0
	var states := [dugi.state]
	var rest_hidden := not dugi.pointer.visible
	var tip_low := INF
	var worst_aim := 0.0
	var moving_aim := 0.0
	dugi.explain(func() -> Vector3: return moving[0])
	var frames := int((DugiActor.RAISE_S + DugiActor.POINT_S + DugiActor.LOWER_S) * 60.0) + 30
	for k in frames:
		dugi.advance(dt)
		if states[-1] != dugi.state:
			states.append(dugi.state)
		if dugi.pointer.visible:
			tip_low = minf(tip_low, dugi.tip_point().y)
		if dugi.state == "point":
			if k < 120:
				worst_aim = maxf(worst_aim, _aim_error(dugi, target))
			else:
				target = Vector3(0.5 + 0.01 * (k - 120), 0.6, 0.0)   # a moving target
				moving[0] = target
				dugi.advance(0.0)
				moving_aim = maxf(moving_aim, _aim_error(dugi, target))
	var back_rest := dugi.state == "rest" and not dugi.pointer.visible and dugi.arm.basis.is_equal_approx(Basis())
	expect.call(states == ["rest", "raise", "point", "lower", "rest"] and rest_hidden and back_rest,
		"Dugi: rest -> raise -> point -> lower -> rest; the stick hidden at rest, the arm back in its rest pose", "%s" % [states])
	expect.call(worst_aim < POINT_TOL_DEG and moving_aim < POINT_TOL_DEG,
		"Dugi: while pointing the stick's tip is on the line shoulder -> target (also a moving target)", "%.3f / %.3f deg" % [worst_aim, moving_aim])
	expect.call(tip_low > 0.05, "Dugi: whenever the stick shows its tip is above the ground", "lowest tip %.3f m" % tip_low)
	dugi.explain(func() -> Vector3: return target)
	for k in 40:
		dugi.advance(dt)
	var was_visible := dugi.pointer.visible and dugi.speaking()
	dugi.stop(true)
	expect.call(was_visible and dugi.state == "rest" and not dugi.pointer.visible and not dugi.speaking(),
		"Dugi: stop(true) (처음으로) is back at rest at once", "")
	holder.queue_free()
	await tree.process_frame


# --- 4. trigger -------------------------------------------------------------------------------

func check_watch() -> void:
	var stub := GDScript.new()
	stub.source_code = "extends Experiment\nvar s := \"ready\"\nfunc status() -> String:\n\treturn s\nfunc explain_point() -> Vector3:\n\treturn Vector3(-1.0, 0.5, 0.0)\n"
	stub.reload()
	var lab = stub.new()
	tree.root.add_child(lab)
	var cast := IslandCast.create({"cast": {"dugi": {"at": [2.0, 1.0], "explain_on": ["done"], "delay_s": 0.5}}, "observe": "x"}, lab)
	tree.root.add_child(cast)
	cast.set_process(false)
	cast.dugi.set_process(false)
	var dt := 0.1
	var counts := []
	lab.s = "done"
	for k in 4:
		cast.watch(dt)
	counts.append(cast.explain_count)   # 0.4 s < delay
	cast.watch(dt)
	counts.append(cast.explain_count)   # 0.5 s: explains
	for k in 20:   # a flickering status (0.2 s out, 0.2 s in): no repeat
		lab.s = "moving" if (k / 2) % 2 == 0 else "done"
		cast.watch(dt)
	counts.append(cast.explain_count)
	lab.s = "moving"
	for k in 11:
		cast.watch(dt)
	lab.s = "done"
	for k in 5:
		cast.watch(dt)
	counts.append(cast.explain_count)   # re-armed after REARM_S outside
	cast.user_changed()
	for k in 5:
		cast.watch(dt)
	counts.append(cast.explain_count)   # a user change re-arms (the status stayed)
	expect.call(counts == [0, 1, 1, 2, 3] and cast.text == "x",
		"cast: explains once per run after delay_s; a flickering status does not repeat it; re-armed after %.1f s outside or a user change" % IslandCast.REARM_S, "%s" % [counts])
	cast.queue_free()
	lab.queue_free()
	await tree.process_frame


func check_projectile_explains() -> void:
	var screen := await _open("projectile", TABLET)
	var lab: Experiment = screen.experiment
	var cast: IslandCast = screen.cast
	screen._end_question()        # the prediction round is not under test here (game_round_checks):
	screen._reason_pending = ""   # no question, and no reason told first
	screen.experiment_action("release")
	var guard := 0
	while not cast.dugi.speaking() and guard < 600:
		guard += 1
		await tree.process_frame
	var path: PackedVector3Array = lab.formula_path()
	var landing := path[path.size() - 1]
	var status: String = lab.status()
	for k in int(DugiActor.RAISE_S * 60.0) + 4:
		await tree.process_frame
	var aim := _aim_error(cast.dugi, landing)
	var box: DialogueBox = screen.dialogue
	expect.call(cast.explain_count == 1 and status in ["landed", "fence"] and lab.explain_point().distance_to(landing) < 1e-4 and aim < POINT_TOL_DEG,
		"cast (projectile): after the throw lands Dugi points at the formula landing point (the end of the formula path)",
		"status %s, %d explanations, point %s vs %s, aim %.3f deg" % [status, cast.explain_count, lab.explain_point(), landing, aim])
	expect.call(box.visible and box.active and box.joined() == ExperimentRegistry.kid_text(screen.definition, "say") and box.name_label.text == "두기두기"
		and box.label.text == box.page_text(0),
		"cast (projectile): the dialogue opens with the lab's kid say text exactly (only split into pages)", box.label.text)
	screen.experiment_action("reset")
	await tree.process_frame
	expect.call(cast.dugi.state == "rest" and not box.visible and not box.active and not cast.dugi.pointer.visible,
		"cast (projectile): 처음으로 puts Dugi back at rest and closes the dialogue at once", cast.dugi.state)
	await _close(screen)


# --- 5. placement -----------------------------------------------------------------------------

func check_placement(id: String) -> void:
	var screen := await _open(id, TABLET)
	var lab: Experiment = screen.experiment
	var cast: IslandCast = screen.cast
	if cast == null:
		expect.call(false, "cast (%s): the definition places Dugi and Puppy" % id, "")
		await _close(screen)
		return
	var cells := apparatus_cells(lab)
	var island := lab.find_child("Island", true, false)
	var center: Vector3 = island.get_meta("center")
	var motion := await _motion(screen)
	var target := lab.explain_point()
	screen.experiment_action("reset")
	await tree.physics_frame
	var problems := []
	var eye := IslandCast.front_eye(screen.definition.camera)
	for actor: Node3D in [cast.dugi, cast.puppy]:
		var to_eye := Vector2(eye.x - actor.global_position.x, eye.z - actor.global_position.z).normalized()
		var front := Vector2(actor.global_basis.z.x, actor.global_basis.z.z).normalized()
		if rad_to_deg(front.angle_to(to_eye)) > 1.0:
			problems.append("%s does not face the front camera" % actor.name)
	var cat_box := AABB()
	for c in lab.find_children("CatActor", "", true, false):
		cat_box = IslandCast.drawn_bounds((c as CatActor).rig)
	# Dugi at rest, and pointing at the lab's explain point.
	var dugi := cast.dugi
	dugi.set_process(false)
	var boxes := {"Dugi": dugi.bounds(), "Puppy": cast.puppy.bounds()}
	dugi.explain(func() -> Vector3: return target)
	dugi.advance(DugiActor.RAISE_S + 0.1)
	boxes["Dugi pointing"] = dugi.bounds()
	# The raised arm and stick reach out diagonally: each of their meshes on its own, closer.
	var reach_hits := false
	for m in dugi.rig.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.is_visible_in_tree() and _hits_cells((mi.global_transform * mi.get_aabb()).grow(POINTING_CLEARANCE), cells):
			reach_hits = true
	dugi.stop(true)
	dugi.set_process(true)
	for who in boxes:
		var box: AABB = boxes[who]
		var actor: Node3D = cast.puppy if who == "Puppy" else dugi
		var at := Vector2(actor.global_position.x, actor.global_position.z)
		if at.distance_to(Vector2(center.x, center.z)) > ArtKit.ISLAND_RADIUS - 1.3:
			problems.append("%s off the island" % who)
		for o in ArtKit.island_obstacles(center):
			if at.distance_to(Vector2(o[0], o[1])) < o[2] + 0.45:
				problems.append("%s in decoration at %s" % [who, o])
		if who != "Dugi pointing" and _hits_cells(box.grow(CLEARANCE), cells) or who == "Dugi pointing" and reach_hits:
			problems.append("%s touches an apparatus mesh" % who)
		if cat_box.size != Vector3.ZERO and box.grow(CLEARANCE).intersects(cat_box):
			problems.append("%s touches the bread cat" % who)
		var flat := AABB(Vector3(box.position.x, -100.0, box.position.z), Vector3(box.size.x, 200.0, box.size.z)).grow(MOTION_CLEARANCE)
		for p in motion:
			if flat.has_point(p):
				problems.append("%s in the bodies' motion at %s" % [who, p])
				break
	# Puppy behind the whole apparatus (its front behind the apparatus' back).
	var apparatus_back := INF
	for k in cells:
		apparatus_back = minf(apparatus_back, k.z * CELL)
	if cast.puppy.bounds().end.z >= apparatus_back:
		problems.append("Puppy not behind the apparatus (front z %.2f, apparatus back %.2f)" % [cast.puppy.bounds().end.z, apparatus_back])
	_scene[id] = {"cells": cells, "motion": motion, "cat": cat_box, "explained": _explained.duplicate()}
	if id == "orbit":
		var top := maxf(boxes["Dugi"].end.y, maxf(boxes["Dugi pointing"].end.y, boxes["Puppy"].end.y))
		var consts: Dictionary = (lab.get_script() as GDScript).get_script_constant_map()
		if top + 0.012 >= consts.ORBIT_Y - consts.PLANET_RADIUS:
			problems.append("the cast reaches the planet's plane")
	expect.call(problems.is_empty(), "cast (%s): Dugi (also pointing) and Puppy on the island, clear of trees, rocks, every apparatus mesh, the bread cat and the bodies' motion (%d samples)" % [id, motion.size()],
		"; ".join(problems))
	await _close(screen)


# --- 6. layout --------------------------------------------------------------------------------

## What the front view must keep visible, on the view: [rect, distance from the camera] of every
## apparatus cell, every sampled body position (a 0.6 m box) and the bread cat.
func _keep(screen: Control, scene: Dictionary) -> Array:
	var eye: Vector3 = screen.view.rig.global_position
	var out := []
	for k in scene.cells:
		var b := AABB(Vector3(k) * CELL, Vector3.ONE * CELL)
		out.append([screen.view_rect_of(b), eye.distance_to(b.get_center()), "apparatus"])
	for p in scene.motion:
		out.append([screen.view_rect_of(AABB(p - Vector3.ONE * 0.3, Vector3.ONE * 0.6)), eye.distance_to(p), "motion"])
	var cat: AABB = scene.cat
	if cat.size != Vector3.ZERO:
		out.append([screen.view_rect_of(cat), eye.distance_to(cat.get_center()), "cat"])
	return out


func check_layout(id: String) -> void:
	if not _scene.has(id):
		return
	for setup in [[PHONE, false, "phone"], [TABLET, false, "tablet"], [TABLET, true, "tablet, sidebar open"]]:
		var screen := await _open(id, setup[0], setup[1])
		var cast: IslandCast = screen.cast
		var lab: Experiment = screen.experiment
		var view_rect := Rect2(Vector2.ZERO, screen.view.size)
		var problems := []
		var overlays: Array[Rect2] = screen.overlay_rects()
		var keep := _keep(screen, _scene[id])
		var eye: Vector3 = screen.view.rig.global_position
		var dugi_r: Rect2 = screen.view_rect_of(cast.dugi.bounds())
		var puppy_r: Rect2 = screen.view_rect_of(cast.puppy.bounds())
		for pair in [["Dugi", dugi_r], ["Puppy", puppy_r]]:
			var r: Rect2 = pair[1]
			if r.size.x < 8.0 or not view_rect.grow(-4.0).encloses(r):
				problems.append("%s not in the view %s" % [pair[0], r])
			for o in overlays:
				if o.intersects(r):
					problems.append("%s under an overlay" % pair[0])
		# Dugi hides nothing farther than him (apparatus, bodies' motion, cat); things may pass in front.
		var dugi_depth := eye.distance_to(cast.dugi.bounds().get_center()) - 0.4
		var hidden := 0
		for k in keep:
			if k[1] > dugi_depth and (k[0] as Rect2).intersects(dugi_r.grow(2.0)):
				hidden += 1
		if hidden > 0:
			problems.append("Dugi hides %d apparatus / motion / cat rects" % hidden)
		# Puppy (full views): never over the apparatus, the motion, the cat or Dugi on the view.
		if not setup[1]:
			var over := 0
			for k in keep:
				if (k[0] as Rect2).intersects(puppy_r.grow(4.0)):
					over += 1
			if over > 0 or puppy_r.intersects(dugi_r):
				problems.append("Puppy overlaps %d apparatus / motion / cat rects%s" % [over, ", Dugi" if puppy_r.intersects(dugi_r) else ""])
		# Explaining: the dialogue.
		cast.dugi.explain(lab.explain_point)
		for k in int(DugiActor.RAISE_S * 60.0) + 3:
			await tree.process_frame
		var box: DialogueBox = screen.dialogue
		if not cast.dugi.speaking():
			problems.append("Dugi not explaining")
		if setup[1]:
			if box.visible or box.active:
				problems.append("dialogue shown beside the open sidebar")
		else:
			if not (box.visible and box.active):
				problems.append("dialogue not shown")
			for r in box.rects():
				if not view_rect.encloses(r):
					problems.append("dialogue %s outside the view" % r)
				for o in overlays:
					if o.intersects(r):
						problems.append("dialogue under an overlay")
				if r.intersects(screen.dugi_rect()):
					problems.append("dialogue covers Dugi")
				if r.grow(4.0).has_point(screen.view_point(lab.explain_point())):
					problems.append("dialogue covers what Dugi points at")
				for p: Vector3 in _scene[id].explained:   # the target over a whole run (moving bodies too)
					if r.grow(4.0).has_point(screen.view_point(p)):
						problems.append("dialogue covers what Dugi points at during the run (%s)" % p)
						break
			if box.portrait.position.x > box.size.x * 0.5:
				problems.append("portrait not on the left")
		expect.call(problems.is_empty(), "cast (%s, %s): Dugi and Puppy in the front view clear of the overlays; Dugi hides no apparatus, motion or cat; Puppy over none of them nor Dugi; the dialogue clear of the controls, cards, Dugi and what he points at (none beside the open sidebar)" % [id, setup[2]],
			"; ".join(problems))
		await _close(screen)


## The dialogue: pages = the observe text split at spaces into at most 2 lines that fit, for every
## experiment on phone and tablet; typewriter, tap to show all / next / close (Dugi lowers his arm),
## the read timer, and opening the sidebar closes it.
func check_dialogue() -> void:
	var split_problems := []
	var max_pages := 0
	for definition in ExperimentRegistry.load_all():
		for size in [PHONE, TABLET]:
			var screen := await _open(definition.id, size)
			var box: DialogueBox = screen.dialogue
			if not screen._layout_dialogue():
				split_problems.append("%s %s: no room" % [definition.id, size])
			else:
				# A lab with a prediction opens with Dugi's question (Plan G4): its pages first, then
				# the question goes and his kid say text and the prediction's reason are checked the same way.
				var say := ExperimentRegistry.kid_text(definition, "say")
				var texts: Array = [say]
				if screen._asking:
					texts.push_front(str(MissionTracker.predict(definition).question))
					texts.append(str(MissionTracker.predict(definition).reason))
				for text in texts:
					if text != texts[0] or not screen._asking:
						screen._end_question()
						box.open(text)
						screen._layout_dialogue()
					split_problems.append_array(_page_problems(box, definition.id, text))
					max_pages = maxi(max_pages, box.pages().size())
			await _close(screen)
	expect.call(split_problems.is_empty(), "dialogue: every kid say text (and prediction question and reason) splits at its spaces into pages of at most %d lines that fit (phone, tablet), and joins back exactly" % DialogueBox.LINES,
		"; ".join(split_problems) if not split_problems.is_empty() else "up to %d pages" % max_pages)

	var screen := await _open("collision", TABLET)
	screen._end_question()   # the prediction's question first goes (the round is not under test here)
	screen._reason_pending = ""
	var cast: IslandCast = screen.cast
	var box: DialogueBox = screen.dialogue
	box.set_process(false)
	box.words = screen.definition.observe   # a long text (the shared one: two pages on a tablet) to turn pages
	cast.dugi.explain(screen.experiment.explain_point)
	for k in 3:
		await tree.process_frame
	var opened := box.active and box.visible and box.page == 0
	# Taps only where it is drawn: the box and the bust take them, the empty band above the box
	# (inside the control's rect) passes them to the 3D view.
	var r := box.rects()
	var corner := Vector2(20.0, 20.0)                                  # above the box, left end
	var on_box := r[0].get_center() - box.position
	var on_bust := r[1].position + r[1].size * Vector2(0.5, 0.8) - box.position
	var on_ears := r[1].position + r[1].size * Vector2(0.5, 0.1) - box.position
	expect.call(not box._has_point(corner) and not box._has_point(on_ears) and box._has_point(on_box) and box._has_point(on_bust),
		"dialogue: takes taps only on the box and the bust; the band above the box passes them to the 3D view", "")
	box.step(0.1)
	var partial := box.label.visible_characters > 0 and not box.typed()
	box.advance()   # tap: the whole page
	var full := box.typed() and box.page == 0 and box.label.visible_characters == -1
	var pages := box.pages().size()
	box.advance()   # tap: next page
	var second := pages > 1 and box.page == 1 and not box.typed()
	for k in pages:
		box.advance()
		box.advance()
	for k in int(DugiActor.LOWER_S * 60.0) + 4:
		await tree.process_frame
	var closed := not box.active and not box.visible and cast.dugi.state == "rest"
	expect.call(opened and partial and full and second and closed,
		"dialogue (collision, %d pages): types out, a tap shows the page, the next turns it, past the last it closes and Dugi lowers his arm" % pages,
		"opened %s, typing %s, full %s, page 2 %s, closed %s" % [opened, partial, full, second, closed])
	# Untouched: it reads itself through and closes; Dugi points all the while.
	cast.dugi.explain(screen.experiment.explain_point)
	for k in 3:
		await tree.process_frame
	var pointing := true
	var t := 0.0
	while box.active and t < 60.0:
		box.step(0.1)
		t += 0.1
		await tree.process_frame
		pointing = pointing and (cast.dugi.state == "point" or cast.dugi.state == "raise" or not box.active)
	var expected := 0.0
	for k in pages:
		var n := box.page_text(k).length()
		expected += n / DialogueBox.CHARS_PER_S + DialogueBox.READ_S + DialogueBox.READ_PER_CHAR_S * n
	expect.call(not box.active and pointing and t > expected - 1.0 and t < expected + 1.0 and t > DugiActor.POINT_S,
		"dialogue: untouched it closes after reading every page (Dugi pointing until then, longer than his own %.0f s)" % DugiActor.POINT_S,
		"closed after %.1f s (expected %.1f s)" % [t, expected])
	# The sidebar closes it.
	cast.dugi.stop(true)
	await tree.process_frame
	cast.dugi.explain(screen.experiment.explain_point)
	for k in 3:
		await tree.process_frame
	var was := box.active
	screen.open_sidebar(false)
	for k in 2:
		await tree.process_frame
	expect.call(was and not box.active and not box.visible, "dialogue: opening the sidebar closes it (no dialogue beside the sidebar)", "")
	await _close(screen)


## The problems of `box`'s pages for `text`: joined back exactly, at most LINES lines a page, every
## line within the label, the ▼ clear of the words.
static func _page_problems(box: DialogueBox, id: String, text: String) -> Array:
	var problems := []
	var font := box.label.get_theme_font("font")
	var fs := box.label.get_theme_font_size("font_size")
	if box.joined() != text:
		problems.append("%s: pages != %s" % [id, text.left(12)])
	for pg in box.pages():
		if pg.lines.size() > DialogueBox.LINES:
			problems.append("%s: %d lines" % [id, pg.lines.size()])
		for line in pg.lines:
			if font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > box.label.size.x + 0.5:
				problems.append("%s: line too wide" % id)
	if box.more.position.x < box.label.position.x + box.label.size.x or box.more.position.x + box.more.get_minimum_size().x > box.box.size.x:
		problems.append("%s: the ▼ overlaps the words or leaves the box" % id)
	return problems


# --- 7. physics unchanged ---------------------------------------------------------------------

func _record(id: String, with_cast: bool) -> Array:
	var screen := await _open(id, TABLET, false, with_cast)
	var lab: Experiment = screen.experiment
	var out := []
	var primary := ""
	for action in screen.definition.actions:
		if action.get("style") == "primary":
			primary = action.id
	if primary != "":
		screen.experiment_action(primary)
	var explained := false
	for k in 420:
		if id == "friction":
			for e in [[0, 20.0], [30, 36.0], [150, 0.0]]:
				if e[0] == k:
					lab.set_applied_force(e[1])
		if with_cast and k == 120 and not explained:
			screen.cast.dugi.explain(lab.explain_point)   # no result status yet: point during the run anyway
		await tree.physics_frame
		var row := [str(lab.observations())]
		for b in lab.find_children("*", "RigidBody3D", true, false):
			row.append((b as Node3D).global_transform)
		out.append(row)
		if with_cast and screen.cast.dugi.speaking():
			explained = true
	await _close(screen)
	return [out, explained]


func check_physics_unchanged() -> void:
	for definition in ExperimentRegistry.load_all():
		var id: String = definition.id
		var without: Array = await _record(id, false)
		var with_cast: Array = await _record(id, true)
		var same: bool = without[0] == with_cast[0]
		var first := -1
		if not same:
			for k in mini(without[0].size(), with_cast[0].size()):
				if without[0][k] != with_cast[0][k]:
					first = k
					break
		expect.call(same and with_cast[0].size() == 420 and with_cast[1],
			"cast (%s): engine bodies (every step) and panel texts are the same with and without the cast while Dugi explains" % id,
			"first difference at step %d" % first if not same else "%d steps" % with_cast[0].size())
