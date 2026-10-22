## Shared base of the uniform-field guided labs (Phase 1 Task 4a: free fall and projectile). Both
## drop or throw balls in the field chosen by the "gravity" control (the web's gravity buttons:
## 0, moon 1.62, earth 9.81, jupiter 24.79 m/s^2) and use the uniform-field formula correction
## (UniformFieldCorrector, docs/formula-correction.md section 4): Jolt integrates the field, the
## first released step gets the leapfrog half force, and the engine contact report ends the free
## flight. Every displayed number comes from PhysicsLaws; engine positions are only the graph's
## "시뮬레이션" points and the measured landing values.
## The field is the project gravity (physics/3d/default_gravity) times each ball's gravity_scale, so
## the corrector reads it from the engine on release; its 64-bit g is set to the chosen value first.
class_name UniformFieldLab
extends Experiment

const BALL_RADIUS := 0.25     # m (0.5 m balls, about the web's 24 px radius at 48 px = 1 m)
const GRAPH_EVERY_STEPS := 6  # graph sample every 6 fixed steps (10 Hz), like the incline

## Field the balls feel (m/s^2, downwards) and the selected gravity option id.
var g := 9.81
var gravity_id := "earth"
## The project's engine gravity; gravity_scale = g / engine_g.
var engine_g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.81)
var floor_body: StaticBody3D


## Selects a gravity option ({id, g} in the "gravity" control). False for an unknown id.
func set_gravity(option_id: String) -> bool:
	for control in definition.get("controls", []):
		if control.id != "gravity":
			continue
		for option in control.options:
			if option.id == option_id:
				g = float(option.g)
				gravity_id = option_id
				return true
	push_warning("%s: unknown gravity %s" % [definition.get("id", "?"), option_id])
	return false


## Puts the chosen field on a ball: engine gravity scale and the corrector's 64-bit strength.
func apply_field(ball: FormulaBody) -> void:
	ball.gravity_scale = g / engine_g
	(ball.corrector as UniformFieldCorrector).g = g


## Fixed-step length (s).
func step_dt() -> float:
	return 1.0 / float(Engine.physics_ticks_per_second)


## Graph window (s) from the definition.
func graph_x_max() -> float:
	return float(definition.get("graph", {}).get("x", {}).get("max", 3.0))


## Collision floor: the island's top surface at y = 0 (the island mesh is ArtKit's, no collision).
func make_floor(size: Vector3) -> StaticBody3D:
	floor_body = StaticBody3D.new()
	floor_body.name = "Floor"
	var material := PhysicsMaterial.new()
	material.friction = 0.6
	material.bounce = 0.0
	floor_body.physics_material_override = material
	_add_box_shape(floor_body, Vector3(size.x, 0.4, size.z))
	floor_body.position = Vector3(0.0, -0.2, 0.0)
	add_child(floor_body)
	return floor_body


## A ball for the uniform-field correction: sphere of BALL_RADIUS, no damping, no rotation (a toy
## ball that slides after landing; the free flight has no rotation anyway, and ArtJuice squashes
## along the surface normal), frozen until released, contact reports on (landing).
func make_ball(ball_name: String, mass: float, bounce: float) -> FormulaBody:
	var ball := FormulaBody.new()
	ball.name = ball_name
	ball.mass = mass
	ball.can_sleep = false
	ball.lock_rotation = true
	ball.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	ball.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	ball.linear_damp = 0.0
	ball.angular_damp = 0.0
	ball.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	ball.freeze = true
	ball.contact_monitor = true
	ball.max_contacts_reported = 4
	ball.collision_mask = 1   # the world (floor, other balls); handles on other layers are not hit
	var material := PhysicsMaterial.new()
	material.friction = 0.6
	material.bounce = bounce
	ball.physics_material_override = material
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = BALL_RADIUS
	shape.shape = sphere
	ball.add_child(shape)
	var corrector := UniformFieldCorrector.new()
	# The graph window (+ a sample at its end) is all the lab reads from the history.
	corrector.history_steps = int(graph_x_max() * Engine.physics_ticks_per_second) + 2
	ball.corrector = corrector
	return ball


## Stops a ball where it is (frozen, no velocity) with a fresh corrector history: not released.
static func hold_ball(ball: FormulaBody, at: Vector3) -> void:
	ball.freeze = true
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.global_position = at
	var corrector := ball.corrector as UniformFieldCorrector
	corrector.reset_history()
	corrector.offsets.clear()
	corrector.in_flight = false
	corrector.landed_step = -1
	corrector.origin = at
	corrector.initial_velocity = Vector3.ZERO


## Low-poly ball mesh (art-direction section 3: a sphere with 4 rings x 7 sides, one colour).
static func ball_mesh(color: Color) -> Mesh:
	var b := ArtKit.builder()
	b.ao_height = BALL_RADIUS * 1.2
	b.add_sphere(Transform3D.IDENTITY, BALL_RADIUS, 4, 7, color)
	return b.commit()
