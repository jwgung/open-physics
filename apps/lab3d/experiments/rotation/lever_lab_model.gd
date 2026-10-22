## Formula model of the lever lab (Phase 1 Task 4e; web preset "rotation"): the web's LeverChallenge
## (src/app/mechanics-challenges.ts) on a 6 m beam. The fulcrum sits under the beam at pivot_x, the
## load at load_x (both dragged on a 0.25 m grid; the beam's centre stays at x = 0), and the effort
## point is one of the web's three points, a fraction 0.35 / 0.6 / 0.9 of the way from the fulcrum
## to the beam's right end. The red handle is a spring scale: each grid cell it is pressed down
## (FORCE_STEP newtons per cell) is that much more hand force.
## As in the web app, the force on the beam is the hand force capped at the required force
## F = m g r_load / r_effort (LeverChallenge.applyForce: lifting when it reaches it), and the beam
## lies level or turns to the web's lift angle 0.18 rad (load side up) - a quasi-static lever: at
## the required force the torques balance (m g r_load = F r_effort) and the beam is held lifted.
## Positions are world x / y (m, 64-bit) in the beam's vertical plane (z = 0).
class_name LeverLabModel
extends RefCounted

const LIFT_ANGLE := 0.18           # rad, the web's LEVER_LIFT_ANGLE
const FORCE_STEP := 5.0            # N per handle grid cell (the rule's snap, 0.02 m: 250 N/m)

var beam_half := 3.0               # m, half the beam length (beam centre at x = 0)
var pivot_x := -0.5                # world x of the fulcrum (the beam turns about it)
var pivot_y := 1.25                # world y of the beam's axis
var load_x := -2.5                 # world x of the load centre on the level beam
var load_up := 0.46                # m from the beam axis up to the load centre (rides with the beam)
var fraction := 0.6                # effort point: this fraction of the right arm (web 0.35 / 0.6 / 0.9)
var mass := 20.0
var g := 9.81
var cells := 0                     # handle grid cells pressed down


## r_load: fulcrum to load (m).
func load_arm() -> float:
	return pivot_x - load_x


## r_effort: fulcrum to the effort point (m).
func effort_arm() -> float:
	return fraction * (beam_half - pivot_x)


func effort_x() -> float:
	return pivot_x + effort_arm()


## F = m g r_load / r_effort (LeverChallenge.requiredForce).
func required() -> float:
	return PhysicsLaws.lever_required_force(mass, g, load_arm(), effort_arm())


## The spring scale's reading (N): FORCE_STEP per pressed cell.
func hand_force() -> float:
	return cells * FORCE_STEP


## Force on the beam (N): the hand force capped at the required force (the web's lever drag).
func applied() -> float:
	return minf(required(), hand_force())


func lifting() -> bool:
	return PhysicsLaws.lever_lifting(applied(), required())


## Beam angle (rad, about +z: negative = load side up).
func angle() -> float:
	return -LIFT_ANGLE if lifting() else 0.0


func advantage() -> float:
	return PhysicsLaws.lever_mechanical_advantage(load_arm(), effort_arm())


func weight() -> float:
	return PhysicsLaws.uniform_gravity_force(mass, g)


## Torque of the load's weight about the fulcrum (N m, counter-clockwise +): rotation.ts torque.
func load_torque() -> float:
	return PhysicsLaws.torque_2d(-load_arm(), 0.0, 0.0, -weight())


## Torque of the force on the beam at the effort point (N m, counter-clockwise +).
func effort_torque() -> float:
	return PhysicsLaws.torque_2d(effort_arm(), 0.0, 0.0, -applied())


## World x / y of a point `along` m along the level beam (world x) and `up` m above its axis,
## turned with the beam about the fulcrum (64-bit, no allocation).
func beam_x(along: float, up: float) -> float:
	var a := angle()
	return pivot_x + (along - pivot_x) * cos(a) - up * sin(a)


func beam_y(along: float, up: float) -> float:
	var a := angle()
	return pivot_y + (along - pivot_x) * sin(a) + up * cos(a)
