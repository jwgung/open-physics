# 공식 보정 계층 (Phase 1 Task 3)

역학 안내형 실험은 Jolt 위에서 움직이지만, 핵심 운동과 화면 수치는 TS 공식 코어(`src/physics/laws/` 등)와 같아야 한다. 이 문서는 Godot 4.7.2 + Jolt에서 공식값을 강제할 수 있는 지점과 한계(조사), 실험 10개를 어떤 보정 방식으로 처리할지(설계), 그리고 그것을 지키는 테스트를 정리한다. 용어는 [CONTEXT.md](../../../CONTEXT.md) "Formula Correction(공식 보정)"을 따른다.

코드는 `scripts/formula/`(보정 계층)와 `scripts/core/physics_laws.gd`(TS 공식 포트)에 있다. 실험 화면·콘텐츠는 Task 4에서 이 계층 위에 만든다.

## 1. 원칙

- **화면 수치는 공식에서 나온다.** 보정기의 `formula_values()`는 `PhysicsLaws`로만 계산한다. 엔진 측정값(`engine_values()`, 기록 `samples`)은 "(시뮬레이션)" 표시가 붙은 관찰값이나 그래프의 측정 점으로만 보여 준다. 웹 2D의 관찰값 중 엔진 상태가 필요한 값(예: 용수철의 지금 늘어난 길이)은 측정한 상태를 공식에 넣어 계산한다.
- **움직임을 공식에 맞춘다.** 숫자만 공식으로 바꾸고 움직임은 엔진 근사로 두지 않는다. 방식별로 핵심 운동(아래 4절 표의 "핵심 운동")을 대표 장면 테스트로 지킨다.
- **보정은 물리 서버 스텝 전에 한다.** 보정기는 고정 스텝(60 Hz)마다 `_physics_process`에서 한 번 실행된다(`FormulaBody`, `FormulaDriver`). 이유는 2절.
- **공식은 64비트 스칼라로 계산한다.** GDScript `float`는 64비트지만 `Vector3`는 32비트다. `PhysicsLaws`는 스칼라만 받고 돌려준다. 엔진 위치·속도(32비트)는 측정값으로만 쓴다.

## 2. Jolt 조사 (Godot 4.7.2, 헤드리스 실험)

작은 헤드리스 실험 프로젝트 [`spikes/jolt-probes/`](../../../spikes/jolt-probes/)(Jolt, 60 Hz, `--fixed-fps 60`, `run.sh`로 전부 실행)로 확인했다. 수치는 그 실행 결과다.

| 항목 | 확인한 동작 | 보정에 주는 뜻 |
|---|---|---|
| 콜백 순서 | 한 프레임에 `_physics_process`(스텝 k 전) → Jolt 스텝 → `_integrate_forces`(스텝 k 직후 상태) 순서다. 스텝 3의 `_physics_process`에서 넣은 힘·충격량·속도는 다음 `_physics_process`에서 이미 반영돼 있고, 스텝 3의 `_integrate_forces`에서 넣은 힘은 한 스텝 늦게 반영된다(측정: 속도 변화가 스텝 4가 아니라 5에 보임). `_integrate_forces`에서 정한 속도는 다음 스텝에 쓰인다 | 공식 힘은 `_physics_process`에서 넣는다. `_integrate_forces`는 "스텝 직후" 상태를 읽는 곳이다. 놓는 스텝에 바로 보정하려면 같은 `_physics_process`에서 해야 한다(Task 2a 빗면과 같은 결론) |
| 적분 | 중력만 받는 바디: k 스텝 뒤 v = −g k dt, y = −g dt² k(k+1)/2(측정 비율 1.000, 3.000, 6.000, 10.00 …). 즉 반암시적(symplectic) 오일러 | 정지·등가속 출발은 공식 ½at²보다 ½a t dt 앞선다(t = 1 s에서 8 cm). 첫 스텝에 알짜힘의 절반만 주면(도약 출발, leapfrog) 스텝 위치가 정확히 x₀ + v₀t + ½at²가 된다. 힘이 위치에 따라 바뀌면 같은 처리로 속도 Verlet가 돼 주기 오차 O((ωdt)²), 에너지 표류 없음 |
| 정밀도 | `Vector3`·바디 상태는 32비트(10 m 근처 위치 분해능 ~1e-6 m) | 엔진 위치 비교 허용 오차는 1e-5~1e-4 m. 공식 parity(1e-9)는 스칼라 포트로만 한다 |
| `custom_integrator` | 켜면 엔진이 중력·감쇠를 더하지 않고, 정한 속도로 위치만 적분한다(측정: 콜백에서 반 중력만 더하면 그만큼만 빨라짐) | 쓸 수는 있지만 `_integrate_forces`가 스텝 뒤라 한 스텝 늦다. 지금 방식들에는 필요 없다 |
| 접촉 보고 | `contact_monitor` + `max_contacts_reported`일 때 `_integrate_forces`의 상태에서 접촉 수·위치·법선·충격량을 읽는다. 바닥에 놓인 2 kg 상자: 접촉 4개, 충격량 합 0.32712(= m g dt 0.32700의 +0.04%), 기본 마찰 탓 접선 성분 ~0.003. `body_entered`는 닿은 스텝에 한 번. `get_contact_count()`는 바로 전 스텝 기준 | 접촉 여부 판정(자유 비행 끝, 충돌 감지)에는 쓸 만하다. 엔진 법선력·충격량을 그대로 표시값으로 쓰지는 않는다(공식 N = mg cosθ 등을 쓴다) |
| 반발 | 두 재질의 `bounce`를 **더해서 1로 자른다**(0.44 + 0.44 → e 0.88, 0.5 + 0.5 → 1, 0.88 + 0 → 0.88). TS는 min(eA, eB). 닫히는 속도 1 m/s(`bounce_velocity_threshold`) 아래는 e = 0(0.7 m/s 접근 → 완전 비탄성). 정면 충돌 결과는 공식과 5자리까지 같다(1 kg 3.4 m/s ↔ 2 kg −1.7 m/s, e = 0.88 → −2.992 / 1.496) | TS의 임계 속도(48 px/s = 1 m/s)와 Jolt 기본값이 같다. 재질은 바꾸지 않는다(바꾸면 바닥·벽 반발과 마찰까지 바뀐다). 두 공의 접촉 결과만 공식 결과로 덮어쓴다. 반발 0 재질 쌍은 추측 접촉(닿기 직전 스텝에 닫히는 속도를 간격/dt로 줄임) → 다음 스텝 충돌로 **두 스텝에 걸쳐** 해결되므로, 보정기는 접촉이 시작되기 전 속도를 접촉이 끝날 때까지 보관한다 |
| 마찰 | Coulomb 계수 하나뿐(정지·운동 구분 없음), 재질 결합도 엔진 규칙 | 엔진 마찰 0 + 공식 마찰력 주입(Task 2a S3, 그대로 유지) |
| `PinJoint3D` 진자 | L = 2 m, 10° 진폭: 주기 2.8444 s(유한 진폭 공식 2.8424 s 대비 +0.07%), 길이 오차 최대 0.07 mm, 진폭이 30초에 9.99° → 9.87°(−1.3%)로 줄어든다(제약 솔버의 감쇠) | 웹 진자 모델은 감쇠(줄 0.06, 막대 0.03 /s)를 직접 지정하고 각도를 그래프로 보여 준다. 조인트로는 그 감쇠·각도 곡선을 재현할 수 없다. 진자는 모델을 고정 스텝으로 돌리고 추를 키네마틱으로 놓는다 |
| `Generic6DOFJoint3D` 선형 스프링 | k = 5, m = 1: 주기는 공식 대비 +0.04%지만 에너지가 0.118–0.624 J(공식 0.625 J)로 흔들리며 줄어든다. 평형점은 관절 생성 때의 상대 위치 기준(`equilibrium_point`로 옮겨야 움직인다) | 용수철은 Hooke 힘을 공식으로 주입한다 |
| `HingeJoint3D`·`SliderJoint3D` | 수치로 측정하지 않았다. Pin·6DOF와 같은 Jolt 제약 솔버(속도 10회·위치 2회 반복, Baumgarte 0.2)를 쓴다 | 지렛대·도르래는 웹에서도 운동이 아니라 평형 판정이라 모델 구동으로 충분하다. 빈 실험실(Task 5)에서 조인트를 쓸 때 따로 측정한다 |
| 고정 스텝·결정성 | `physics_ticks_per_second = 60`, 헤드리스 `--fixed-fps 60`에서 같은 입력은 같은 결과(빗면 기록 해시가 실행마다 같다) | 테스트를 엔진 스텝 수로 판정한다(렌더링 FPS와 무관) |

관련 프로젝트 설정 기본값: `physics/jolt_physics_3d/simulation/velocity_steps = 10`, `position_steps = 2`, `baumgarte_stabilization_factor = 0.2`, `penetration_slop = 0.02`, `speculative_contact_distance = 0.02`, `bounce_velocity_threshold = 1.0`. 바닥에 놓인 무거운 상자는 약 2 cm 파고든다(부력 장면의 3 kg 상자 y −2.82, 기대 −2.80).

### 엔진 위에서 공식값을 강제할 수 있는 지점

1. `_physics_process`의 힘·충격량(같은 스텝에 반영) — 접촉 힘 보정, 힘 주입, 도약 출발.
2. `_physics_process`의 속도 설정(같은 스텝에 반영) — 충돌 결과 덮어쓰기.
3. 키네마틱 바디의 변환 설정(Jolt가 그 스텝에 옮기며 다른 바디를 민다) — 해석 모델 구동.
4. 재질(`friction` 0) — 접촉 힘 보정에서 엔진 마찰을 끈다. 충돌 보정은 재질을 바꾸지 않는다(바닥·벽 접촉이 같이 바뀌므로).

### 한계

- 접촉 힘 보정은 **알려진 평면 하나** 위의 한 바디만 다룬다(빗면, 바닥 밀기). 일반 다접촉 마찰(빈 실험실)은 아니다.
- 충돌 보정은 알려진 두 바디(구)의 정면·비스듬한 충돌만 다룬다. 접촉 스텝의 위치는 엔진 결과로 움직인다(스텝마다 오차 ≤ |Δv| dt). **충돌 판정**은 엔진 접촉 보고다: A의 `get_colliding_bodies()`에 B가 새로 들어온 스텝(보고는 바로 전 스텝 기준)을 충돌 시작으로 보고, 그 스텝을 시작할 때의 속도를 보관한다(`setup()`이 두 바디의 `contact_monitor`를 켠다). 벽·바닥 충격, `apply_*` 힘처럼 A–B 접촉이 아닌 속도 변화는 판정에 쓰이지 않는다. 보정하지 않고 엔진 결과를 두는 경우: (1) 같은 스텝에 A나 B가 다른 바디(벽, 바닥, 세 번째 공)와도 새로 닿음 — 충격량을 나눌 수 없다. 계속 닿아 있는 바닥(굴러가는 공)은 막지 않는다. (2) 지속 접촉 — 마지막 접촉 뒤 표면이 5 cm 넘게 떨어진 적이 없고 닫히는 속도가 반발 임계(1 m/s) 미만(서로 눌린 채 미는 쌍, 접촉 보고가 깜박이는 경우). 반발 임계 미만의 느린 첫 접촉(떨어져 있다 닿음)은 보정한다(TS e = 0). 접촉 스텝 동안 더하는 외력 Δv는 **A–B 접촉이 없던 마지막 스텝의 실제 속도 변화**다(중력, 계속 닿은 바닥의 지지, `constant_force`, 매 스텝 주는 `apply_*` 힘과 감쇠가 다 들어간다. 접촉 동안 힘이 같다고 보는 근사). 그런 스텝이 아직 없으면(놓자마자 닿음) 엔진 중력 + `constant_force`다. 그 마지막 비접촉 스텝에 바닥·벽에 튕겼다면 그 충격도 들어간다. 접촉이 끝나는 기준은 법선 상대 속도가 더는 닫히지 않거나 보고에서 B가 빠질 때이고, 스텝 상한은 없다. 밀기 모드의 첫 스텝 절반 규칙은 밀기 정지 임계(`PUSH_REST_SPEED`)를, 빗면은 2a 임계(0.01)를 쓴다.
- 용수철 감쇠(−bv)와 부력 끌림(−drag f m v)은 엔진의 `linear_velocity`를 쓴다. 이 값은 symplectic Euler에서 v_(k−1/2), 위치보다 반 스텝 늦은 속도다. 위치 차분 (x_k − x_(k−1))/dt도 같은 값이라 바꿔도 나아지지 않고, 스텝 시점 속도(`synced_velocity`)는 그 힘 자체가 필요해 암시적 풀이가 된다. 그래서 그대로 둔다: 감쇠율·끌림은 dt 1차 정확도(b dt = 0.0075, 끌림 1.8 × dt = 0.03 정도의 상대 차)이고, 표시 수치(에너지, 뜨는 비율)는 이 값에 기대지 않는다.
- 균일장 보정의 착지는 엔진 접촉 보고(`get_colliding_bodies()`)로 판정한다: 출발 때 닿아 있지 않던 바디와의 접촉, 또는 출발 때 닿아 있던 면과 한 번 떨어진 뒤 다시 닿음. 바닥에서 던지거나 테이블 가장자리에서 아래 성분이 있는 속도로 밀어 낸 물체는 출발 면으로 착지하지 않는다. 바닥에 놓은 채 v₀ = 0으로 놓으면 착지하지 않고 시간이 계속 간다. `contact_monitor`가 꺼져 있으면 `release()`가 켜고, 그 스텝의 보고가 없으므로 첫 스텝 뒤 보고를 출발 접촉으로 쓴다(이때 첫 스텝 안에 새로 닿은 면도 출발 면으로 본다). 표시 공식의 g·방향은 `release()` 때 바디에 걸린 엔진 장(`get_gravity() × gravity_scale`, 영역 중력 포함)이다. 크기가 설정값과 float32 반올림만큼만 다르면 64비트 설정값(9.81)을 그대로 쓴다. 놓은 뒤 장이 바뀌는 경우(영역 경계를 넘음)는 다루지 않는다.
- `PhysicsLaws`의 밀기 마찰 정지 임계는 TS(0.01 px/s)를 m/s로 바꾼 0.01/48 m/s다. 빗면 `corrected_tangential_force`의 0.01은 Task 2a 측정 기준 그대로 두었다(빗면 수치 불변).
- 키네마틱 구동 바디는 힘을 받지 않는다(진자 추를 다른 물체가 밀어도 추는 모델대로 움직인다). 웹 2D도 같다.
- 부력의 잠긴 비율은 깊이에 선형이다(TS `BuoyancyRegionLaw`). 3D에서는 세운 각기둥(상자)에서만 부피와 정확히 같다. 3D 실험은 상자 또는 원기둥을 쓴다(구를 쓰면 표시는 공식, 움직임은 선형 근사).
- 엔진 동작 의존: 콜백 순서·적분 방식·반발 결합 규칙은 문서화된 계약이 아니다. Godot·Jolt를 올릴 때 `build.sh test`의 대표 장면이 깨져 알려 주고, 원인은 `spikes/jolt-probes/run.sh`(수동, CI 밖)로 다시 잰다.

## 3. 공통 인터페이스 (`scripts/formula/`)

| 부품 | 역할 |
|---|---|
| `FormulaCorrector` | 기반 클래스. `method`(방식 id, `METHODS` 중 하나), `steps`, 제한된 기록 `samples`·`velocities`(`history_steps`까지, 같은 길이로 인덱스가 맞고 속도 없는 샘플은 NAN)·`last_sample`·`last_velocity`, `record(value, velocity?)`, 한 고정 스텝 `step(dt)` / 바디가 부르는 `apply(body, dt)`, 표시값 `formula_values()`, 측정값 `engine_values()`, 도약 출발 `leapfrog_start`와 그 계수 `start_factor(first_step)`(첫 스텝 0.5, 세 보정기 공용) |
| `FormulaBody` | `RigidBody3D`. 얼려 있지 않으면 매 `_physics_process`에서 `corrector.apply(self, dt)` |
| `FormulaDriver` | 여러 바디를 다루는 보정기(충돌, 모델 구동)를 매 스텝 실행하는 노드. `running`일 때만, 실험 노드보다 먼저(`process_physics_priority = -10`) |
| 리셋 | 방식마다 `reset(origin/body)`·`release(body, v0)`·`attach(body)`·`setup(a, b, …)`로 기록과 상태를 초기화하고, 놓는 스텝부터 보정한다 |

| 방식 (`method`) | 클래스 | 하는 일 |
|---|---|---|
| 접촉 힘 보정 (`contact_force`) | `ContactFrictionCorrector`(빗면: `InclineFrictionCorrector`, `incline`은 `surface`의 다른 이름) | 엔진 마찰 0, 공식 마찰력(정지·운동, 법칙 `surface`·`push`)과 학습자가 주는 힘을 접선 방향으로 주입, 도약 출발 |
| 균일장 출발 보정 (`uniform_field`) | `UniformFieldCorrector` | 엔진 중력으로 적분, 첫 스텝 −mg/2(도약 출발). 표시 공식은 놓을 때의 엔진 장(크기·방향). 출발 면이 아닌 첫 접촉까지 자유 비행 기록 |
| 충돌 결과 보정 (`collision`) | `CollisionCorrector` | 엔진이 바디 재질 그대로 접촉을 감지·해결. A–B 접촉 보고가 시작된 스텝 직전 속도를 접촉이 끝날 때까지 보관하고, 끝나면 속도 = 보관 속도 + 접촉 스텝의 외력 Δv(마지막 비접촉 스텝의 실제 속도 변화) + 법선 방향 `world_collision_velocities` 결과(엔진 법선·마찰 충격량만 버림). 제3 바디 동시 접촉·지속 접촉은 엔진 결과 |
| 공식 힘 주입 (`force_injection`) | `ForceInjectionCorrector` → `SpringInjector`, `BuoyancyInjector`, `PointGravityInjector` | 엔진에 없는(또는 다른) 힘을 매 스텝 공식으로 계산해 주입, 도약 출발 |
| 해석 모델 구동 (`kinematic_model`) | `KinematicModelCorrector` → `PendulumModelDriver`, `LeverModelDriver`, `PulleyModelDriver` | TS 모델을 고정 스텝으로 진행하고 바디를 키네마틱으로 그 자세에 놓음(엔진은 충돌만) |

## 4. 실험별 보정 방식

허용 오차는 대표 장면 테스트(`tests/formula_checks.gd`, 실제 Jolt 바디)의 기준이다. 공식 포트 자체는 모두 TS 벡터와 상대 오차 1e-9 이내(측정 최대 3e-13).

| 실험 | 방식 | 쓰는 법칙 (TS 출처 → `PhysicsLaws`) | 표시 수치 | 핵심 운동과 허용 오차 | 근거 |
|---|---|---|---|---|---|
| 자유 낙하 (`free-fall`) | 균일장 출발 보정 | `constantAccelerationDisplacement/Velocity`, `UniformGravity`, `kineticEnergy`, `momentum`, `gravitationalPotentialEnergy` | 높이, 속력, 가속도 g, 운동량, 운동·위치 에너지 | 스텝 위치 = ½gt² (≤ 1e-4 m), 질량 0.5·1·3 kg가 같이 떨어짐(≤ 1e-6 m), 바닥 접촉 시각 = √(2h/g) ±2스텝 | 적분이 symplectic Euler라 도약 출발만으로 정확(보정 끄면 8 cm 오차) |
| 던지기 (`projectile`) | 균일장 출발 보정 | 위와 같음(축별) | 위치, 속도, 비행 경로(공식 곡선) | (x, y)(t) = x₀ + v₀t + ½at² (≤ 1e-4 m) | 같음. 착지 뒤 튀기는 엔진 접촉 |
| 충돌 (`collision`) | 충돌 결과 보정 | `postCollisionVelocity1D(·Second)`, `elasticCollision1D`, world.ts 반발 규칙(`min(eA, eB)`, 1 m/s 미만 e = 0), `momentum` | 충돌 전후 속도, 운동량(합 보존) | 충돌 뒤 속도 = TS world 결과(≤ 1e-4 m/s): 재질 반발 0(두 스텝 해결)·0.88씩(Jolt e = 1), 느린 접근(0.7 m/s, e = 0), 깊은 겹침 출발, 중력 하 공중 충돌(TS `MultiBodyWorld` 80스텝 속도와 네 성분 비교). 운동량 보존(≤ 1e-4). 짝 바디의 바닥 반발 = 보정 없는 쌍둥이(재질 그대로) | Jolt 반발 결합이 합(min(a+b,1))이고 마찰이 있어 TS와 다름. 재질을 바꾸면 바닥·벽까지 바뀌어 결과만 덮어씀 |
| 용수철 (`spring`) | 공식 힘 주입 | `AnchoredSpringLaw`(F = −kx − bv), `springPotentialEnergy`, `angularFrequency`, `periodFromAngularFrequency`, `harmonicDisplacement/Velocity/Energy`, `kineticEnergy` | 늘어난 길이(측정), 탄성·운동 에너지(TS 정의: 탄성 ½kx², 운동 ½mv². 감쇠·중력이 없으면 전체 = 놓을 때 상태의 ½kA² + ½mv₀², 운동 = 나머지. 있으면 현재 상태의 ½mv²(스텝 동기 속력) + ½kx²), 주기 | 주기 = 2π√(m/k) ±0.1%, 엔진 에너지(스텝 동기 속도) = ½kA² ±0.5%(10초), 감쇠 0.45에서 표시 에너지 = 현재 상태 K + U이고 줄기만 함, 정지 길이에서 2 m/s로 출발하면 전체 = ½mv₀² | 6DOF 스프링은 에너지 비보존(0.118–0.624 J). 주입 + 도약 출발은 3.5e-4 |
| 마찰 (`friction`) | 접촉 힘 보정 (`push`) | `PushFrictionLaw`(정지·운동, 역주행 방지), `maximumStaticForce` | 미는 힘, 최대 정지 마찰력 μₛmg, 상태(버팀/움직임. 정지 임계 0.01 px/s = 0.01/48 m/s) | μₛmg 아래 2초 정지(≤ 1 mm), 위에서 s = ½at², a = (F − μₖmg)/m(상대 ≤ 1e-4) | Jolt 마찰은 계수 하나. 빗면(Task 2a)과 같은 방식 |
| 빗면 마찰 (Task 2a, 마찰 실험의 3D 첫 사례) | 접촉 힘 보정 (`surface`) | `SurfaceContactFrictionModifier`, 임계각 atan μₛ | 기존 그대로 | 기존 테스트(측정 기준 4절, 재질별 임계각, s = ½at² ±1%) 그대로 통과, 기록 해시 리팩터 전과 같음 | S3 |
| 지렛대 (`rotation`) | 해석 모델 구동 | `LeverChallenge`(F = m g r_load / r_effort, 역학적 이득, lifting), `torque` | 필요한 힘, 역학적 이득, 양쪽 토크, 들림 여부 | 필요한 힘 미만이면 수평, 이상이면 들림 각 0.18 rad(≤ 1e-5 rad), 표시 힘 = TS | 웹도 운동이 아니라 평형 판정(0 / 0.18 rad). 힌지 동역학은 필요 없음 |
| 줄·막대 (`constraints`, 진자) | 해석 모델 구동 | `PendulumModel.step`(반암시적 오일러, 감쇠), `pose`, `pendulumPeriod`, `pendulumAngularFrequency` | 각도, 주기 2π√(L/g), 길이 | 추 각도 = TS 모델(≤ 1e-5 rad, 감쇠 0과 TS 기본 감쇠 0.08 둘 다), 길이 = L(≤ 1e-5 m), 주기 ±0.5%(0.1 rad), 추가 다른 바디를 민다 | PinJoint3D는 솔버 감쇠로 진폭이 줄고(30초 −1.3%) 웹 감쇠·각도 곡선을 재현 못 함 |
| 도르래 (`pulley`) | 해석 모델 구동 | `PulleyAdvantageChallenge`(F = mg/n, d_pull = n d_lift) | 필요한 힘, 줄 수, 들린 높이, 당긴 줄 길이 | 1 m 당기면 1/n 올라감(≤ 1e-5 m), 힘 = TS(1·2·4줄) | 웹도 이상적 도르래 관계만 보여 줌. 줄·바퀴 동역학 없음 |
| 궤도 (`orbit`) | 공식 힘 주입 | `PointGravity`(a = GM/r²), `circularOrbitSpeed/Period`, `escapeSpeed`, `OrbitChallenge.analyze`(충돌·공전·이탈 예측) | 궤도 반지름, 원 궤도 속력·주기, 탈출 속력, 예측 결과 | 원 궤도 한 바퀴 시간 = 2π√(r³/GM) ±0.1%, 반지름 ±0.1% | Area3D 점 중력 대신 주입: 법칙·G·M을 TS와 같게. 도약 출발 없이는 반지름이 0.7% 흔들림 |
| 부력 (`buoyancy`) | 공식 힘 주입 | `BuoyancyRegionLaw`(잠긴 비율 선형, 끌림), `buoyantForce`, `floatingSubmergedFraction`, `buoyancyNetForce` | 잠긴 깊이(측정), 부력 ρgV_sub, 무게, 뜨는 비율 ρ물체/ρ유체, 판정 뜸/중성/가라앉음(비율이 1에서 1e-9 이내면 중성) | 상자가 비율 m/m_displaced에 뜸 ±0.5%, 더 무거우면 바닥까지 가라앉음, 같으면 중성(가라앉음 아님) | Jolt에 유체 없음 |

## 5. 테스트 파이프라인

1. **TS → 벡터**: `tools/formula-vectors.test.ts`(루트 `npm test`)가 TS 함수·클래스를 직접 불러 `tests/formula_vectors.json`을 만들고 커밋된 파일과 대조한다. 내용: 실험 id → 쓰는 `PhysicsLaws` 함수 목록(10개 실험 전부), 사례 583개(`law`, SI 단위 `args`, `expect`. 밀기 마찰은 TS 법칙이 px 단위라 SI 인자 × 48을 넣고 힘 ÷ 48을 받는다), 대표 장면 목표값(`scenes`). 다시 만들기: `UPDATE_FORMULA_VECTORS=1 npx vitest run apps/lab3d`. 빗면은 기존 `tools/incline-vectors.test.ts` → `tests/incline_vectors.json`.
2. **Godot parity**: `tests/formula_checks.gd`가 사례마다 `PhysicsLaws.<law>(args)`를 불러 상대 오차(|기대값| < 1이면 절대 오차) ≤ 1e-9를 확인한다. 벡터에 있는 법칙에 포트가 없으면 실패한다.
3. **대표 장면**: 같은 파일이 방식마다 실제 Jolt 바디 장면을 만들어 4절 기준으로 확인한다. 기대값은 벡터의 `scenes`(TS 계산) 또는 parity를 통과한 `PhysicsLaws`에서 온다. 측정량은 보정기와 독립적으로(바디 위치에서) 잰다.
4. **돌연변이 확인**(Task 3에서 한 번): 균일장 도약 출발 끄기, 밀기 마찰 법칙 제거, 충돌 결과 덮어쓰기 끄기, 힘 주입 도약 출발 끄기, 용수철 k 1% 변경, 부력 깊이 1 cm 변경, 진자 스텝 1% 변경, 빗면 μₛ 10% 변경, 법칙 포트 변경(도르래 1e-6, 궤도 경로 기록 간격) — 모두 해당 검사가 실패했다. 리뷰 반영 때 더한 것: 충돌 보정이 재질을 바꿈(재질·바닥 반발 검사), 접촉 중 보관 속도를 덮어씀(반발 0 재질·중력 충돌), 접촉 스텝 외력 Δv 빠뜨림(중력 충돌), 던지기 출발 접촉을 착지로 봄, 밀기 정지 임계 0.01 m/s(parity), 중성부력을 가라앉음으로 봄 — 모두 실패했다. 2차 리뷰 반영: 균일장 표시가 엔진 장 대신 기본 9.81 아래를 씀(달 중력 기울어진 장), 출발 면 접촉 중 장 방향 운동을 착지로 봄(테이블 가장자리), `release()`가 `contact_monitor`를 켜지 않음, 이전 충돌 판정(설명 안 되는 속도 변화 + 30스텝 상한: 벽 옆 B·`apply_central_force` 접근·눌린 쌍), 접촉 스텝 외력을 중력 + `constant_force`로만 셈(접촉 중 `apply_*` 힘), 지속 접촉 판정 끔(눌린 쌍), 제3 바디 동시 접촉 판정 끔(세 공), 용수철 전체 에너지에서 출발 속도 뺌, 진자 감쇠 기본 0, `record()` 속도 없는 샘플 건너뜀 — 모두 실패했다.
5. **CI**: `.github/workflows/ci.yml`이 PR과 dev·main push마다 Node 테스트·빌드와 Godot 4.7.2 헤드리스 테스트(앱·스파이크)를 돌린다. 앱 [README "테스트와 CI"](../README.md#테스트와-ci).

새 실험(Task 4)은 이 표의 방식 중 하나를 고르고, 쓰는 법칙을 `formula-vectors.test.ts`의 해당 그룹에 더한 뒤 화면 수치는 보정기의 `formula_values()`(또는 `PhysicsLaws`)에서만 가져온다.
