## The collision's piece game (2026-10-29 "조각 꺼내기"): the star piece is frozen in an ice block on
## the right bumper, where the orange ball ends its run. A stage asks for the orange ball to leave
## a hard enough push (MissionTracker: impulse_b, the formula's J_B = m_B Δv_B the orange ball gets in
## the hit, past 6.5 → 12 → 18 N·s since 2026-10-29; before: its speed after the hit). The ice shakes whenever the formula orange ball reaches the bumper (knock);
## a stamp cracks it (stages 1 and 2) at that knock, and the last one breaks it: the chunks and the
## piece fly out on uniform gravity (LabGame.launch_piece). Visual only: the ice is a picture on the
## bumper (no body), the balls and the numbers are CollisionModel's as before.
class_name CollisionGame
extends LabGame

const ICE := 0.85                        # m, the ice block's side (0.72 until 2026-10-29)
const ICE_COLOR := Color(0.78, 0.93, 1.0, 0.62)
const CRACK := Color("2f6fb8")           # deep blue on the pale ice (white read poorly, 2026-10-29)
const CHUNKS := 8
const BREAK_S := 0.7
const KNOCK_WAIT_S := 1.6                # a stamp with no knock yet (the ball still rolling) waits this long

var bumper: Node3D                       # the right bumper (CollisionProps.bumper_right): the ice sits on it
var _ice: Node3D
var _block: MeshInstance3D
var _cracks: MeshInstance3D              # the stamps' cracks on the front face (one mesh per count)
var _chunks: MeshInstance3D
var _chunk_from := Vector3.ZERO
var _knocked_at := -10.0
var _shake := 0.0
var _pending := -1                       # a stage cleared before the ball reached the ice (its index)
var _pending_since := 0.0
var _pending_last := false
var _broken_at := -1.0


func build() -> void:
	_ice = Node3D.new()
	_ice.name = "Ice"
	add_child(_ice)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var b := ArtKit.builder()
	b.ao_min = 0.9
	b.add_rounded_box(Transform3D(Basis(), Vector3(0.0, ICE * 0.5, 0.0)), Vector3.ONE * ICE, 0.08, 1, ICE_COLOR, Color(0.9, 0.98, 1.0, 0.62))
	_block = ArtKit.instance(b.commit(), material)
	_block.name = "Block"
	_ice.add_child(_block)
	_cracks = ArtKit.instance(crack_mesh(1))
	_cracks.name = "Cracks"
	_cracks.visible = false
	_ice.add_child(_cracks)
	# The chunks of the broken ice: one mesh that bursts out (it grows apart, falls and shrinks).
	var cb := ArtKit.builder()
	for i in CHUNKS:
		var a := TAU * i / CHUNKS
		cb.add_rounded_box(Transform3D(Basis(Vector3.UP, a), Vector3(cos(a), 0.4 * sin(a * 2.0), sin(a)) * ICE * 0.3), Vector3.ONE * ICE * 0.3, 0.03, 1, ICE_COLOR)
	_chunks = ArtKit.instance(cb.commit(), material)
	_chunks.name = "Chunks"
	_chunks.visible = false
	add_child(_chunks)
	make_piece(Vector3.ZERO, PIECE_SIZE * 0.9)
	piece.reparent(_ice, false)
	piece.position = Vector3(0.0, ICE * 0.5, 0.0)
	_jump(0)


## The formula orange ball reached the bumper at `speed` (m/s): the ice shakes (harder when faster);
## a stamp that came before the ball got here cracks or breaks it now.
func knock(speed: float) -> void:
	_knocked_at = _t
	_shake = clampf(speed / 13.0, 0.25, 1.0)
	if _pending >= 0:
		_crack(_pending, _pending_last)
		_pending = -1


func _cleared(stage_index: int, last: bool) -> void:
	if _t - _knocked_at < 0.6:
		_crack(stage_index, last)   # the ball is at the ice now (or just was)
	else:
		_pending = stage_index
		_pending_last = last
		_pending_since = _t


func _crack(stage_index: int, last: bool) -> void:
	if last:
		_break()
		return
	_show_cracks(stage_index + 1)
	SoundBoard.play(&"star_break")


func _show_cracks(count: int) -> void:
	_cracks.visible = count > 0
	if count > 0:
		_cracks.mesh = crack_mesh(count)


static var _crack_meshes := {}


## White zigzags on the ice's front face: the first `count` of two.
static func crack_mesh(count: int) -> Mesh:
	if _crack_meshes.has(count):
		return _crack_meshes[count]
	var c := ArtKit.builder()
	c.ao_min = 1.0
	var lines: Array = [[Vector2(-0.3, 0.62), Vector2(-0.1, 0.45), Vector2(-0.18, 0.3), Vector2(0.05, 0.12)],
		[Vector2(0.32, 0.55), Vector2(0.12, 0.42), Vector2(0.2, 0.25), Vector2(-0.05, 0.08), Vector2(0.1, 0.02)]]
	for set_i in mini(count, lines.size()):
		var points: Array = lines[set_i]
		for k in points.size() - 1:
			var p0: Vector2 = points[k] * (ICE / 0.72)
			var p1: Vector2 = points[k + 1] * (ICE / 0.72)
			var mid := (p0 + p1) * 0.5
			var seg := p1 - p0
			var xf := Transform3D(Basis(Vector3.BACK, atan2(seg.y, seg.x)), Vector3(mid.x, mid.y, ICE * 0.5 + 0.006))
			c.add_rounded_box(xf, Vector3(seg.length() + 0.03, 0.04, 0.012), 0.0, 1, CRACK)
	_crack_meshes[count] = c.commit()
	return _crack_meshes[count]


func _break() -> void:
	if _broken_at >= 0.0:
		return
	_broken_at = _t
	_block.visible = false
	_cracks.visible = false
	_chunk_from = _ice.global_position + Vector3.UP * ICE * 0.5
	_chunks.visible = true
	_chunks.global_position = _chunk_from
	_chunks.scale = Vector3.ONE
	piece.reparent(self, true)
	launch_piece(Vector3(1.2, 3.2, 0.6), 9.81)
	SoundBoard.play(&"star_break")


## The ice after `stamps` stamps: whole (and cracked once or twice), or gone once the round is done.
func _jump(stamps: int) -> void:
	_pending = -1
	_broken_at = -1.0
	_chunks.visible = false
	var done := stamps >= stages
	_block.visible = not done
	_show_cracks(0 if done else stamps)
	if not done and piece != null and piece_state != "held":
		piece.reparent(_ice, false)
		piece.position = Vector3(0.0, ICE * 0.5, 0.0)
		piece.rotation = Vector3.ZERO
		set_piece_state("held")


func _process(delta: float) -> void:
	super(delta)
	if bumper != null and _ice != null:
		# On the bumper's top (the bumper moves with the orange ball's look).
		var shake := wobble(_t, _knocked_at, 0.05 * _shake, 0.5)
		_ice.position = bumper.position + Vector3(0.15 + shake, 0.6, 0.0)
		_ice.rotation.z = shake * 1.5
	if _pending >= 0 and _t - _pending_since > KNOCK_WAIT_S:
		knock(0.0)   # the ball never got there (stopped on the rail): crack it anyway
	if _broken_at >= 0.0 and _chunks.visible:
		# The burst: the chunks spread (the mesh grows from the ice's middle) and fall on g, shrinking away.
		var k := (_t - _broken_at) / BREAK_S
		var tt := _t - _broken_at
		_chunks.global_position = _chunk_from + Vector3(0.6 * tt, 2.4 * tt - 0.5 * 9.81 * tt * tt, 0.0)
		_chunks.scale = Vector3.ONE * (1.0 + 1.4 * k) * maxf(0.01, 1.0 - k * k)
		if k >= 1.0:
			_chunks.visible = false


## The clue's glow (LabGame.highlight): a halo on the ice block (the piece is frozen in it).
func highlight_radius() -> float:
	return 0.75
