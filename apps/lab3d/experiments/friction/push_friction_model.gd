## Formula model of the push friction lab (Phase 1 Task 4b): the box on the level floor stepped with
## PushFrictionLaw (PhysicsLaws ports, 64-bit) under the applied force of each fixed step. It owns
## everything the panel shows about the motion (state, friction force, speed, displacement, heat);
## the engine box (Jolt + ContactFrictionCorrector, law "push") is only the "시뮬레이션" readout.
## Stepping rule = the corrector's on the engine (docs/formula-correction.md section 4): the law
## gives the net force on the state before the step, on the step that leaves rest only half of it
## acts (leapfrog start), then v += F/m dt, x += v dt. Friction = net - applied (the web's force
## breakdown); heat = -sum work(friction, step displacement) (mechanics.ts work). Checked against
## tests/friction_lab_vectors.json (tools/friction-lab-vectors.test.ts).
class_name PushFrictionModel
extends RefCounted

var mass := 8.0
var mu_s := 0.4
var mu_k := 0.22
var g := 9.81
## Applied force of the last step (N, + = towards +x).
var applied := 0.0
## PushFrictionLaw status of the last step (true before the first one).
var holding := true
## Friction force of the last step (N, signed; while holding = -applied).
var friction := 0.0
var velocity := 0.0       # m/s after the last step
var displacement := 0.0   # m from the start
var heat := 0.0           # J, friction work turned into heat since the start
var path := 0.0           # m slid (test-only: heat = mu_k m g x path) (sum of |step displacement|)
var steps := 0


func reset() -> void:
	applied = 0.0
	holding = true
	friction = 0.0
	velocity = 0.0
	displacement = 0.0
	heat = 0.0
	path = 0.0
	steps = 0


## Stops the box where it is (a bumper at the track end): no speed, the next step starts from rest.
func stop() -> void:
	velocity = 0.0
	holding = true


## One fixed step of `dt` s with `force` N applied along +x.
func step(force: float, dt: float) -> void:
	applied = force
	var was_holding := holding
	holding = PhysicsLaws.push_friction_holding(force, velocity, mass, mu_s, g)
	var net := PhysicsLaws.push_friction_force(force, velocity, mass, mu_s, mu_k, g, dt)
	var starting := was_holding and not holding and absf(velocity) < PhysicsLaws.PUSH_REST_SPEED
	velocity += (0.5 * net if starting else net) / mass * dt
	var dx := velocity * dt
	displacement += dx
	friction = net - force
	heat -= PhysicsLaws.work_1d(friction, dx)
	path += absf(dx)
	steps += 1


func max_static() -> float:
	return PhysicsLaws.push_max_static_force(mu_s, mass, g)


## Kinetic friction while sliding, mu_k m g (N).
func kinetic_friction() -> float:
	return PhysicsLaws.kinetic_friction_force(mu_k, PhysicsLaws.uniform_gravity_force(mass, g))


## Test-only (friction_lab_checks.gd); the panel does not show it.
func kinetic_energy() -> float:
	return PhysicsLaws.kinetic_energy(mass, absf(velocity))
