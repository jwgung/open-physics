## "Bread cat" look (Phase 1 Task 4g, apps/lab3d/docs/art-direction.md section 11) for a CatActor:
## the user's model assets/characters/bread_cat.glb (made in Blender by art_src/characters/bread_cat.py:
## a cheese-tabby cat with a "w" mouth in a kraft bakery bag, a baguette, a striped tail; one texture
## atlas, no armature). Only this file knows the model; the acting and its sync with the formula
## model are CatActor's.
##
## glb tree (each node's origin is its pivot; +z is the front, origin = the middle of the bag's
## bottom): BreadCat > Bag, Baguette, Body > Head, ArmL > HandL, ArmR > HandR, Tail > Tail2 > TailTip.
## build() makes 6 draw nodes under the actor's rig: Static (Bag + Baguette + Body merged into one
## mesh: they never move against each other), Head (nod / tilt at the neck), ArmR / ArmL (turned at
## the shoulder; HandL / HandR = the paw centre, the grip point), Tail and Tail2 (sway); with the
## actor's blob shadow the cat draws 7. Their
## material is the island light on the atlas (ArtKit.lit_texture_material), no engine lights.
class_name BreadCat
extends CatLook

const SCENE := preload("res://assets/characters/bread_cat.glb")
## Paw centre (HandL / HandR) to the paw's front along the arm (measured on the arm mesh: 0.039 m).
const PAW_FRONT := 0.039
## The paw's half width across the arm (a box face it touches keeps the paw this far inside).
const PAW_HALF := 0.045


func _init() -> void:
	var model: Node3D = SCENE.instantiate()
	var cat := model.get_node("BreadCat") as Node3D
	var body := cat.get_node("Body") as Node3D
	for i in 2:
		var arm := body.get_node("ArmR" if i == 0 else "ArmL") as Node3D
		var hand := arm.get_node("HandR" if i == 0 else "HandL") as Node3D
		shoulders[i] = body.position + arm.position
		hand_rest[i] = arm.basis * hand.position
	hand_reach = hand_rest[1].length()
	reach = hand_reach + PAW_FRONT
	paw_radius = PAW_HALF
	neck = body.position + (body.get_node("Head") as Node3D).position
	var bag := cat.get_node("Bag") as MeshInstance3D
	var box := bag.mesh.get_aabb()
	footprint = Vector2(box.size.x, box.size.z)
	rim = box.end.y
	# The ball where an overhand throw lets go (2026-10-23 user feedback: not below the arm): out to
	# the side beside the head (0.7 m wide), above the shoulder and a little forward. The launch point
	# is this hand: the cat is placed from it.
	hold_dir = Vector3(0.72, 0.45, 0.52)
	rest_dir = hand_rest[0].normalized()   # paws on the bag's rim, as modelled
	model.free()


func build(rig: Node3D) -> Dictionary:
	var model: Node3D = SCENE.instantiate()
	var cat := model.get_node("BreadCat") as Node3D
	var body := cat.get_node("Body") as MeshInstance3D
	var material := ArtKit.lit_texture_material((body.mesh.surface_get_material(0) as BaseMaterial3D).albedo_texture)
	# Bag, baguette and body: one mesh (one draw call).
	var st := SurfaceTool.new()
	for part: MeshInstance3D in [cat.get_node("Bag"), cat.get_node("Baguette"), body]:
		st.append_from(part.mesh, 0, part.transform)
	var static_mesh := MeshInstance3D.new()
	static_mesh.name = "Static"
	static_mesh.mesh = st.commit()
	rig.add_child(static_mesh)
	var arms: Array[Node3D] = []
	var hands: Array[Node3D] = []
	var parts := {"body": static_mesh, "eyes": null}
	for node_name in ["Head", "ArmR", "ArmL", "Tail"]:
		var node := body.get_node(node_name) as Node3D
		var rig_xf := body.transform * node.transform
		body.remove_child(node)
		for n in [node] + node.find_children("*", "", true, false):
			n.owner = null   # it leaves the model scene
		node.transform = rig_xf
		rig.add_child(node)
		match node_name:
			"Head":
				parts.head = node
			"Tail":
				parts.tail = node
				parts.tail2 = node.get_node("Tail2")
			_:
				arms.append(node)
				hands.append(node.get_node("HandR" if node_name == "ArmR" else "HandL"))
	parts.arms = arms
	parts.hands = hands
	model.free()
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = material
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return parts
