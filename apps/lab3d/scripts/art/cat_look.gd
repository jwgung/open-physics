## The appearance a CatActor wears (Phase 1 Task 4g): its meshes and the few points of its body the
## acting uses. The acting (CatActor: holding, throwing, pushing, reactions, the sync with the
## formula model) reads only what is declared here, so a new look (another model, another way of
## modelling) replaces this class's subclass and nothing else.
##
## Space: the look's origin is the middle of its base on the floor, it faces +z, up +y. Arms turn at
## the shoulder only: an arm node's origin is the shoulder; in its rest pose its hand node (the paw
## centre, the grip point) is `hand_rest` from it; the paw's front (what touches a box) is `reach`
## from the shoulder along the same line.
class_name CatLook
extends RefCounted

## Shoulders (index 0 = the right paw at -x, 1 = the left paw at +x, which holds and throws).
var shoulders: Array[Vector3] = [Vector3(-0.25, 0.9, 0.2), Vector3(0.25, 0.9, 0.2)]
## Shoulder to the hand (paw centre) in the rest pose, per arm (rig space).
var hand_rest: Array[Vector3] = [Vector3(0.0, 0.1, 0.3), Vector3(0.0, 0.1, 0.3)]
## Shoulder to the hand (m) and to the paw's front (m).
var hand_reach := 0.32
var reach := 0.36
## Paw radius (m): tests keep a paw this far inside a face it touches.
var paw_radius := 0.1
## Head pivot (the head node's position).
var neck := Vector3(0.0, 1.0, 0.0)
## Footprint (x width, z depth) of the base: the stand under it and its shadow; height of its rim.
var footprint := Vector2(0.75, 0.57)
var rim := 0.76
## Direction from the holding shoulder to a held ball's centre (out to the side, so the ball hides
## neither the face nor the body seen from the front).
var hold_dir := Vector3(0.8, 0.3, 0.52)
## Rest direction of the right paw (mirrored in x for the left).
var rest_dir := Vector3(-0.05, -0.55, 0.83)


## Builds the drawn nodes under `rig` (the node the actor turns and hops) and returns them:
## {"body": Node3D, "head": Node3D (at `neck`), "eyes": Node3D (scaled in y to blink; may be null),
##  "tail", "tail2": Node3D (swayed at their origins; may be null), "arms": [right, left] (each at its
##  shoulder, rest pose), "hands": [right, left] (under the arms, at hand_rest)}. The actor adds the
## shadow.
func build(_rig: Node3D) -> Dictionary:
	return {}
