## Runs correctors that own several bodies (collision, kinematic models) once per fixed step,
## before the physics server steps. Add it to the experiment's tree; it runs while `running`.
class_name FormulaDriver
extends Node

var correctors: Array[FormulaCorrector] = []
var running := false


func _init() -> void:
	# Before the experiment's own _physics_process (lower priority value runs first).
	process_physics_priority = -10


func _physics_process(delta: float) -> void:
	if not running:
		return
	for corrector in correctors:
		corrector.step(delta)
