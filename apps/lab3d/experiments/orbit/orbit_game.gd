## The orbit's piece game (2026-10-29 "조각 꺼내기", batch B): the star piece floats far out in space,
## at HOME_R from the star on the side where a planet shot hard from 4 m along its circle leaves
## (a tangent launch past the escape speed √(2GM/r) = 3.67 m/s crosses HOME_R between about 41° and
## 53° round from its start). Stages 1 and 2 are laps (MissionRound: the formula's laps at 4 m, then
## two at 2 m): little sparkles sit on the stage's circle and pop when the formula planet passes them
## (a picture of the way round; the stamp is the laps'). Stage 3 asks for the planet to leave the star
## from 4 m (the state "far" on a launch past 3.67 m/s): when the leaving planet's formula position
## comes within ATTACH of the piece it takes the piece along, and the stamp lets it float there
## (released; the screen then flies it to the bread cat). A planet that leaves elsewhere leaves the
## piece where it floats and the stamp frees it there. Visual only: no body; the planet and every
## number are OrbitModel's as before.
class_name OrbitGame
extends LabGame

const HOME_R := 5.0
const HOME_DEG := 47.0                   # counter-clockwise from the planet's start (+x), seen from above
const ATTACH := 0.8                      # m: the leaving planet takes the piece within this
const RIDE_UP := 0.5                     # m: the taken piece rides this far over the planet
const SPARKLES := 8
const SPARKLE_R := 0.2
const COLLECT := 0.55                    # m: the formula planet pops a sparkle within this
const LAP_RADII := [4.0, 2.0]            # the lap stages' circles (orbit.json stages 1 and 2)

var plane_y := 2.0
var attached := false
var _sparkles: MultiMeshInstance3D
var _taken: Array[bool] = []
var _sparkle_radius := -1.0
var _glint_at := -10.0


func build() -> void:
	var b := ArtKit.builder()
	b.ao_min = 1.0
	b.add_sphere(Transform3D(Basis.from_scale(Vector3(1.0, 1.3, 1.0)), Vector3.ZERO), SPARKLE_R, 2, 4, ArtPalette.YELLOW_TOP)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = b.commit()
	mm.instance_count = SPARKLES
	_sparkles = MultiMeshInstance3D.new()
	_sparkles.name = "Sparkles"
	_sparkles.multimesh = mm
	_sparkles.material_override = ArtKit.lit_material()
	_sparkles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sparkles)
	_taken.resize(SPARKLES)
	make_piece(home(), PIECE_SIZE * 1.45)   # far off in the top view: bigger (more reaches Puppy on the view, tests/island_cast_checks.gd)
	_jump(0)


## Where the piece floats (the lab's own axes, the star at the origin): HOME_R from the star at HOME_DEG, in the orbit plane.
func home() -> Vector3:
	var a := deg_to_rad(HOME_DEG)
	return Vector3(HOME_R * cos(a), plane_y, -HOME_R * sin(a))


## The sparkles on the lap stage's circle (radius 0: none), all back in place.
func _lay_sparkles(radius: float) -> void:
	_sparkle_radius = radius
	_sparkles.visible = radius > 0.0
	for i in SPARKLES:
		_taken[i] = false
		_set_sparkle(i)


func _sparkle_at(i: int) -> Vector3:
	var a := TAU * (i + 0.5) / SPARKLES
	return Vector3(_sparkle_radius * cos(a), plane_y, -_sparkle_radius * sin(a))


func _set_sparkle(i: int) -> void:
	var s := 0.0 if _taken[i] else 1.0 + 0.15 * sin(_t * 4.0 + i)
	_sparkles.multimesh.set_instance_transform(i, Transform3D(Basis(Vector3.UP, _t * 1.5 + i).scaled(Vector3.ONE * maxf(s, 0.001)), _sparkle_at(i)))


## The sparkles popped by the formula planet so far (tests).
func sparkles_taken() -> int:
	return _taken.count(true)


func _cleared(_stage_index: int, last: bool) -> void:
	_glint_at = _t
	if last:
		# Released where it is now: riding the planet, or still floating at its home.
		_rest_at = piece.global_position
		piece_state = "out"
		SoundBoard.play(&"glint")
		_lay_sparkles(0.0)
		return
	_lay_sparkles(_lap_radius())
	SoundBoard.play(&"glint")


func _lap_radius() -> float:
	return float(LAP_RADII[stage]) if stage < LAP_RADII.size() else 0.0


func _jump(stamps: int) -> void:
	attached = false
	if stamps < stages and piece != null and piece_state != "taken":
		piece.position = home()
		set_piece_state("held")
	if _sparkles != null:
		_lay_sparkles(_lap_radius() if stamps < stages else 0.0)


## The leaving planet takes the piece: the last stage's run, launched from its circle (the stage's
## conditions), the formula planet unbound and within ATTACH of the piece.
func _try_attach(orbit_lab: Variant) -> void:
	if attached or stage != stages - 1 or piece_state != "held" or orbit_lab.status() != "leaving":
		return
	var stages_list: Array = MissionRound.missions(lab.definition).get("stages", [])
	if stage < stages_list.size() and not MissionRound.conditions_met(stages_list[stage].get("conditions", {}), lab):
		return
	if orbit_lab.planet.global_position.distance_to(piece.global_position) <= ATTACH:
		attached = true
		SoundBoard.play(&"glint")


func _process(delta: float) -> void:
	super(delta)
	var orbit_lab: Variant = host()
	if orbit_lab == null or piece == null:
		return
	if _sparkles.visible:
		var running: bool = orbit_lab.released and orbit_lab.holding == ""
		for i in SPARKLES:
			if running and not _taken[i] and orbit_lab.planet.position.distance_to(_sparkle_at(i)) <= COLLECT:
				_taken[i] = true
			_set_sparkle(i)
	if piece_state == "held":
		if orbit_lab.released and orbit_lab.holding == "":
			_try_attach(orbit_lab)
		if attached:
			piece.global_position = orbit_lab.planet.global_position + Vector3.UP * RIDE_UP
		else:
			piece.position = home() + Vector3.UP * (0.08 * sin(_t * 1.7) + absf(wobble(_t, _glint_at, 0.25, 0.6)))


## The clue's glow (LabGame.highlight): a halo on the far piece in space.
func highlight_radius() -> float:
	return 0.9
