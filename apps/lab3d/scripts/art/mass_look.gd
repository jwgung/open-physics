## How big a body looks for its mass (2026-10-28 user request "무게에 따라 크기가 달라지게": two 1 kg
## balls looked different, a heavier one was not bigger). Bodies of one stuff have one density, so
## the drawn size follows the cube root of the mass: twice the size is 8 times the mass, and equal
## masses look equal. Visual only: the labs keep their bodies, collision shapes and formula models
## (the mesh grows from the body's contact point, ArtJuice.look_scale). No lab needs a clamp: their
## mass ranges stay within a size ratio of 2.8 (0.5-10 kg collision, 2-10 kg friction, 1-20 kg
## lever and pulley), so every order and equality is the cube root's own.
## The buoyancy drum is not here: its size is its volume (큰 통 / 작은 통); its mass is the weight on
## its lid (BuoyancyProps).
class_name MassLook
extends RefCounted


## Size of a body of `mass` against one of `reference` mass of the same stuff: (m / m_ref)^(1/3).
static func factor(mass: float, reference: float) -> float:
	return pow(mass / reference, 1.0 / 3.0)


## Radii (a, b) of two balls of one stuff resting on one floor that touch exactly when their centres
## are `reach` apart along it (the collision lab's model contact, radius_a + radius_b). Resting on the
## floor, balls of radii a and b touch at a horizontal distance 2 sqrt(a b); with a / b the cube root
## of the mass ratio that gives a = reach / 2 (m_a / m_b)^(1/6). Equal masses: reach / 2 each.
static func touching_radii(mass_a: float, mass_b: float, reach: float) -> Vector2:
	var q := pow(mass_a / mass_b, 1.0 / 6.0)
	return Vector2(0.5 * reach * q, 0.5 * reach / q)
