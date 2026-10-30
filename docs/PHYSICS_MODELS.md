# Open Physics — Physics Model Catalog

> **2026-10-30:** 웹 2D 앱을 지웠다([ADR 0002](adr/0002-drop-web-2d.md)). 이 문서는 공식 설명으로 남긴다. 공식의 코드는 정답 기준인 [`src/physics`](../src/README.md)에 있고, 3D 앱은 그 공식을 GDScript로 옮겨 쓴다. 아래의 "client-side simulation engine"은 지운 웹 엔진을 가리킨다.

> **Status:** Foundational physics specification
> **Purpose:** Define the equation-based physical models that the client-side simulation engine may implement.

## 1. Philosophy

Open Physics is an equation-driven visual simulation environment, not a general-purpose real-world physics engine.

Each simulation defines:

```text
State + Parameters + Conditions
        ↓
Physical Laws / Equations
        ↓
Numerical Solver
        ↓
Updated State
        ↓
Visualization
```

The equations below are the baseline model catalog. They are grouped by the product's content navigation, not by implementation order.

A model may be simplified by explicitly fixing assumptions such as constant gravity, ideal materials, ideal gases, geometric optics, or negligible air resistance.

## 2. Common Mechanics Models

### 2.1 Kinematics

Position, velocity, and acceleration:

```text
v = dx/dt
a = dv/dt = d²x/dt²
```

Uniform motion:

```text
x = x₀ + vt
```

Uniform acceleration:

```text
v = v₀ + at
x = x₀ + v₀t + ½at²
v² = v₀² + 2a(x - x₀)
```

### 2.2 Newtonian Dynamics

```text
ΣF = ma
```

Weight near a surface:

```text
Fg = mg
```

Spring force (Hooke's law):

```text
Fs = -kx
```

Kinetic friction:

```text
Ff = μk N
```

Static friction:

```text
Ff ≤ μs N
```

### 2.3 Momentum and Impulse

```text
p = mv
J = Δp = ∫F dt
```

For an isolated system:

```text
Σp_before = Σp_after
```

### 2.4 Work and Energy

Work by a constant force:

```text
W = F · Δx = FΔx cosθ
```

Kinetic energy:

```text
K = ½mv²
```

Gravitational potential energy near a surface:

```text
Ug = mgh
```

Spring potential energy:

```text
Us = ½kx²
```

Work-energy theorem:

```text
W_net = ΔK
```

Mechanical energy:

```text
E_mech = K + U
```

### 2.5 Circular Motion

```text
v = ωr
ac = v²/r = ω²r
Fc = mv²/r
```

Angular quantities:

```text
ω = dθ/dt
α = dω/dt
```

### 2.6 Rotation

Torque:

```text
τ = r × F
|τ| = rF sinθ
```

Angular momentum:

```text
L = Iω
```

Rotational dynamics:

```text
Στ = Iα
```

Rotational kinetic energy:

```text
K_rot = ½Iω²
```

### 2.7 Gravity and Orbits

Newton's law of universal gravitation:

```text
F = Gm₁m₂/r²
```

Gravitational potential energy:

```text
U = -Gm₁m₂/r
```

Circular orbit speed:

```text
v = √(GM/r)
```

Escape speed:

```text
v_escape = √(2GM/r)
```

### 2.8 Oscillation

Simple harmonic oscillator:

```text
F = -kx
ω = √(k/m)
T = 2π√(m/k)
f = 1/T
```

Simple pendulum (small-angle approximation):

```text
T = 2π√(L/g)
```

Damped oscillator, conceptual model:

```text
F_d = -bv
```

## 3. Electromagnetism

### 3.1 Charge and Coulomb Force

```text
F = k|q₁q₂|/r²
```

Vector form:

```text
F₁₂ = k q₁q₂ (r₁-r₂)/|r₁-r₂|³
```

Charge conservation:

```text
Σq = constant
```

### 3.2 Electric Field

Definition:

```text
E = F/q
```

Point charge:

```text
E = kq/r²
```

Superposition:

```text
E_total = ΣEᵢ
```

Force on a charge:

```text
F = qE
```

### 3.3 Electric Potential

```text
V = U/q
```

Point charge:

```text
V = kq/r
```

Potential energy:

```text
U = qV
```

Electric field and potential:

```text
E = -∇V
```

For a uniform field:

```text
ΔV = -E · Δr
```

### 3.4 Circuits

Current:

```text
I = ΔQ/Δt
```

Ohm's law:

```text
V = IR
```

Electrical power:

```text
P = VI = I²R = V²/R
```

Resistors in series:

```text
R_eq = ΣRᵢ
```

Resistors in parallel:

```text
1/R_eq = Σ(1/Rᵢ)
```

Kirchhoff's current law:

```text
ΣI_in = ΣI_out
```

Kirchhoff's voltage law:

```text
ΣΔV = 0
```

### 3.5 Capacitors

```text
C = Q/V
U = ½CV² = ½QV = Q²/(2C)
```

Parallel-plate capacitor:

```text
C = εA/d
```

### 3.6 Magnetic Field

Magnetic force on a moving charge:

```text
F = q(v × B)
```

Magnitude:

```text
F = qvB sinθ
```

Force on a current-carrying wire:

```text
F = I(L × B)
```

### 3.7 Electromagnetic Induction

Magnetic flux:

```text
Φ_B = ∫B · dA
```

Faraday's law:

```text
ε = -dΦ_B/dt
```

Lenz's law is represented by the negative sign: the induced effect opposes the change in flux.

## 4. Waves

### 4.1 Basic Wave Relations

```text
v = fλ
f = 1/T
ω = 2πf
k = 2π/λ
```

A simple traveling wave:

```text
y(x,t) = A sin(kx - ωt + φ)
```

### 4.2 Superposition and Interference

```text
y_total = y₁ + y₂ + ...
```

For coherent sources, path difference determines constructive/destructive interference.

Constructive:

```text
Δr = mλ
```

Destructive:

```text
Δr = (m + ½)λ
```

### 4.3 Standing Waves

A standing wave can be represented as the superposition of two opposite traveling waves:

```text
y = 2A sin(kx) cos(ωt)
```

For a string fixed at both ends:

```text
λ_n = 2L/n
f_n = nv/(2L)
```

### 4.4 Sound and Doppler Effect

For sound, the baseline model uses:

```text
v = fλ
```

Classical Doppler model:

```text
f' = f (v ± v_o)/(v ∓ v_s)
```

Signs depend on the relative direction of observer and source motion.

## 5. Light and Geometrical Optics

### 5.1 Reflection

Law of reflection:

```text
θ_i = θ_r
```

### 5.2 Refraction

Snell's law:

```text
n₁ sinθ₁ = n₂ sinθ₂
```

Refractive index:

```text
n = c/v
```

Critical angle for total internal reflection:

```text
sinθ_c = n₂/n₁   (n₁ > n₂)
```

### 5.3 Lenses and Mirrors

Thin-lens / spherical-mirror equation:

```text
1/f = 1/d_o + 1/d_i
```

Magnification:

```text
m = h_i/h_o = -d_i/d_o
```

Lens power:

```text
P = 1/f
```

with focal length expressed in meters for optical power in diopters.

### 5.4 Interference and Diffraction

Double-slit constructive interference:

```text
d sinθ = mλ
```

Single-slit diffraction minima:

```text
a sinθ = mλ
```

These models should be treated as wave-optics models rather than geometric-ray models.

### 5.5 Polarization

Malus's law:

```text
I = I₀ cos²θ
```

## 6. Thermal Physics

### 6.1 Temperature and Thermal Energy

Temperature is a state variable; microscopic particle motion may be visualized as a model rather than a literal molecular-scale simulation.

Heat transfer by temperature difference can use:

```text
Q = mcΔT
```

Latent heat:

```text
Q = mL
```

### 6.2 Ideal Gas

```text
PV = nRT
```

Equivalent particle form:

```text
PV = Nk_BT
```

Combined gas-law form for fixed amount of gas:

```text
P₁V₁/T₁ = P₂V₂/T₂
```

### 6.3 First Law of Thermodynamics

Using the convention that W is work done by the system:

```text
ΔU = Q - W
```

For an ideal monatomic gas:

```text
U = 3/2 nRT
```

### 6.4 Heat Transfer

Conduction can use a simplified one-dimensional model:

```text
Q̇ = kAΔT/L
```

Radiative heat transfer can use:

```text
P = εσAT⁴
```

or, for net exchange with surroundings:

```text
P_net = εσA(T⁴ - T_surroundings⁴)
```

## 7. Modern Physics

### 7.1 Special Relativity

Lorentz factor:

```text
γ = 1/√(1-v²/c²)
```

Time dilation:

```text
Δt = γΔt₀
```

Length contraction:

```text
L = L₀/γ
```

Mass-energy relation:

```text
E = mc²
```

Relativistic energy-momentum relation:

```text
E² = (pc)² + (mc²)²
```

### 7.2 Photons and Photoelectric Effect

Photon energy:

```text
E = hf = hc/λ
```

Photoelectric equation:

```text
K_max = hf - φ
```

Stopping potential:

```text
eV_s = K_max
```

### 7.3 Matter Waves

de Broglie relation:

```text
λ = h/p
```

### 7.4 Quantum Model

Time-dependent Schrödinger equation:

```text
iℏ ∂ψ/∂t = Ĥψ
```

Probability density:

```text
P(x) = |ψ(x)|²
```

Heisenberg uncertainty relation:

```text
Δx Δp ≥ ℏ/2
```

For introductory visualization, quantum models should generally visualize probability amplitudes/densities rather than pretend that a classical particle has a definite hidden trajectory.

### 7.5 Quantum Tunneling

For a simple rectangular barrier, the transmission probability may be modeled approximately using the relevant energy/barrier parameters. The exact approximation should be selected according to the regime being visualized rather than treated as a universal formula.

### 7.6 Atomic and Nuclear Physics

Photon emission/absorption between energy levels:

```text
ΔE = hf
```

Radioactive decay:

```text
N(t) = N₀e^(-λt)
```

Half-life:

```text
T₁/₂ = ln(2)/λ
```

Mass-energy relation for nuclear reactions:

```text
Q = Δmc²
```

### 7.7 Semiconductors

The semiconductor section should initially use simplified educational models rather than a full device-physics simulator.

Candidate models include:

```text
Band gap
Carrier concentration
p-n junction
Diode I-V characteristic
LED photon energy
Solar-cell energy conversion
```

The exact equations will be specified when semiconductor simulation is implemented.

## 8. Implementation Priorities

The model catalog is broader than the first implementation.

The initial engine should prioritize models that establish the reusable simulation architecture:

### Phase 1 — Core Mechanics

```text
Vectors
Position / Velocity / Acceleration
Newton's second law
Constant gravity
Spring force
Friction
Basic collision / contact
Work / Energy measurement
```

### Phase 2 — Extended Mechanics

```text
Momentum / Impulse
Circular motion
Rotation
Constraints
Oscillation
Universal gravitation
Orbital motion
```

### Phase 3 — Fields and Waves

```text
Charge
Coulomb force
Electric field
Electric potential
Basic circuits
Magnetic field / force
Wave propagation
Superposition
Interference
```

### Phase 4 — Optics and Thermal Physics

```text
Reflection
Refraction
Lenses
Diffraction
Polarization
Ideal gas
Heat transfer
Thermodynamics
```

### Phase 5 — Modern Physics

```text
Relativity
Photon models
Photoelectric effect
Matter waves
Quantum probability models
Nuclear decay
Semiconductor models
```

## 9. Modeling Rules

1. **Every implemented phenomenon must state its assumptions.**
2. **Equations are the source of behavior; animations should not fake the result.**
3. **A physical law must be independent from its numerical solver.**
4. **Units must be explicit and consistent internally.**
5. **Simplification is allowed when the assumptions are clear.**
6. **A model should expose the quantities that are useful for visualization and experimentation.**
7. **Content presets configure models; they do not duplicate model implementations.**
8. **Do not implement a more complicated physical model merely because it is more realistic if the simpler model better expresses the intended concept.**
