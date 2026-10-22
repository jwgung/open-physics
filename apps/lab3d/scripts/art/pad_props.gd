## Shared base of the props of the uniform-field labs (free fall, projectile): the yellow pad that
## holds a waiting ball and flips down around its hinge edge on release, and the reactions the
## lab triggers (released / reset). The labs' own props add their ruler, stand, arrow, ... on top.
class_name PadProps
extends RefCounted

const PAD_FLIP_S := 0.18
const PAD_MIN_HEIGHT := 0.05   # a ball resting lower than this (on the floor) needs no pad
const DUST_PER_BALL := 10      # dust grains per ball: three landings at once stay under the 32-grain budget

var _tweens: Dictionary = {}   # key -> the flip Tween of that pad


## A yellow pad slab centred at `at` (mesh space; the node origin is the hinge).
static func add_pad_slab(b: ArtMeshBuilder, at: Vector3, size: Vector3) -> void:
	b.add_rounded_box(Transform3D(Basis(), at), size, 0.02, 1, ArtPalette.YELLOW, ArtPalette.YELLOW_TOP)


## Flips `pad` down around its hinge (`property` of the node, to `angle` rad) and hides it.
## `key` names the pad (one flip at a time per key).
func flip_pad(key: Variant, pad: Node3D, property: String, angle: float) -> void:
	stop_flip(key)
	var tween := pad.create_tween()
	tween.tween_property(pad, property, angle, PAD_FLIP_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(pad.hide)
	_tweens[key] = tween


## Stops the running flip of `key` (a pad put back while it was still turning).
func stop_flip(key: Variant) -> void:
	var tween: Tween = _tweens.get(key)
	if tween != null and tween.is_valid():
		tween.kill()
	_tweens.erase(key)


## The lab let the balls go (override: pads flip, balls stretch).
func released() -> void:
	pass


## The balls were put back (override: they pop in again).
func reset() -> void:
	pass
