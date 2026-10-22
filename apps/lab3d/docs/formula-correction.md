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
- 충돌 보정은 알려진 두 바디(구)의 정면·비스듬한 충돌만 다룬다. 접촉 스텝의 위치는 엔진 결과로 움직인다(스텝마다 오차 ≤ |Δv| dt). **충돌 판정**은 엔진 접촉 보고다: A의 `get_colliding_bodies()`에 B가 새로 들어온 스텝(보고는 바로 전 스텝 기준)을 충돌 시작으로 보고, 그 스텝을 시작할 때의 속도를 보관한다(`setup()`이 두 바디의 `contact_monitor`를 켠다). 벽·바닥 충격, `apply_*` 힘처럼 A–B 접촉이 아닌 속도 변화는 판정에 쓰이지 않는다. 보정하지 않고 엔진 결과를 두는 경우: (1) 같은 스텝에 A나 B가 다른 바디(벽, 바닥, 세 번째 공)와도 새로 닿음 — 충격량을 나눌 수 없다. 계속 닿아 있는 바닥(굴러가는 공)은 막지 않는다. (2) 지속 접촉 — 마지막 접촉 뒤 표면이 5 cm 넘게 떨어진 적이 없고 닫히는 속도가 반발 임계(1 m/s) 미만(서로 눌린 채 미는 쌍, 접촉 보고가 깜박이는 경우). 반발 임계 미만의 느린 첫 접촉(떨어져 있다 닿음)은 보정한다(TS e = 0). 접촉 스텝 동안 더하는 외력 Δv는 **A–B 접촉이 없던 마지막 스텝의 실제 속도 변화**다(중력, 계속 닿은 바닥의 지지, `constant_force`, 매 스텝 주는 `apply_*` 힘과 감쇠가 다 들어간다. 접촉 동안 힘이 같다고 보는 근사). 그런 스텝이 아직 없으면(놓자마자 닿음) 엔진 중력 + `constant_force`다. 그 마지막 비접촉 스텝에 바닥·벽에 튕겼거나 순간 힘이 있었다면 그 한 스텝의 변화가 접촉 전체로 외삽된다. 접촉이 끝나는 기준은 법선 상대 속도가 더는 닫히지 않거나 보고에서 B가 빠질 때이고, 스텝 상한은 없다. 밀기 모드의 첫 스텝 절반 규칙은 밀기 정지 임계(`PUSH_REST_SPEED`)를, 빗면은 2a 임계(0.01)를 쓴다.
- 용수철 감쇠(−bv)와 부력 끌림(−drag f m v)은 엔진의 `linear_velocity`를 쓴다. 이 값은 symplectic Euler에서 v_(k−1/2), 위치보다 반 스텝 늦은 속도다. 위치 차분 (x_k − x_(k−1))/dt도 같은 값이라 바꿔도 나아지지 않고, 스텝 시점 속도(`synced_velocity`)는 그 힘 자체가 필요해 암시적 풀이가 된다. 그래서 그대로 둔다: 감쇠율·끌림은 dt 1차 정확도(b dt = 0.0075, 끌림 1.8 × dt = 0.03 정도의 상대 차)이고, 표시 수치(에너지, 뜨는 비율)는 이 값에 기대지 않는다.
- 균일장 보정의 착지는 엔진 접촉 보고(`get_colliding_bodies()`)로 판정한다: 출발 때 닿아 있지 않던 바디와의 접촉, 또는 출발 때 닿아 있던 면과 한 번 떨어진 뒤 다시 닿음. 바닥에서 던지거나 테이블 가장자리에서 아래 성분이 있는 속도로 밀어 낸 물체는 출발 면으로 착지하지 않는다. 바닥에 놓은 채 v₀ = 0으로 놓으면 착지하지 않고 시간이 계속 간다(실험은 이 경우를 공식으로 처리한다: 아래 실험 구현). **출발 접촉은 항상 놓은 뒤 첫 스텝의 보고로 정한다**: 놓기 전 보고는 얼어 있던 바디(`FREEZE_MODE_STATIC`은 접촉을 보고하지 않는다)의 빈 보고이거나 이전 실행의 낡은 보고라, 읽으면 이미 닿아 있던 면이 첫 스텝에 착지로 잡힌다(리뷰 지적, 처음 연 실험의 첫 바닥 던지기가 1스텝 착지). 놓은 스텝(steps 0)의 보고는 읽지 않고, 첫 스텝 안에 새로 닿은 면도 출발 면으로 본다. `contact_monitor`가 꺼져 있으면 `release()`가 켠다. `surfaces`(지면: 바닥·실험이 정한 면)를 주면 그 바디와의 접촉만 착지다. 다른 공처럼 지면이 아닌 바디와 닿는 것은 착지가 아니다(비어 있으면 모든 바디). 표시 공식의 g·방향은 `release()` 때 바디에 걸린 엔진 장(`get_gravity()`. 이 값에 `gravity_scale`과 영역 중력이 이미 들어 있다 — Task 4a에서 측정. Task 3 구현은 `gravity_scale`을 한 번 더 곱해 배율이 0·1이 아닐 때 장이 틀렸고, 네 보정기 모두 고쳤다)이다. 크기가 설정값과 float32 반올림만큼만 다르면 64비트 설정값(9.81)을 그대로 쓴다. 놓은 뒤 장이 바뀌는 경우(영역 경계를 넘음)는 다루지 않는다.
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
| 해석 모델 구동 (`kinematic_model`) | `KinematicModelCorrector` → `PendulumModelDriver`, `LeverModelDriver`, `PulleyModelDriver`; 충돌 실험의 `CollisionRailDriver`(두 공, Task 4c) | TS 모델을 고정 스텝으로 진행하고 바디를 키네마틱으로 그 자세에 놓음(엔진은 충돌만. 충돌 실험은 두 공끼리의 접촉도 공식) |

## 4. 실험별 보정 방식

허용 오차는 대표 장면 테스트(`tests/formula_checks.gd`, 실제 Jolt 바디)의 기준이다. 공식 포트 자체는 모두 TS 벡터와 상대 오차 1e-9 이내(측정 최대 3e-13).

| 실험 | 방식 | 쓰는 법칙 (TS 출처 → `PhysicsLaws`) | 표시 수치 | 핵심 운동과 허용 오차 | 근거 |
|---|---|---|---|---|---|
| 자유 낙하 (`free-fall`) | 균일장 출발 보정 | `constantAccelerationDisplacement/Velocity`, `UniformGravity`, `kineticEnergy`, `momentum`, `gravitationalPotentialEnergy` | 높이, 속력, 가속도 g, 운동량, 운동·위치 에너지 | 스텝 위치 = ½gt² (≤ 1e-4 m), 질량 0.5·1·3 kg가 같이 떨어짐(≤ 1e-6 m), 바닥 접촉 시각 = √(2h/g) ±2스텝 | 적분이 symplectic Euler라 도약 출발만으로 정확(보정 끄면 8 cm 오차) |
| 던지기 (`projectile`) | 균일장 출발 보정 | 위와 같음(축별) | 위치, 속도, 비행 경로(공식 곡선) | (x, y)(t) = x₀ + v₀t + ½at² (≤ 1e-4 m) | 같음. 착지 뒤 튀기는 엔진 접촉 |
| 충돌 (`collision`) | 충돌 결과 보정(대표 장면). 안내형 실험은 공식 모델 구동(Task 4c, 아래) | `postCollisionVelocity1D(·Second)`, `elasticCollision1D`, world.ts 반발 규칙(`min(eA, eB)`, 1 m/s 미만 e = 0), `momentum` | 충돌 전후 속도, 운동량(합 보존) | 충돌 뒤 속도 = TS world 결과(≤ 1e-4 m/s): 재질 반발 0(두 스텝 해결)·0.88씩(Jolt e = 1), 느린 접근(0.7 m/s, e = 0), 깊은 겹침 출발, 중력 하 공중 충돌(TS `MultiBodyWorld` 80스텝 속도와 네 성분 비교). 운동량 보존(≤ 1e-4). 짝 바디의 바닥 반발 = 보정 없는 쌍둥이(재질 그대로) | Jolt 반발 결합이 합(min(a+b,1))이고 마찰이 있어 TS와 다름. 재질을 바꾸면 바닥·벽까지 바뀌어 결과만 덮어씀 |
| 용수철 (`spring`) | 공식 힘 주입(대표 장면). 안내형 실험은 공식 모델 구동(Task 4d, 아래) | `AnchoredSpringLaw`(F = −kx − bv), `springPotentialEnergy`, `angularFrequency`, `periodFromAngularFrequency`, `harmonicDisplacement/Velocity/Energy`, `kineticEnergy` | 늘어난 길이(측정), 탄성·운동 에너지(TS 정의: 탄성 ½kx², 운동 ½mv². 감쇠·중력이 없으면 전체 = 놓을 때 상태의 ½kA² + ½mv₀², 운동 = 나머지. 있으면 현재 상태의 ½mv²(스텝 동기 속력) + ½kx²), 주기 | 주기 = 2π√(m/k) ±0.1%, 엔진 에너지(스텝 동기 속도) = ½kA² ±0.5%(10초), 감쇠 0.45에서 표시 에너지 = 현재 상태 K + U이고 줄기만 함, 정지 길이에서 2 m/s로 출발하면 전체 = ½mv₀² | 6DOF 스프링은 에너지 비보존(0.118–0.624 J). 주입 + 도약 출발은 3.5e-4 |
| 마찰 (`friction`) | 접촉 힘 보정 (`push`) | `PushFrictionLaw`(정지·운동, 역주행 방지), `maximumStaticForce` | 미는 힘, 최대 정지 마찰력 μₛmg, 지금 마찰력, 운동 마찰력 μₖmg(`KineticFriction`), 속력, 열에너지(`work`), 상태(버팀/움직임. 정지 임계 0.01 px/s = 0.01/48 m/s) | μₛmg 아래 2초 정지(≤ 1 mm), 위에서 s = ½at², a = (F − μₖmg)/m(상대 ≤ 1e-4) | Jolt 마찰은 계수 하나. 빗면(Task 2a)과 같은 방식 |
| 빗면 마찰 (Task 2a, 마찰 실험의 3D 첫 사례) | 접촉 힘 보정 (`surface`) | `SurfaceContactFrictionModifier`, 임계각 atan μₛ | 기존 그대로 | 기존 테스트(측정 기준 4절, 재질별 임계각, s = ½at² ±1%) 그대로 통과, 기록 해시 리팩터 전과 같음 | S3 |
| 지렛대 (`rotation`) | 해석 모델 구동 | `LeverChallenge`(F = m g r_load / r_effort, 역학적 이득, lifting), `torque` | 필요한 힘, 역학적 이득, 양쪽 토크, 들림 여부 | 필요한 힘 미만이면 수평, 이상이면 들림 각 0.18 rad(≤ 1e-5 rad), 표시 힘 = TS | 웹도 운동이 아니라 평형 판정(0 / 0.18 rad). 힌지 동역학은 필요 없음 |
| 줄·막대 (`constraints`, 진자) | 해석 모델 구동 | `PendulumModel.step`(반암시적 오일러, 감쇠), `pose`, `pendulumPeriod`, `pendulumAngularFrequency` | 각도, 주기 2π√(L/g), 길이 | 추 각도 = TS 모델(≤ 1e-5 rad, 감쇠 0과 TS 기본 감쇠 0.08 둘 다), 길이 = L(≤ 1e-5 m), 주기 ±0.5%(0.1 rad), 추가 다른 바디를 민다 | PinJoint3D는 솔버 감쇠로 진폭이 줄고(30초 −1.3%) 웹 감쇠·각도 곡선을 재현 못 함 |
| 도르래 (`pulley`) | 해석 모델 구동 | `PulleyAdvantageChallenge`(F = mg/n, d_pull = n d_lift) | 필요한 힘, 줄 수, 들린 높이, 당긴 줄 길이 | 1 m 당기면 1/n 올라감(≤ 1e-5 m), 힘 = TS(1·2·4줄) | 웹도 이상적 도르래 관계만 보여 줌. 줄·바퀴 동역학 없음 |
| 궤도 (`orbit`) | 공식 힘 주입(대표 장면). 안내형 실험은 공식 모델 구동(Task 4d, 아래) | `PointGravity`(a = GM/r²), `circularOrbitSpeed/Period`, `escapeSpeed`, `OrbitChallenge.analyze`(충돌·공전·이탈 예측) | 궤도 반지름, 원 궤도 속력·주기, 탈출 속력, 예측 결과 | 원 궤도 한 바퀴 시간 = 2π√(r³/GM) ±0.1%, 반지름 ±0.1% | Area3D 점 중력 대신 주입: 법칙·G·M을 TS와 같게. 도약 출발 없이는 반지름이 0.7% 흔들림 |
| 부력 (`buoyancy`) | 공식 힘 주입(대표 장면). 안내형 실험은 공식 모델 구동(Task 4d, 아래) | `BuoyancyRegionLaw`(잠긴 비율 선형, 끌림), `buoyantForce`, `floatingSubmergedFraction`, `buoyancyNetForce` | 잠긴 깊이(측정), 부력 ρgV_sub, 무게, 뜨는 비율 ρ물체/ρ유체, 판정 뜸/중성/가라앉음(비율이 1에서 1e-9 이내면 중성) | 상자가 비율 m/m_displaced에 뜸 ±0.5%, 더 무거우면 바닥까지 가라앉음, 같으면 중성(가라앉음 아님) | Jolt에 유체 없음 |

### 실험 구현 (Task 4a: 균일장)

자유 낙하·던지기 실험(`experiments/free_fall/`, `experiments/projectile/`, 공용 `experiments/uniform_field/uniform_field_lab.gd`)이 위 표의 방식을 그대로 쓴다.

- 중력 선택(무중력·달·지구·목성)은 공의 `gravity_scale`로 엔진 장을 정하고 보정기에 64비트 g를 준다. 이때 `get_gravity()`가 이미 `gravity_scale`을 포함한다는 것을 확인했고(배율 0.165에서 −1.62 반환), Task 3 보정기 네 개가 배율을 한 번 더 곱하던 것을 고쳤다(2절 한계 항목, 회귀 검사 `uniform field: gravity_scale 0.165`).
- 표시: 놓은 뒤 고정 스텝 시계를 공식 착지 시간 `landing_time(v0y, −g, h₀)`에서 멈추고 그 시각의 `PhysicsLaws` 값을 보인다. 착지 시간·최고점(`landing_time`, `apex_time`, `apex_rise`)은 TS 코어에 닫힌 식이 없어, 벡터 생성기가 TS `constantAccelerationDisplacement/Velocity`의 근을 이분법으로 구한다(`tools/ts-oracle.ts`, parity 상대 오차 0). `landing_time(v0, a, drop)`은 a t²/2 + v0 t + drop = 0의 **첫 양의 근**이다(모든 부호: 위쪽 장 a > 0, 장 없음 a = 0, 출발보다 높은 착지면 drop < 0이면 올라가는 길의 근). 착지면 위에서 출발해(drop = 0) 바로 그 아래로 가면(v0 < 0, 또는 v0 = 0이고 a < 0) 0, 착지면에 닿지 않으면 INF다. 오라클은 속도의 근(전환점)으로 나눈 단조 구간마다 이분법으로 찾고, 벡터에는 INF를 문자열 `"inf"`로 적는다(JSON에 Infinity 없음).
- 착지 판정(2차 리뷰, 공식 소유): 화면의 "착지됨"은 **공식 시계 ≥ 공식 착지 시간**(스텝 수 × dt 반올림 여유 1e-9 s) **또는 엔진 착지 보고**다(`UniformFieldLab.has_landed_by`). 그때부터 공식 착지 값(t = T, h = 0)을 보인다. 한 스텝 여유는 두지 않았다: 착지 한 스텝 전의 시계 값을 TS 벡터가 그대로 확인한다(여유 1스텝이면 5 m 낙하의 60스텝 표시가 T 값으로 바뀌어 실패했다). 엔진 착지는 접촉 보고라 출발 바닥 접촉이 끝나지 않으면 오지 않는다(바닥 몇 mm 위 낙하, 바닥에서 15°·1 m/s 같은 짧은 튐: 측정 결과 보고 없음). 그래서 엔진 착지는 "시뮬레이션" 측정값에만 쓴다: 측정 착지 스텝은 엔진 보고 스텝, 보고 없이 공식 착지가 지나면 공식 착지 시각에 가장 가까운 기록 스텝이고(`measured_landing_step`), 자유 낙하는 그 스텝 시각, 던지기는 그 스텝의 엔진 x를 보인다. 아직 없으면 "—"다. 그래프 시뮬레이션 점은 공식 착지 시각까지만 더한다(엔진 보고와 무관). 보정기의 스텝 길이 `dt`는 `release()` 때 `Engine.physics_ticks_per_second`로 정한다(첫 스텝 전에도 실제 스텝 길이: 120 Hz에서 기본값 1/60을 쓰면 놓은 직후 판정이 바뀌었다).
- 착지 규칙(PR #9 리뷰): 공의 착지 대상은 바닥(`surfaces`)뿐이고, 공은 자기 충돌 층(3)에 있고 마스크는 세계 층(1)뿐이라 공끼리 닿지 않는다. 옆에 붙은 공(0.5 m 격자)의 접촉이 있으면 엔진의 바닥 접촉 보고가 한 스텝 늦었다(측정: 같은 5 m 낙하가 62 → 63스텝). 자유 낙하에서는 한 공의 낙하선(같은 x) 위·아래에 다른 공을 놓을 수 없다(`placement_allowed`: 공중에서 겹치거나 지나가는 모습을 막는다. 옆 격자는 허용). 공식 착지 시간이 0인 공(장 안에서 바닥에 놓고 위로 던지지 않음: 자유 낙하 높이 0, 던지기 높이 0·각도 0)은 놓는 순간 착지한 것으로 본다(시간 0, 그래프 점 없음). 장이 없으면 바닥의 공도 착지하지 않고(착지 시간 INF) 시간은 시계다. 출발 높이는 놓을 때 1 mm 격자로 맞춰(`snapped_height`) 엔진 출발점·그래프 점·공식이 같은 값을 쓴다.
- 던지기 발사 속도는 64비트 스칼라(`launch_vx`·`launch_vy`)로 공식에 넣는다. `Vector3`에 담으면 32비트로 반올림돼 표시가 1e-7만큼 어긋난다(측정).
- 테스트: `tests/uniform_lab_checks.gd`(1·2·3절 기준을 실험 자체에 적용, 기대값은 `tests/uniform_labs_vectors.json`). 결과는 앱 README "테스트".

### 실험 구현 (Task 4b: 마찰 밀기)

마찰 밀기 실험(`experiments/friction/`)은 위 표의 `push` 법칙을 쓴다.

- 힘은 학습자 입력이라 닫힌 식이 없다. 그래서 표시는 **공식 모델**(`PushFrictionModel`)이 맡는다: 매 스텝 그 스텝의 힘으로 `push_friction_holding`·`push_friction_force`를 부르고, 보정기와 같은 스텝 규칙(쉬다가 떠나는 스텝은 알짜힘 절반, v += F/m dt, x += v dt)으로 64비트 속도·변위를 진행한다. 마찰력 = 알짜힘 − 주는 힘(웹 힘 분해와 같음, 버틸 때 = −F), 열에너지 = −Σ `work_1d`(마찰력, 스텝 변위). 상태(버팀/움직임)·속력·거리·열에너지·그래프는 모두 이 모델의 값이고, 엔진 상자(보정기가 엔진 속도로 같은 법칙을 적용)는 "간 거리(시뮬레이션)"에만 쓴다. 헤드리스 검사가 엔진을 얼려 두어도 화면 상태가 공식대로인지 확인한다.
- TS 오라클(`tools/friction-lab-vectors.test.ts` → `tests/friction_lab_vectors.json`): TS `PushFrictionLaw`를 웹 px 단위(입력 × 48, 힘 ÷ 48, 에너지 ÷ 48²)로 같은 스텝 규칙으로 진행하고 TS `work`·`kineticEnergy`로 열·운동 에너지를 낸다. 재질 4종 × 무게, 힘 일정표(최대 정지 마찰력 바로 아래 → 위 → 0, 고무는 반대 방향 밀기 포함)에서 15스텝마다 기록한다. 최대 정지 마찰력 −0.01 N·같은 값·+0.01 N에서 TS 상태도 기록한다.
- 결과: 표시값 = TS(상대 4e-15), 엔진 변위 = 모델(≤ 2.5e-6 m), 열 = μₖmg × 미끄러진 거리(3e-16), 주는 힘의 일 = 운동 에너지 + 열(60 Hz 스텝 오차 5% 이내. 스텝마다 ½m(Δv)²와 떠나는 스텝의 절반 힘만큼 다르다). 경계값에서 버팀 2초(≤ 1 mm), +0.01 N에서 첫 스텝부터 s = (F − μₖmg)t²/2m.
- 손잡이 힘 = 집은 자리에서 손잡이 격자점까지 칸 수 × (5 cm × 20 N/m) = 정수 N. 격자 간격은 64비트 규칙 값으로 센다(`ManipSurface.snap`은 32비트 `Vector2`라 0.05 × 20 = 1.0000000149가 된다).
- 트랙 끝: 공식 위치가 끝(±(6 − 0.35 − 0.02) m)을 넘어가면 모델 속도 0, 위치를 끝으로 고정하고(빠른 상자가 한 스텝에 넘어간 몫 포함) 다음 스텝에 엔진 상자를 그 자리에 얼린다.

### 실험 구현 (Task 4c: 충돌)

충돌 실험(`experiments/collision/`)은 레일 위 두 공의 1차원 충돌이다. 사용자 우선순위("물리 공식에 맞게 동작하는 것이 제일 중요")에 따라 표시 수치뿐 아니라 **화면 속 공의 움직임**이 충돌 전·충돌 순간·충돌 뒤 모두 TS 공식과 스텝 단위로 같아야 한다(목표 ≤ 1e-4 m, ≤ 1e-4 m/s).

- 공식 모델 `CollisionModel`: 웹 충돌 프리셋의 한 프레임(`physics-playground.ts` `advance`)을 레일에서 64비트로 진행한다. TS world 명시적 오일러(x += v dt, 레일 방향 힘 없음) → world.ts `resolveCollisions`(겹치면 겹친 만큼 질량 역비로 밀어내고, 다가가면 `world_collision_velocities`: 반발 min(eA, eB), 닫히는 속도 1 m/s 미만 e = 0) → `applyPresetDamping`(v ×= e^(−0.15 dt), 2 px/s 미만 정지) → `resolveWorldBounds`(벽 = 레일 끝 범퍼 면 ±7 m, 넘으면 벽에 두고 바깥으로 가면 v ×= −e). 첫 충돌(속도를 바꾼 첫 충격)의 앞뒤 속도·e를 기록하고, 충격량은 각 공의 Δp(`momentum` 차), 운동 에너지 합은 `kinetic_energy`.
- 엔진: `CollisionRailDriver`(방식 `kinematic_model`)가 매 고정 스텝 물리 서버 전에 엔진 공의 위치를 기록하고, 모델을 한 스텝 진행한 뒤 두 공(얼린 키네마틱 `RigidBody3D`)을 모델 위치에 둔다. 두 공은 Jolt 안에서 서로 충돌하지 않는다(충돌 예외, 마스크 0). 엔진 공이 공식 위치에 놓이므로 엔진에서 잰 값은 독립 측정이 아니다: 패널에 "시뮬레이션" 관찰값을 두지 않고(이전 "지금 운동량 합(시뮬레이션)"은 공식 값을 다시 읽을 뿐이라 뺐다) 모든 수치가 공식 모델의 값이다. 엔진 위치는 테스트가 공식과 대조하는 데만 쓴다.
- `CollisionCorrector`(Jolt 접촉 + 공식 결과 속도)를 쓰지 않은 이유: 같은 웹 시작 조건(1 kg·2 kg 고무, 3.4·−1.7 m/s)을 헤드리스로 재 보니, 엔진 속도를 매 스텝 모델 속도로 맞춰도 충돌 스텝 앞뒤에서 공 위치가 공식 궤적에서 최대 **0.084 m** 벗어났다(Jolt 추측 접촉이 접촉 스텝의 속도·위치를 바꾸고, TS는 겹친 뒤 밀어냄). 보정기만 두고 감쇠를 같이 주면 5초 뒤 **0.23 m**까지 벌어졌다. 접촉을 공식이 맡고 Jolt 접촉을 끈 구동(밀어내기 스텝은 위치로 반영)은 **2.4e-7 m**다. 대표 장면의 `CollisionCorrector`(속도 결과 ≤ 1e-4 m/s)는 Task 5 빈 실험실처럼 바디가 자유롭게 부딪히는 경우에 그대로 쓴다.
- 남은 차이(측정, `tests/collision_lab_checks.gd`): 엔진 위치는 Godot 단정밀도(float32)라 ±7 m에서 반올림 2.4e-7 m(TS 표본 대비)·3.8e-7 m(매 스텝 모델 대비), 스텝 속도(변위/dt) 2.8e-5 m/s. 공의 회전은 없다(구르는 모습은 자식 메시만 돌림). 마찰은 공식에 없고 엔진 접촉도 없어 영향이 없다.
- TS 오라클(`tools/collision-lab-vectors.test.ts` → `tests/collision_lab_vectors.json`): 웹 `PhysicsSimulation`에 원 두 개를 웹 px 단위로 넣고 60 Hz로 진행하며, 프리셋 감쇠·정지·벽 규칙을 웹과 같은 순서로 적용한다(이 상수들은 `physics-playground.ts` 안의 비공개 값이라 테스트가 소스에서 값을 읽어 같은지 확인한다). 7가지 경우의 6스텝마다 위치·속도·운동량, 첫 충돌(스텝, 앞뒤 속도, `coefficientOfRestitution`, 충격량, 운동량·에너지 합), 충돌 횟수를 기록한다.
- 엔진 기록 `engine_a/b`는 `history_steps`까지만 쌓이므로 직전 스텝 위치는 `last_engine`에 따로 둔다(`FormulaCorrector.last_sample`처럼). 10초를 넘는 실행(웹 시작 약 29초)에서도 엔진 위치·스텝 속도·운동량이 공식과 1e-4 안이다. 충돌 연출 세기는 모델이 기록한 그 스텝의 닫히는 속도(`CollisionModel.last_closing`)로 정한다.
- 결과: 모델 = TS(상대 7e-15, 첫 충돌 값 1e-15), 패널 = TS(1.6e-15), 운동량 보존(1.8e-15), 같은 질량 e = 1이면 속도 교환. 돌연변이(감쇠 끔, 밀어내기 끔, 충돌 결과 0.1% 변경, 벽 반발 무시, 구동이 한 스텝 늦음, 손잡이 눈금 변경, 엔진 접촉 켬) 모두 해당 검사가 실패했다.

### 실험 구현 (Task 4d: 용수철·부력·궤도)

세 실험(`experiments/{spring,buoyancy,orbit}/`)은 충돌(4c)처럼 사용자 우선순위("물리 공식에 맞게 동작하는 것이 제일 중요")에 따라 표시값과 **화면 속 물체의 움직임**을 TS 공식과 스텝 단위로 맞춘다. 구동은 공용 `BodyModelDriver`(방식 `kinematic_model`): 매 고정 스텝 물리 서버 전에 엔진 바디(얼린 키네마틱 `RigidBody3D`, 충돌 없음)의 위치를 기록하고 공식 모델을 한 스텝 진행해 바디를 모델 위치에 둔다. 그래서 `SpringInjector`·`BuoyancyInjector`·`PointGravityInjector`(대표 장면)는 안내형 실험에 쓰지 않는다. 엔진 바디가 공식 위치에 놓이므로 엔진에서 잰 값은 독립 측정이 아니다: 패널에 "시뮬레이션" 관찰값을 두지 않고 모든 수치가 공식 모델 값이다(엔진 위치는 테스트가 공식과 대조하는 데만 쓴다).

| 실험 | 공식 모델 | 웹과 같은 것 | 웹 적분을 따르지 않은 이유(측정) |
|---|---|---|---|
| 용수철 | `SpringModel`: `AnchoredSpringLaw`(k = 5 N/m)의 정확한 해를 t = k dt에서 취함. 감쇠 없으면 TS `harmonicDisplacement/Velocity`, 감쇠(b = 0.45)는 감쇠 진동 해(`PhysicsLaws` 추가, TS 법칙 RK4와 1e-9) | k, b, 질량 | 웹 명시적 오일러는 10초에 에너지 +52% |
| 부력 | `BuoyancyModel`: `BuoyancyRegionLaw`(잠긴 비율 선형 = 세운 기둥에 정확, 물 저항 1.8/s)와 중력, 반암시적 오일러 4번 나눔(60 Hz), 웹 바닥 규칙(e 0.5, 1 m/s 미만 정지) | 법칙, 물 1000 kg/m³, 바닥 규칙 | 웹 명시적 오일러는 가벼운 통이 10초에 뜰 깊이에서 0.72 m 벗어남 |
| 궤도 | `OrbitModel`: `PointGravityField`(GM 27 m³/s², 3 m에서 원 궤도 3 m/s)를 속도 Verlet 8번 나눔(60 Hz). 별 표면 + 행성 반지름(1.2 m)에서 충돌, 12 m에서 이탈로 끝. 예측은 `OrbitChallenge` | GM, 시작 조건, 충돌·이탈 규칙, 예측 | 웹 명시적 오일러는 20초에 반지름 3 → 3.83 m로 퍼짐 |

- TS 오라클(`tools/{spring,buoyancy,orbit}-lab-vectors.test.ts` → `tests/*_lab_vectors.json`, 용수철 6·부력 7·궤도 8가지 경우): TS 코어 클래스·함수로 6스텝마다 상태·패널 값을 기록한다. 감시: TS를 바꾸면 vitest가 먼저 깨지고, `UPDATE_{SPRING,BUOYANCY,ORBIT}_VECTORS=1`로 다시 만든 뒤 Godot 쪽 불일치를 본다.
- 결과(헤드리스, `tests/{spring,buoyancy,orbit}_lab_checks.gd`):

| 항목 | 용수철 | 부력 | 궤도 |
|---|---|---|---|
| 모델 = TS (상대 오차) | 1.3e-15 | 3.1e-16 | 3.7e-15(예측·결과 1.7e-13) |
| 엔진 바디 위치 오차(60초 실행 포함) | 1.2e-7 m | 5.9e-8 m | 4.6e-7 m |
| 엔진 스텝 속도 오차 | 1.5e-5 m/s | 1.3e-5 m/s | 5.2e-5 m/s |
| 패널 = TS (상대 오차) | 1.3e-15 | 3.1e-16 | 3.8e-16 |
| 법칙 확인(엔진 바디에서) | 영점 통과 주기 = 2π√(m/k)(0.5·1·3 kg, 1e-4), 엔진 위치로 잰 에너지 보존 4.6e-4(30초), 감쇠 때만 감소 | 70 kg·100 L이 0.35 m에 떠 부력 = 무게, 같은 밀도면 작은 통도 같은 비율, 150 kg은 바닥, 같은 밀도는 그 자리에 머묾 | 원 궤도 반지름 6.7e-6 m 이내 60초, 주기 = 2π√(r³/GM) 3 m·5 m(1.4e-6), 에너지 보존 1e-4(타원 30초), 탈출 속력 위/아래, 충돌 위치 r = 1.2 m |

  끌어 놓은 뒤 출발(용수철 0.7 m, 부력 0.55 m 아래, 궤도 knob 4.5 m/s·90°와 반지름 4 m)도 공식 곡선과 같다(≤ 2.4e-7 m).
- 엔진 기록은 `history_steps`까지만 쌓이므로 직전 스텝 위치를 `last_engine`에 따로 둔다(4c와 같음). 엔진 위치는 Godot 단정밀도(float32)라 반올림이 위 오차의 한계다.
- 공 회전 없음: 용수철 공·부력 통·궤도 행성의 몸체는 돌지 않는다(회전은 메시뿐, 4c와 같음). 부력은 선형 잠김 비율이 정확한 세운 기둥(상자·원기둥)만 쓴다.
- 구조: 세 실험(과 충돌)의 공통 부분(run 상태·그래프 장부·`release()` 본문·자유 바디 구성)은 `experiments/model_driven/model_driven_lab.gd`(`ModelDrivenLab`), 배치 복원(`begin_batch`/`end_batch`/`_restart`)은 `Experiment`에 있다. 시계는 `BodyModel.dt`/`time()` 하나다. 궤도의 GM·충돌·이탈 반지름·평면 높이는 `OrbitModel`의 상수 한 곳이고, 서브스텝마다 부르는 `PhysicsLaws.point_gravity_field_acceleration`은 `out` 인자에 써서 할당이 없다(수치 불변).
- 리뷰 반영(4d 검증): 시계 방향 발사의 첫 바퀴 시간은 `|swept| ≥ 2π`로 센다(TS 오라클도 같게 고쳐 벡터의 "clockwise" 경우가 −1 대신 8.69 s). 부력 상태는 밀도 판정이 먼저라 같은 밀도(중성) 통이 바닥에 닿아도 `staying`이고 `sunk`는 더 무거운 통만이다. 돌연변이: `swept >= TAU`로 되돌림(시계 방향 첫 바퀴 검사 실패), 바닥 접촉을 먼저 `sunk`로 봄(중성 바닥 검사 실패) — 모두 실패했다.
- 그래프 y축: 용수철의 에너지 비율은 고정 0–100 %축(`graph.y.max`, `GraphView.y_top`), 나머지는 데이터에 맞춘 자동 축.

## 5. 테스트 파이프라인

1. **TS → 벡터**: `tools/formula-vectors.test.ts`(루트 `npm test`)가 TS 함수·클래스를 직접 불러 `tests/formula_vectors.json`을 만들고 커밋된 파일과 대조한다. 내용: 실험 id → 쓰는 `PhysicsLaws` 함수 목록(10개 실험 전부), 사례 583개(`law`, SI 단위 `args`, `expect`. 밀기 마찰은 TS 법칙이 px 단위라 SI 인자 × 48을 넣고 힘 ÷ 48을 받는다), 대표 장면 목표값(`scenes`). 다시 만들기: `UPDATE_FORMULA_VECTORS=1 npx vitest run apps/lab3d`. 빗면은 기존 `tools/incline-vectors.test.ts` → `tests/incline_vectors.json`.
2. **Godot parity**: `tests/formula_checks.gd`가 사례마다 `PhysicsLaws.<law>(args)`를 불러 상대 오차(|기대값| < 1이면 절대 오차) ≤ 1e-9를 확인한다. 벡터에 있는 법칙에 포트가 없으면 실패한다.
3. **대표 장면**: 같은 파일이 방식마다 실제 Jolt 바디 장면을 만들어 4절 기준으로 확인한다. 기대값은 벡터의 `scenes`(TS 계산) 또는 parity를 통과한 `PhysicsLaws`에서 온다. 측정량은 보정기와 독립적으로(바디 위치에서) 잰다.
4. **돌연변이 확인**(Task 3에서 한 번): 균일장 도약 출발 끄기, 밀기 마찰 법칙 제거, 충돌 결과 덮어쓰기 끄기, 힘 주입 도약 출발 끄기, 용수철 k 1% 변경, 부력 깊이 1 cm 변경, 진자 스텝 1% 변경, 빗면 μₛ 10% 변경, 법칙 포트 변경(도르래 1e-6, 궤도 경로 기록 간격) — 모두 해당 검사가 실패했다. 리뷰 반영 때 더한 것: 충돌 보정이 재질을 바꿈(재질·바닥 반발 검사), 접촉 중 보관 속도를 덮어씀(반발 0 재질·중력 충돌), 접촉 스텝 외력 Δv 빠뜨림(중력 충돌), 던지기 출발 접촉을 착지로 봄, 밀기 정지 임계 0.01 m/s(parity), 중성부력을 가라앉음으로 봄 — 모두 실패했다. 2차 리뷰 반영: 균일장 표시가 엔진 장 대신 기본 9.81 아래를 씀(달 중력 기울어진 장), 출발 면 접촉 중 장 방향 운동을 착지로 봄(테이블 가장자리), `release()`가 `contact_monitor`를 켜지 않음, 이전 충돌 판정(설명 안 되는 속도 변화 + 30스텝 상한: 벽 옆 B·`apply_central_force` 접근·눌린 쌍), 접촉 스텝 외력을 중력 + `constant_force`로만 셈(접촉 중 `apply_*` 힘), 지속 접촉 판정 끔(눌린 쌍), 제3 바디 동시 접촉 판정 끔(세 공), 용수철 전체 에너지에서 출발 속도 뺌, 진자 감쇠 기본 0, `record()` 속도 없는 샘플 건너뜀 — 모두 실패했다. Task 4a 리뷰 반영: 출발 접촉을 놓을 때 읽음(처음 연 실험의 바닥 던지기·바닥 위 공, 얼어 있던 공), 지면 한정 끔(다른 공에 스친 낙하), 수평 바닥 던지기 즉시 착지 끔, 무중력 바닥 공 착지 처리(INF 시간), 낙하선 배치 허용, 공끼리 충돌, 샘플 없이 그래프 리비전 증가, 발사 높이 스냅을 엔진 출발점에 안 씀 — 모두 실패했다. 2차 리뷰 반영: 착지를 이전 규칙(엔진 보고 또는 착지 시간 ≤ dt)으로 되돌림(바닥 짧은 튐·5 mm 낙하·120 Hz), 그래프 점을 엔진 착지 기준으로 되돌림(바닥 짧은 튐·5 mm 낙하), 측정값을 엔진 보고만으로(바닥 짧은 튐·5 mm 낙하), `release()`의 dt 설정 제거(120 Hz), `landing_time`을 이전 식으로(경계 벡터 parity) — 모두 실패했다.
5. **CI**: `.github/workflows/ci.yml`이 PR과 dev·main push마다 Node 테스트·빌드와 Godot 4.7.2 헤드리스 테스트(앱·스파이크)를 돌린다. 앱 [README "테스트와 CI"](../README.md#테스트와-ci).

새 실험(Task 4)은 이 표의 방식 중 하나를 고르고, 쓰는 법칙을 `formula-vectors.test.ts`의 해당 그룹에 더한 뒤 화면 수치는 보정기의 `formula_values()`(또는 `PhysicsLaws`)에서만 가져온다.
