## Puppy (퍼피), the flag-bearer (Phase 1 Task 4h, art-direction.md section 12): the user's model
## assets/characters/puppy.glb (art_src/characters/puppy.py, no armature). He stands at the back of
## the island holding the app's flag "과학섬" (the app is "빵고양이 과학섬"), out of the way of the
## experiment. Only the banner moves: FlagCloth turns a little about the pole, a gentle wave. No
## body, no collision object, no layer.
##
## Draw nodes: Static (everything but the banner in one mesh), FlagCloth (pivot at the pole top where
## the banner is tied), plus a blob shadow; one storybook material (ArtKit.toon_material).
class_name PuppyActor
extends Node3D

const SCENE := preload("res://assets/characters/puppy.glb")
const WAVE_DEG := 7.0               # banner swing about the pole (deg) and its rate
const WAVE_HZ := 0.45
const FLUTTER := 0.3                # share of a faster second wave on top

var static_mesh: MeshInstance3D
var cloth: MeshInstance3D
var shadow: MeshInstance3D
## The pole's direction (from the paw to the pole top, puppy space): the banner turns about it.
var pole_axis := Vector3.UP
var _cloth_rest := Transform3D()
var _clock := 0.0
## The celebration (Plan G4: the last stamp of a round): a faster, larger wave for CELEBRATE_S.
var _celebrate_left := 0.0
const CELEBRATE_S := 2.0


## A bigger, faster flag wave for a moment (the puppy celebrates a cleared round).
func celebrate() -> void:
	_celebrate_left = CELEBRATE_S


func _init() -> void:
	name = "Puppy"
	var model: Node3D = SCENE.instantiate()
	var root := model.get_node("Puppy") as Node3D
	var body := root.get_node("Body") as MeshInstance3D
	var material := ArtKit.toon_material((body.mesh.surface_get_material(0) as BaseMaterial3D).albedo_texture)
	var banner := root.find_child("FlagCloth", true, false) as MeshInstance3D
	var st := SurfaceTool.new()
	for node in [body] + body.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi != banner:
			st.append_from(mi.mesh, 0, _model_xf(mi, root))
	static_mesh = MeshInstance3D.new()
	static_mesh.name = "Static"
	static_mesh.mesh = st.commit()
	add_child(static_mesh)
	cloth = MeshInstance3D.new()
	cloth.name = "FlagCloth"
	cloth.mesh = banner.mesh
	_cloth_rest = _model_xf(banner, root)
	cloth.transform = _cloth_rest
	add_child(cloth)
	var flag := banner.get_parent() as Node3D
	pole_axis = (_model_xf(flag, root).basis * banner.position).normalized()
	model.free()
	for mi: MeshInstance3D in [static_mesh, cloth]:
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var s := ArtKit.shadow_builder()
	s.add_blob(Transform3D(Basis(), Vector3(0.0, 0.012, 0.0)), 0.45, ArtKit.shadow_alpha(1.0))
	shadow = ArtKit.instance(s.commit(), ArtKit.shadow_material())
	shadow.name = "Shadow"
	add_child(shadow)


## A node's transform in the model root's space (the model is not in the tree).
static func _model_xf(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D()
	var n := node
	while n != root:
		xf = n.transform * xf
		n = n.get_parent() as Node3D
	return xf


## World AABB of the drawn meshes (not the shadow; the actor is in the tree).
func bounds() -> AABB:
	return IslandCast.drawn_bounds(self, shadow)


## The banner's turn about the pole now (rad; a celebration doubles the swing and speed).
func wave_angle() -> float:
	var w := TAU * WAVE_HZ * _clock
	var angle := deg_to_rad(WAVE_DEG) * (sin(w) + FLUTTER * sin(w * 2.3 + 0.8)) / (1.0 + FLUTTER)
	return angle * (2.0 if _celebrate_left > 0.0 else 1.0)


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	_clock += delta
	if _celebrate_left > 0.0:
		_celebrate_left -= delta
	cloth.transform = Transform3D(Basis(pole_axis, wave_angle()) * _cloth_rest.basis, _cloth_rest.origin)
