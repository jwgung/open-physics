# Open Physics 3D (apps/lab3d)

역학 3D 실험 앱이다. Godot 4.7.2 + Jolt, GDScript. Phase 1 Task 2a에서 셸 뼈대(실험 등록, 카메라·제스처, 2D 패널, 품질 설정)와 첫 실험(빗면 마찰)을 만들었고, Task 2c에서 시각 스타일(잔디 섬: 선명한 원색, 각진 로우폴리, 하늘에 뜬 잔디 섬)과 연출을 정했다. Task 2b에서 한 손가락으로 물체를 집어 정해진 면 위로 옮기는 조작(조작 평면·스냅·높이 손잡이·보조 시점)을 더했다. Task 3에서 역학 안내형 10개 실험이 쓸 공식 보정 계층(`scripts/formula/`)과 TS↔GDScript parity, CI를 만들었다([공식 보정](docs/formula-correction.md)). Task 4a에서 실험 문구를 웹 2D와 공유하는 JSON으로 빼고(1절 "콘텐츠 공유"), 균일장 실험 두 개(자유 낙하, 던지기)를 더했다(1절 "실험 목록"). Task 4b에서 접촉 힘 실험 마찰 밀기를, Task 4c에서 충돌 실험을, Task 4d에서 공식 모델 구동 실험 셋(용수철, 부력, 궤도: `BodyModelDriver`. 힘 주입 보정기는 대표 장면·빈 실험실용)을, Task 4e에서 해석 모델 구동 실험 셋(줄·막대 진자, 지렛대, 도르래)을 더했다. Task 2d에서 앱을 가로 전용으로 바꾸고 실험 화면을 3D 전체 + 핵심 관찰값 카드 + 오른쪽 사이드바로 개편했다(1절 "레이아웃과 해상도"). 기준은 [아트 디렉션](docs/art-direction.md)이다. 계획과 진행은 [Phase 1 문서](../../docs/3d-phase1/README.md), 스택 결정은 [ADR 0001](../../docs/adr/0001-3d-app-stack.md)에 있다.

- Android: arm64-v8a release APK(디버그 키스토어 서명, 배포용 아님). 렌더러는 품질 단계가 정한다(low = Compatibility, medium·high = Mobile).
- 모든 작업은 헤드리스 CLI(`godot --headless`)로 한다. 에디터 GUI를 쓰지 않는다.
- `spikes/godot/`은 Phase 0·Task 1 참고용으로 그대로 둔다. 이 앱은 거기서 품질 단계·측정 로그·parity 테스트·빌드 스크립트를 옮겨 왔다.

## 1. 구조

```
apps/lab3d/
  project.godot, export_presets.cfg   Jolt, 60 Hz 고정 스텝, 짧은 변 720 UI 단위, 방향 sensor, Android export
  scenes/main.tscn                    App(루트 Control)
  scripts/core/                       autoload Quality(품질 단계)·Bench(OPBENCH/OPPERF), PhysicsLaws(TS 공식 포트, 10개 실험)
  scripts/formula/                    공식 보정 계층: FormulaCorrector(공통)·FormulaBody·FormulaDriver, 방식별 보정기
  scripts/app/                        App(화면 전환·fps 표시), 목록·설정 화면, UiTheme(섬 스타일 2D), Ui(위젯 헬퍼),
                                      IslandBanner(목록 머리 그림)
  scripts/art/                        셸 공용 아트: ArtPalette, PadProps(받침판 뒤집기·소품 공통), ArtMeshBuilder(로우폴리 메시), art_lit 셰이더(구운 조명),
                                      ArtKit(재질·환경·떠 있는 섬), ArtJuice(연출·블롭 그림자), VelocityArrow(화살표·손잡이 메시),
                                      CatActor(빵고양이 연기·모델 동기화), CatLook·BreadCat(빵고양이 겉모습 = glb), art_lit_tex 셰이더
  scripts/shell/                      Experiment(실험 기반 클래스), ExperimentRegistry, ExperimentScreen,
                                      View3D(3D 뷰·제스처), CameraRig(카메라 6모드·보조 시점), GraphView,
                                      Manipulator(물체 조작), ManipSurface(조작 평면), PressLineSurface(아래로 누르는·당기는 손잡이 선),
                                      RollingGraph(손잡이를 잡은 동안만 흐르는 10초 창 그래프)
  experiments/incline_friction/       빗면 마찰 실험(장면, InclineFrictionCorrector = 접촉 힘 보정 설정, InclineProps 소품)
  experiments/uniform_field/          균일장 실험 공용 기반 UniformFieldLab(중력 선택, 공, 바닥, 보정기 연결, 실행 상태·그래프 샘플·release/reset 공통)
  experiments/free_fall/              자유 낙하 실험(장면, FreeFallProps 소품)
  experiments/projectile/             던지기 실험(장면, ProjectileProps 소품, ArrowSurface = 화살표 손잡이 평면)
  experiments/friction/               마찰 밀기 실험(장면, PushFrictionModel = 표시 수치의 공식 모델, FrictionProps 소품)
  experiments/collision/              충돌 실험(장면, CollisionModel = 웹 충돌 프리셋 공식 모델, CollisionRailDriver = 공 구동, CollisionProps 소품)
  experiments/spring/                 용수철 실험(장면, SpringModel = 정확한 해, SpringProps 소품)
  experiments/buoyancy/               부력 실험(장면, BuoyancyModel, BuoyancyProps 소품)
  experiments/orbit/                  궤도 실험(장면, OrbitModel, OrbitArrowSurface, OrbitProps 소품)
  experiments/constraints/            줄·막대 진자 실험(장면, PendulumLabModel = 웹 PendulumModel 방정식의 RK4, PendulumArcSurface = 원 위 끌기, ConstraintsProps 소품)
  experiments/rotation/               지렛대 실험(장면, LeverLabModel = 웹 LeverChallenge, LeverLabDriver = 막대·짐 구동, RotationProps 소품)
  experiments/pulley/                 도르래 실험(장면, PulleyLabModel = 웹 PulleyAdvantageChallenge, PulleyLabDriver = 짐 구동, PulleyProps 소품)
  experiments/manipulation_dev/       조작 확인용 개발 장면(목록에 없음, --experiment=manipulation-dev)
  content/mechanics-labs.json         역학 실험 문구(웹 2D와 공유, "콘텐츠 공유")
  content/experiments/                실험 정의 JSON(index.json + 실험별 파일: 3D 전용 필드)
  assets/characters/                  빵고양이 glb + 텍스처 아틀라스(소스: art_src/characters/bread_cat.py, Blender 스크립트)
  assets/props/                       털실 공·택배 박스 glb + 텍스처(소스: art_src/props/yarn_ball.py, parcel_box.py)
  art_src/                            캐릭터·소품 생성 Blender 스크립트(외부 .blend 없음)
  assets/fonts/                       Noto Sans CJK KR 서브셋(Regular·Bold, SIL OFL 1.1), 기호 대체 글꼴
                                      DejaVu Sans 서브셋(Lab3dSymbols, Bitstream Vera 라이선스)
  tests/                              헤드리스 테스트, TS 생성 parity 벡터
  tools/                              빌드·글꼴·벡터 생성·실기기 측정·제스처 도구
  docs/ui-resolution.md               low 단계 UI 해상도 방식 결정과 측정 근거
  docs/art-direction.md               스타일 가이드(팔레트, 형태, 조명, 연출, 성능 예산, 새 실험 소품)
  docs/formula-correction.md          공식 보정: Jolt 조사, 보정 방식, 실험 10개 표, 테스트 파이프라인
```

화면 흐름은 실험 목록 → 실험 화면이고, 두 화면 모두 위쪽 `설정`에서 품질 설정 화면으로 간다. Android 뒤로 가기는 실험 → 목록 → 종료 순서다(실험 화면에서 사이드바가 열려 있으면 먼저 사이드바를 닫는다). 실험 화면에서 설정을 열어도 실험 화면은 해제되지 않고 보관돼, 돌아오면 각도·재질·놓기 상태·카메라가 그대로다. 같은 렌더러에서 품질(medium ↔ high)을 바꾸면 3D 뷰를 다시 만들며 이때는 조건 값·카메라·사이드바 열림만 유지한다. 렌더러가 바뀌는 재시작은 앱이 다시 뜨므로 실험 화면 상태는 유지되지 않고 설정 화면으로 돌아온다. 실행 인자(`--ctl-*`, `--camera` 등)는 `--experiment`로 연 실험 화면에만 적용한다.

### 셸과 실험의 경계

셸(`ExperimentScreen`)이 카메라·제스처·2D 화면(3D 위 카드·버튼, 사이드바)·품질을 맡고, 실험은 3D 월드와 물리만 맡는다.

| 셸이 하는 일 | 실험이 답하는 것(`Experiment`) |
|---|---|
| 3D 위에 핵심 관찰값 카드(`key_observations`)·액션 버튼을, 사이드바에 질문·시점·조건·관찰값·그래프·설명을 그린다 | `set_control(id, value)` · `control_value(id)` · `run_action(id)` |
| 관찰값·그래프를 10 Hz로 갱신한다 | `observations()` → `{id: 숫자 또는 문자열}`, `graph_series()` → `{시리즈 id: PackedVector2Array}` |
| 카메라 모드·제한을 처리한다(기본 정면) | `follow_point()`(따라가기 대상), JSON의 `camera` |
| 3D를 품질 단계 해상도의 SubViewport에 그린다 | 장면은 `ArtKit`·`ArtMeshBuilder`로 꾸민다(엔진 조명·그림자 없음, [아트 디렉션](docs/art-direction.md)) |
| 착지 때 카메라를 살짝 흔든다(`CameraRig.nudge`) | `impact(strength)` 신호(연출용, 선택) |
| 한 손가락 조작: 집기·끌기·스냅·미리보기·높이 손잡이·취소·보조 시점(`Manipulator`) | JSON `manipulation`의 규칙, `manipulation_body`·`manipulation_surface`·`manipulation_juice`, 결과 통보(`manipulation_started`·`_placed`·`_cancelled`), 추가 규칙 `placement_allowed`, 화면 재구성 때 유지할 `placements()` |

콘텐츠(문구·조건·관찰값·그래프·시점)는 JSON 데이터다. 문구는 웹 2D와 같은 파일을 쓴다(아래 "콘텐츠 공유").

### 실험 목록

목록 화면 순서는 `content/experiments/index.json`이다. 문구는 모두 `content/mechanics-labs.json`(웹 2D와 공유)에서 온다.

| 실험 (id) | 웹 2D | 보정 방식 | 조건 | 조작 | 관찰값(공식) · 시뮬레이션 | 그래프 | Task |
|---|---|---|---|---|---|---|---|
| 자유 낙하 (`free-fall`) | 같은 실험(`free-fall`) | 균일장 출발 보정 | 중력(무중력·달 1.62·지구 9.81·목성 24.79, 웹 버튼), 세 공의 출발 높이(0.5–8 m), 빨간 공 무게(0.5·1·3 kg, 웹 무게 버튼) | 공을 바닥 선(x −3…3 m, z 0) 위로 0.5 m 눈금으로 끌기, 공마다 높이 손잡이(0–8 m, 0.5 m) | g, 시간, 상태, 빨간 공 바닥까지 √(2h₀/g), 세 공 높이, 빨간 공 속력·운동량·운동·위치 에너지 · 세 공의 착지 시각(시뮬레이션) | 바닥까지 남은 높이(세 공 공식 선 + 시뮬레이션 점) | 4a |
| 던지기 (`projectile`) | 같은 실험(`projectile`) | 균일장 출발 보정 | 중력(같음), 각도(0–90°, 15°), 빠르기(1–9 m/s, 0.5) | 보라색 화살표 끝 노란 손잡이를 던지는 세로 평면에서 끌기(각도 15°·빠르기 0.5 m/s로 스냅, 웹 화살표와 같은 규칙), 공을 발사 선(x −8…−3 m) 위로 끌기, 발사 높이 손잡이(0–3 m, 0.25 m) | g, 시간, 상태, 던지는 높이, 날아가는 거리 R·비행 시간 T·최고점 H, 지금 x·y·옆/위아래 속도 · 착지 거리(시뮬레이션) | 발사체의 높이(공식 y(t) + 시뮬레이션 점) | 4a |
| 마찰 밀기 (`friction`) | 같은 실험(`friction`) | 접촉 힘 보정(`push`) | 재질(고무·나무·금속·점토, 웹 MATERIALS: μs = 마찰 + 0.18, μk = 마찰), 무게(가벼움 0.5·보통 1·무거움 3 kg = 웹 무게 버튼, 처음 상자 8 kg = 웹 시작 상자, 기본) | 빨간 손잡이를 바닥 선(집은 자리 ±4 m)을 따라 끌기: 집은 자리에서 5 cm 눈금마다 1 N(±80 N), 놓으면 0 N(손잡이는 상자 옆으로 돌아감) | 상태(멈춤·버팀·움직임·바닥 끝), 주는 힘, 최대 정지 마찰력 μs·mg, 지금 마찰력, 운동 마찰력 μk·mg, 속력, 열에너지(마찰이 한 일), 처음 자리에서 간 거리 · 간 거리(시뮬레이션) | 미는 힘과 버티는 힘(주는 힘·최대 정지 마찰력·마찰력, 최근 10초) | 4b |
| 충돌 (`collision`) | 같은 실험(`collision`) | 공식 모델 구동(`kinematic_model`, 웹 충돌 프리셋) | 공마다 질량(0.5–10 kg, 웹 질량 입력), 재질(고무 0.88·나무 0.5·금속 0.72·점토 0.08 = 웹 MATERIALS 반발계수), 속도(−9…9 m/s, 0.1 m/s; 기본 A 1 kg 3.4 m/s, B 2 kg −1.7 m/s = 웹 시작) | 공을 레일의 자기 쪽 절반(A x −6.5…−0.5, B 0.5…6.5 m) 위로 0.5 m 눈금으로 끌기, 공 위 노란 손잡이를 레일 방향으로 끌어 속도(0.5 m/s 눈금, 0.4 m당 1 m/s, ±9 m/s) | 상태(출발 전·굴러가는 중·충돌!·충돌 뒤·멈춤), 이번 충돌 반발계수 e, 충돌 전·뒤 속도 A·B, 운동량 합 충돌 전·뒤, 충격량 A·B(Δp), 운동 에너지 합 충돌 전·뒤  (모두 공식 모델 값: 엔진 공이 모델 위치에 놓여 독립 측정이 없음) | 두 물체의 운동량(공 A·B, 부호 있음, 10초) | 4c |
| 용수철 (`spring`) | 같은 실험(`spring`) | 공식 모델 구동(`kinematic_model`, `BodyModelDriver`) | 공 질량(0.5–5 kg, 기본 1 kg), 감쇠(없음·조금 b = 0.45 = 웹), k = 5 N/m 고정 | 공을 막대를 따라 끌었다 놓으면 그 자리(−1.5…2.5 m, 0.1 m 눈금)에서 정지 출발 | 상태, 늘어난 길이, 속력, 복원력, 가속도, K, U, K + U, 고유 주기 T₀ = 2π√(m/k), 실제 왕복 주기 T = 2π/ω_d(감쇠 없으면 T₀) (모두 공식 모델 값) | 에너지 비율(%, 고정 0–100 %축): 운동·탄성 | 4d |
| 부력 (`buoyancy`) | 같은 실험(`buoyancy`) | 공식 모델 구동(`kinematic_model`) | 통 질량(5–150 kg, 기본 70 kg), 부피(100 L·50 L), 물 1000 kg/m³ | 통을 물탱크 안 세로 선을 따라 위아래로(0.05 m 눈금, 서 있는 채로) 끌었다 놓으면 그 높이에서 정지 출발 | 상태, 밀도로 본 결과(뜸·중성·가라앉음), 밀도, 뜰 때 잠기는 깊이 ρ/ρ물 × 높이, 지금 잠긴 깊이, 부력, 무게, 알짜힘, 속력 | 잠긴 깊이(+ 뜰 때 깊이 공식 선) | 4d |
| 궤도 (`orbit`) | 같은 실험(`orbit`) | 공식 모델 구동(`kinematic_model`) | 발사 속력(0–6 m/s, 0.1)·방향(0–355°, 5°), 출발 반지름(2–5 m, 0.5; 기본 3 m, 3 m/s = 웹 원 궤도) | 보라 화살표 끝 노란 손잡이를 궤도면에서 끌어 속력·방향(0.1 m/s·5° 눈금), 행성을 2–5 m 선을 따라 끌어 출발 반지름. 발사 전 예측 경로(점선) 미리보기 | 상태, 예상 결과(`OrbitChallenge`), 발사·원 궤도·탈출 속력, 지금 반지름, 원 궤도 예상 주기, 지금 속력, 한 바퀴 걸린 시간 | 지금 속력과 지금 반지름의 원 궤도·탈출 속력 | 4d |
| 지렛대 (`rotation`) | 같은 실험(`rotation`) | 공식 모델 구동(`kinematic_model`, `LeverLabDriver`) | 짐 질량(1–20 kg, 기본 20 kg = 웹), 힘점(가까이·중간·멀리 = 웹 세 힘점, 받침점–오른쪽 끝의 35·60·90 %) | 빨간 손잡이를 아래로 눌러 힘(2 cm마다 5 N. 끝까지 눌러도 모자라는 무거운 조건은 10·20·50 N으로 자동으로 커져, 모든 조건에서 끝까지 누르면 들림), 짐(막대 위 왼쪽 끝…받침점 −0.5 m)·받침점(−1.5…1.5 m)을 0.25 m 눈금으로 끌기 | 상태, 짐 무게 F₂ = mg, 받침점–짐 거리 r₂, 받침점–힘점 거리 r₁, 필요한 힘 F₂r₂/r₁, 내가 누르는 힘 F₁, 손잡이 2 cm당 힘, 역학적 이득 r₁/r₂, 양쪽 토크와 토크 합(들리면 0) | 지렛대에 필요한 힘(누르는 힘·필요한 힘, 잡은 동안 10초 창) | 4e |
| 줄·막대 (`constraints`) | 같은 실험(`constraints`) | 공식 모델 구동(`kinematic_model`, `BodyModelGroupDriver`) | 중력(무중력·달·지구·목성, 웹 버튼), 줄·막대 길이(1–3.5 m, 0.25), 감쇠(조금 = 웹 줄 0.06·막대 0.03 /s, 없음) | 줄 추·막대 추를 원(반지름 L) 위로 5° 눈금(±75°)으로 끌었다 놓으면 두 추가 그 각도에서 정지 출발 | 상태, 길이 L, 두 추의 고정점–추 거리 \|A − B\|, 각도, 작은 각도 주기 2π√(L/g), 모델에서 잰 왕복 시간, 줄·막대가 당기는 힘 mg cos θ + mv²/L | 두 진자의 각도(부호 있는 ±90° 고정 축) | 4e |
| 도르래 (`pulley`) | 같은 실험(`pulley`) | 공식 모델 구동(`kinematic_model`, `PulleyLabDriver`) | 짐을 받치는 줄(1·2·4줄, 웹 버튼. 잡은 채 바꾸면 처음으로와 같이 다시 시작), 짐 질량(1–20 kg, 기본 20 kg) | 빨간 손잡이를 아래로 당김(5 cm 눈금, 한 번 최대 2.6 m. 손잡이 이동 = 당긴 줄, 짐은 그 1/n): 놓으면 멈추개가 짐을 잡고 손잡이는 위로(손 바꿔 당기기), 짐 최고 2.4 m | 상태, n, 짐 무게, 필요한 힘 mg/n, 내가 당기는 힘, 당긴 줄 d당김, 올라간 높이 d당김/n, 1 m에 당기는 줄 n m, 내가 한 일 F·d당김, 위치 에너지 mg·d상승 | 줄 수에 따른 필요한 힘(당기는 힘·필요한 힘, 잡은 동안 10초 창) | 4e |
| 빗면 마찰 (`incline-friction`) | 3D 전용(`app_labs`) | 접촉 힘 보정 | 빗면 각도, 표면 재질 | 상자를 빗면 위 출발 위치로 끌기 | 2a 그대로 | 놓은 뒤 이동 거리 | 2a·2b |

- 균일장 실험은 `UniformFieldLab`(`experiments/uniform_field/`)를 잇는다. 중력 선택지는 공의 `gravity_scale`(= g / 프로젝트 중력 9.81)로 엔진 장을 바꾸고, 보정기에는 64비트 g를 준다. 공은 `FormulaBody` + `UniformFieldCorrector`(놓는 첫 스텝 도약 출발, 엔진 접촉 보고로 엔진 착지 기록), 반지름 0.25 m, 감쇠 0. 공은 자유롭게 돌고(Task 4f) 엔진 마찰·반발은 0이다. 날아가는 동안은 엔진이 움직이고(돌지 않음), 공식 착지 시각부터는 64비트 공 모델(`RollingContact`: 균일한 구 I = 2/5 m r²)이 튕김(e v, 1 m/s 미만이면 멈춤), 튕김의 쿨롱 마찰 충격(μ 0.6), 미끄러짐 → v = ωr 구름, 구름 저항(μ_r 0.05, a = μ_r g) → 정지를 닫힌 식으로 진행하고 엔진 공을 매 스텝 그 자리·회전에 둔다(바닥에 들어가지 않음). 던지기 섬 양끝(x 9.5 / −9.3 m 면, 섬 윗면 안)의 울타리(높이 1.8 m, 두께 0.15 m, 폭 6 / 4.4 m, 시각 메시만)는 모델에서 판자 직사각형이다: 공이 앞면·윗면·뒷면·꼭대기 모서리(원-점)에 닿으면 접촉 법선으로 e v_n 되튀고 접선 쿨롱 마찰 충격을 받는다(바닥 위 공은 면과 바닥 두 접점을 한 충격으로). 굴러온 공은 살짝 떠 되튄 뒤 섬 위에서 멈춘다(기본·가장 먼 던지기 시험). 날아가던 공이 판자에 닿으면(달의 긴 던지기, 무중력의 낮은 던지기) 맞은 공식 시각에 되튀고 상태는 "울타리에 맞음"(공식 거리·비행 시간 그대로, 표시 시간은 맞은 시각에서 멈춤, 시뮬레이션 착지 거리 "—"), 판자에 닿지 않고 넘으면 기존 "섬 밖으로 날아감"이다. 발사 미리보기 점은 울타리에 닿는 곳에서 끝나고 착지 고리는 두 울타리 사이 착지에만 그린다. 공은 털실 공(Task 4g, `assets/props/yarn_ball.glb`, 공 색을 곱한 회색 실 텍스처; 충돌·용수철 공도 같다)이라 구르는 것이 보인다(메시는 바디의 자식. Task 4f의 흰 띠는 사용자 요청으로 털실로 바꿈). 측정 착지 스텝은 공식 접촉 뒤 첫 샘플이다. 규칙·측정: [공식 보정 4절 Task 4f](docs/formula-correction.md#실험-구현-task-4f-공-회전구름). 착지는 바닥에 닿을 때만이다(출발 접촉은 놓은 뒤 첫 스텝 보고, 공끼리는 충돌하지 않는 층). 공식 착지 시간이 0인 공(장 안에서 바닥에 놓음, 바닥에서 수평 던지기)은 놓는 순간 착지다(공식 시계 0 = 착지 시간). 자유 낙하는 한 공의 낙하선 위·아래에 다른 공을 놓을 수 없다. 규칙: [공식 보정 4절 실험 구현](docs/formula-correction.md#실험-구현-task-4a-균일장).
- 화면 수치는 모두 `PhysicsLaws`다: 놓은 뒤 시계(고정 스텝)를 공식 착지 시간(`landing_time`)에서 멈추고 그 시각의 위치·속도·에너지를 보여 준다. "착지됨" 상태도 공식이 정한다: 시계가 공식 착지 시간에 닿았거나(반올림 여유 1e-9 s) 그 전에 엔진이 착지를 보고하면 착지이고, 그때부터 공식 착지 값(t = T, h = 0)을 보여 준다. 엔진 값은 "시뮬레이션"이 붙은 착지 시각·착지 거리와 그래프 점뿐이다. 측정 착지는 엔진 착지 보고의 스텝이고, 보고가 없으면(바닥 몇 mm 위 낙하, 바닥에서 짧은 튐처럼 출발 바닥 접촉이 끝나지 않는 경우) 공식 착지 시각에 가장 가까운 스텝의 엔진 값(그 스텝 시각, 그 스텝의 엔진 x)이다. 그래프 시뮬레이션 점은 공식 착지 시각까지만 더한다.
- 무중력: 자유 낙하는 공이 제자리에 떠 있고("무중력: 떠 있어요", 바닥까지 "닿지 않아요"), 던지기는 곧게 날아가 섬(x 12.5 m, 높이 30 m)을 벗어나면 멈추고 숨긴다("섬 밖으로 날아감"). 달처럼 멀리 가는 던지기도 같다(공식 거리·시간은 그대로 표시).
- 놓기 연출: 대기 중인 공 아래 노란 받침판이 놓을 때 아래로 젖혀지며 사라지고 공이 늘어난다(`stretch`). 처음으로·조건 변경 때 공이 다시 나타난다(`pop`). 착지는 ArtJuice 자동 반응(납작·먼지·카메라)이다.
- 던지기 궤적: 공식 경로 점 28개(MultiMesh 1개)와 공식 착지 고리를 조건·출발점이 바뀔 때만 다시 놓는다. 화살표 손잡이·공을 끄는 동안 그 자리에서의 화살표·경로를 미리 보여 준다.
- 마찰 밀기: 상자(0.7 m, 회전 잠금)는 `FormulaBody` + `ContactFrictionCorrector`(법칙 `push`, 엔진 마찰 0)로 움직인다. 화면 수치·상태·그래프는 `PushFrictionModel`(같은 `PushFrictionLaw` 포트를 같은 스텝 규칙으로 64비트 진행: 떠나는 스텝 절반 힘, v += F/m dt, x += v dt)이 내고, 엔진 상자는 "간 거리(시뮬레이션)"뿐이다. 열에너지 = −Σ work(마찰력, 스텝 변위) = μk·mg × 미끄러진 거리. 손잡이를 쥐고 있는 동안 힘 = 손잡이 격자 칸 수 × 1 N(손잡이 위치를 매 스텝 읽음). 상자가 트랙 끝(±6 m)에 닿으면 공식이 멈추고(범퍼, 상태 "바닥 끝에 닿았어요") 엔진 상자를 그 자리에 얼린다. 다시 손잡이를 집으면 풀린다. 조건을 바꾸거나 `처음으로`를 누르면 상자가 출발선(x −3 m)으로 돌아가고 열에너지·그래프가 0부터 다시 시작한다. 그래프 시간은 힘이 있거나 상자가 움직이는 스텝만 센다. 규칙: [공식 보정 4절 실험 구현(Task 4b)](docs/formula-correction.md#실험-구현-task-4b-마찰-밀기).
- 빵고양이 (Task 4g): 던지기와 마찰 밀기에서 빵봉투 고양이가 학생 조작을 대신 연기한다. 물리는 모델, 고양이는 연기다(바디·충돌 없음, 움직임·패널 불변). 던지기에는 발사 기둥·받침판이 없고 고양이 손이 발사점이다(높으면 나무 빵 상자 위에 선다). `공 놓기`는 오버핸드 던지기 0.48초(감기 → 정지에서 점점 빨라지는 휘두르기, 놓기 직전 손이 발사 방향으로 가장 빠름)를 시작하고, 공이 손을 떠나는 프레임(손 = 공식 발사점)에 `release()`가 실행된다. 공식 시계·엔진 공은 그 프레임부터 직접 놓기와 같다. 그동안 공 바디는 발사점에서 기다리고 메시만 손을 따라간다. 밀기에서는 두 앞발이 상자 −x 면에 붙어 함께 가고, 힘에 따라 기운다. 연기 `CatActor`와 겉모습 `CatLook`(`BreadCat` = `assets/characters/bread_cat.glb`)이 나뉘어 있다. 규칙·모양·예산: [아트 디렉션 11절](docs/art-direction.md#11-빵고양이-task-4g).
- 충돌: 두 공(반지름 A 0.4·B 0.5 m, 웹 32·40 px 공의 비율)이 레일(벽 = 범퍼 면 x ±7 m) 위에서 움직인다. 움직임과 화면 수치·상태·그래프는 모두 `CollisionModel`이다: 웹 충돌 프리셋을 레일에서 64비트로 진행한다(TS world 명시적 오일러 x += v dt → world.ts 충돌: 겹치면 질량 역비로 밀어내고 다가가면 `world_collision_velocities`, 반발 min(eA, eB), 1 m/s 미만 e = 0 → 프리셋 감쇠 v ×= e^(−0.15 dt), 2 px/s(1/24 m/s) 미만 정지 → 벽을 넘으면 벽에 두고 바깥으로 가면 v ×= −e). `CollisionRailDriver`가 매 스텝 물리 서버 전에 엔진 공(얼린 키네마틱 바디)을 모델 상태에 두므로 화면 속 공은 공식 궤적 그대로다(검사: 위치 ≤ 2.4e-7 m, 스텝 속도 ≤ 2.8e-5 m/s). 두 공은 Jolt 안에서 서로 닿지 않는다(충돌 예외, 마스크 0): 언제 닿고 어떻게 튀는지는 공식이 정한다. Jolt 접촉 + `CollisionCorrector`를 쓰지 않은 이유와 측정은 [공식 보정 4절 Task 4c](docs/formula-correction.md#실험-구현-task-4c-충돌). "충돌 전" 값은 첫 충돌 전에는 지금 값(감쇠로 줄어듦), 첫 충돌 뒤에는 그 순간 값이다. 웹처럼 첫 충돌만 기록하되, 웹이 충격량 표시를 건너뛰는 1 m/s 미만 충돌도 기록한다(e = 0, 함께 움직임). 공을 집거나 조건을 바꾸면 두 공이 출발 자리로 돌아간다. 구르는 모습은 공 바디가 아니라 자식 메시만 돌린다(이동 거리/반지름 = v = ωr 구름, Task 4f 시험).
- 용수철·부력·궤도(Task 4d): 한 바디를 64비트 공식 모델에 매 스텝 놓는 `BodyModelDriver`로 구동한다(충돌 레일 구동과 같은 방식, 엔진 바디는 얼린 키네마틱·충돌 없음). 용수철 `SpringModel`은 AnchoredSpringLaw(k = 5 N/m)의 정확한 해(감쇠 b = 0.45는 감쇠 진동 해), 부력 `BuoyancyModel`은 BuoyancyRegionLaw(잠긴 비율 선형, 물 저항 1.8/s)와 중력의 반암시적 오일러 4번 나눔(웹 바닥 규칙 e 0.5·1 m/s 미만 정지), 궤도 `OrbitModel`은 PointGravityField(GM 27)의 속도 Verlet 8번 나눔. 웹의 명시적 오일러는 에너지가 늘거나(용수철 10초에 +52 %) 궤도가 퍼지고(반지름 3 → 3.83 m, 20초) 부력 깊이가 0.72 m 벗어나 따르지 않았다. 표시 수치는 모두 공식 모델 값이고 "시뮬레이션" 관찰값은 없다. 조건을 바꾸거나 물체를 집으면 새 출발 자리로 돌아간다. 오라클·측정: [공식 보정 4절 Task 4d](docs/formula-correction.md#실험-구현-task-4d-용수철-부력-궤도).
- 진자·지렛대·도르래(Task 4e): 웹 공식 모델을 64비트로 진행하고 엔진 바디(얼린 키네마틱, 충돌 없음)를 매 스텝 그 자세에 둔다(4c·4d와 같음). 진자 `PendulumLabModel`은 웹 `PendulumModel`의 운동 방정식을 RK4로 스텝당 4번 나눠 적분하고(웹 60 Hz 반암시적 오일러는 2 m 진자가 20초에 2.3 cm 벗어나 따르지 않음), 두 추를 `BodyModelGroupDriver`가 구동한다. 끄는 동안 추는 원 위에만 있어 고정점–추 거리가 늘 L이다. 지렛대 `LeverLabModel`은 `LeverChallenge`(필요한 힘에서 멈추는 힘, 들림 각 0.18 rad), 도르래 `PulleyLabModel`은 `PulleyAdvantageChallenge`(당긴 줄은 5 cm 칸 수로 셈)다. 지렛대·도르래 그래프는 손잡이를 잡은 동안만 시간이 흐르는 10초 창이고(웹도 끄는 동안 그래프 시간이 흐름), 조건이 바뀌면 그 시각에 점이 하나 더해진다(시계가 멈춘 채 같은 시각에 거듭 바뀌면 전·후 두 점만 두고 마지막 점을 덮어쓰며, 점은 최대 512개). 두 실험의 손잡이·시계·그래프는 공용 베이스 `PressHandleLab`(`scripts/shell/press_handle_lab.gd`)이 맡고, 막대·짐은 자세가 바뀔 때만 엔진에서 옮긴다. 지렛대 손잡이 힘은 조건마다 가장 작은 눈금(2 cm당 5·10·20·50 N)을 골라 끝까지 누르면 필요한 힘(최대 1588 N)에 닿는다. 사용자 결정(2026-10-23): 도르래는 손잡이 이동 = 당긴 줄, 짐 1/n을 유지하되 웹 배율(n/4)을 전제한 단계 3·관찰 문구를 앱 전용(`app.steps`·`app.observe`)으로 물리대로 바꾸고, 지렛대·진자는 동작을 유지하되 지렛대 관찰에 "손잡이를 누르고 있는 동안"을 덧붙인다. 오라클·측정·웹과 다르게 정한 점: [공식 보정 4절 Task 4e](docs/formula-correction.md#실험-구현-task-4e-진자지렛대도르래).
- 끄는 동안 공은 바닥 선을 따라 움직인다(자유 낙하). 5 m 높이에 든 공을 바닥과 나란한 평면으로 끌면 카메라 높이와 거의 같아 평면을 옆에서 보게 되기 때문이다. 높이는 손잡이로 바꾼다.

### 핵심 관찰값과 정면 시점 (Task 2d)

실험 화면에 늘 보이는 값은 실험 정의의 `key_observations`(2~3개)다. 실험 질문에 답하는 값을 골랐고, 카드 글자는 사이드바 관찰 타일과 같다(같은 서식 함수 `ExperimentScreen.format_observation`). 기본 시점은 모두 정면이다.

| 실험 | 질문 | 핵심 관찰값 (id) | 정면 시점 조정 |
|---|---|---|---|
| 자유 낙하 | 가벼운 공과 무거운 공은 바닥에 닿는 시간이 다를까? | 놓은 뒤 시간 t (`time`), 빨간 공이 바닥까지 √(2h₀/g) (`fall_time`), 빨간 공 속력 v = gt (`speed`) | 거리 13.5 → 16 m, 대상 높이 4.6 m(8 m 높이 자가 카드 아래에 보임) |
| 던지기 | 어느 방향으로 던질 때 가장 멀리 갈까? | 날아가는 거리 R (`range`), 비행 시간 T (`flight_time`), 착지 거리(시뮬레이션) (`landing`) | 거리 13.5 → 14.5 m, 대상 높이 2.6 m |
| 충돌 | 두 공의 무게가 달라지면 충돌 뒤 움직임은? | 충돌 뒤 속도 A·B (`after_a`, `after_b`), 운동량 합 · 충돌 뒤 (`p_after`) | 그대로 |
| 용수철 | 더 멀리 당기면 얼마나 빨라질까? | 늘어난 길이 x (`extension`), 속력 (`speed`), 역학적 에너지 K + U (`total`) | 그대로 |
| 마찰 밀기 | 버티다가 움직이기 시작하는 힘은? | 내가 주는 힘 F (`applied`), 최대 정지 마찰력 (`max_static`), 상자 상태 (`state`) | 그대로 |
| 지렛대 | 받침점에서 멀리 누르면 더 쉬울까? | 받침점–힘점 거리 r₁ (`effort_arm`), 필요한 힘 F₂r₂/r₁ (`required`), 내가 누르는 힘 F₁ (`applied`) | 그대로 |
| 궤도 | 발사를 조금 바꾸면 충돌·공전·이탈 중 무엇이 될까? | 상태 (`state`), 발사 속력 (`launch_speed`), 탈출 속력 (`escape_speed`) | 내려다보는 각 −10° → −40°(공전면이 보이고, 손잡이를 끌 때 보조 시점이 돌지 않음) |
| 부력 | 무게를 바꾸면 잠기는 정도가 어떻게 달라질까? | 지금 잠긴 깊이 (`depth`), 뜰 때 잠기는 깊이 (`floating_depth`), 부력 (`buoyant`) | 그대로 |
| 줄·막대 | 줄과 막대에 매단 추는 어떤 길로 움직일까? | 줄·막대 고정점–추 거리 (`rope_distance`, `rod_distance`), 작은 각도 주기 (`small_period`) | 그대로 |
| 도르래 | 받치는 줄을 늘리면 필요한 힘은? | 받치는 줄 n (`strands`), 필요한 힘 F = mg/n (`required`), 짐이 올라간 높이 (`lift`) | 거리 10.5 → 12 m, 대상 높이 2.9 m(위 보가 카드에 안 가림) |
| 빗면 마찰 | 어느 각도에서 미끄러지기 시작할까? | 임계각 θc (`critical_angle`), 상자 상태 (`state`), 가속도 a (`acceleration`) | 그대로 |

- 개발 장면(`manipulation-dev`, 목록에 없음)은 바닥 조작 확인용이라 3/4 시점을 유지했다(정면은 바닥을 스치듯 본다). 핵심 값은 세 상자 높이다.


### 콘텐츠 공유 (Task 4a)

역학 안내형 실험의 문구는 `content/mechanics-labs.json` 한 파일에 있고, 웹 2D와 3D 앱이 함께 읽는다.

| 위치 | 내용 | 읽는 곳 |
|---|---|---|
| `content/mechanics-labs.json` `labs` | 웹 2D의 10개 실험(웹 목록 순서): `id`, `title`, `category`, `icon`, `question`, `steps`(3개), `observe`, `terms`, `law`, 플랫폼별 조작 안내 `web`(`controls` = 웹 조건 패널, `tip`)·`app`(`tip` = 사이드바의 전체 문구, `tip_short` = 처음에만 잠깐 뜨는 한 줄, 3D로 옮긴 실험만. 3D 동작이 웹과 달라 공유 문구가 맞지 않으면 `steps`(3개)·`observe`로 3D 앱 전용 문구를 덮어씀: 도르래, 지렛대. 웹은 `app`을 읽지 않아 웹 문구·SHA 불변) | 웹 `src/app/mechanics-labs.ts`(`import { labs }`, `parseMechanicsLabs`가 id·분류·단계 수·조건을 검사), 앱 `ExperimentRegistry` |
| 같은 파일 `app_labs` | 3D 앱에만 있는 실험(빗면 마찰) | 앱 |
| `content/experiments/<id>.json` | 3D 전용 필드: `content`(공유 실험 id), `scene`, `bench_id`, `camera`, `controls`, `actions`, `observations`, `graph`, `manipulation` | 앱 |

- `ExperimentRegistry.resolve()`가 `content`의 문구(`title`·`category`·`icon`·`question`·`steps`·`observe`·`terms`·`law`, `tip` = `app.tip`)를 실험 정의에 합친다. 실험 파일에 문구를 함께 쓰면 오류로 빼고, 없는 id도 오류다. `content`가 없는 파일(개발 장면)은 문구를 직접 쓴다.
- 웹의 조작 안내(`web.tip`)와 앱의 조작 안내(`app.tip`)는 조작 방식이 달라 따로 둔다. 질문·단계·관찰·용어·법칙은 하나다.
- 웹 불변 확인: `src/app/mechanics-labs.test.ts`가 웹이 읽은 10개 실험과 조작 팁의 SHA-256이 옮기기 전(4cb04a4) TS 리터럴과 같은지 본다(한 글자 바꾸면 실패). 웹 빌드(`vite build`)의 한글 문자열 2,083개는 옮기기 전과 같다(압축된 변수 이름만 다름). `import { labs }`라 `app_labs`·설명 문구는 웹 번들에 들어가지 않는다.
- 공유 파일의 기호 중 Noto Sans CJK에 없는 것(`x₀`의 아래 첨자, `⚖`·`⌁`·`▰` 아이콘)은 DejaVu Sans 서브셋을 대체 글꼴로 그린다(`tools/subset_font.sh`가 두 서브셋을 함께 만든다).

### 공식 보정 계층 (Task 3)

안내형 실험의 핵심 운동과 화면 수치를 TS 공식 코어에 맞추는 공용 계층이다. 실험은 보정 방식 하나를 골라 보정기를 붙이고, 화면 숫자는 보정기의 `formula_values()`(또는 `PhysicsLaws`)에서만 가져온다. 엔진 측정값(`engine_values()`, `samples`)은 "(시뮬레이션)" 표시와 그래프 측정 점에만 쓴다. 보정은 고정 스텝마다 물리 서버 스텝 **전**(`_physics_process`)에 한다. 근거와 실험별 표는 [docs/formula-correction.md](docs/formula-correction.md).

| 방식 | 보정기 | 실험 |
|---|---|---|
| 접촉 힘 보정 | `ContactFrictionCorrector`(빗면은 `InclineFrictionCorrector`) | 마찰(밀기), 빗면 |
| 균일장 출발 보정 | `UniformFieldCorrector` | 자유 낙하, 던지기 |
| 충돌 결과 보정 | `CollisionCorrector` | 충돌 |
| 공식 힘 주입 | `SpringInjector`, `BuoyancyInjector`, `PointGravityInjector`(대표 장면용. 안내형 용수철·부력·궤도는 공식 모델 구동 `BodyModelDriver`) | 용수철, 부력, 궤도 |
| 해석 모델 구동 | `PendulumModelDriver`, `LeverModelDriver`, `PulleyModelDriver`(대표 장면용. 안내형 실험은 `PendulumLabModel` + `BodyModelGroupDriver`, `LeverLabDriver`, `PulleyLabDriver`) | 줄·막대(진자), 지렛대, 도르래 |

- 한 바디 보정기는 바디를 `FormulaBody`로 만들고 `body.corrector`에 넣는다. 여러 바디를 다루는 보정기(충돌, 모델 구동)는 `FormulaDriver`의 `correctors`에 넣고 `running`을 켠다.
- 실행 순서: 놓는 스텝에 같은 `_physics_process`에서 보정이 시작된다. 그래서 놓기·리셋은 실험의 `_physics_process`나 그 전에 한다(빗면 `release()`와 같다).

### 카메라와 제스처

| 모드 | 동작 |
|---|---|
| 정면 · 3/4 · 위 · 옆 | 실험 JSON `camera.views`의 시점으로 약 0.4초에 걸쳐 부드럽게 옮긴다. 이동·확대는 기본값으로 돌아간다 |
| 따라가기 | `follow_point()`(빗면에서는 상자)를 따라간다 |
| 제한 회전 | 사용자가 돌린 시점. `yaw_range_deg`·`pitch_range_deg`·`distance_range`·`pan_radius` 안에서만 움직인다 |

- 모든 실험의 기본 시점은 정면이다(Task 2d, `camera.default_mode: "front"`). `정면으로` 버튼은 없앴다. 시점 칩(정면·3/4·위·옆·따라가기·제한 회전)은 사이드바 맨 위 "시점" 카드에 있고, 사이드바를 열면 3D 뷰가 옆에 남아 있어 바뀐 시점을 바로 본다. 정면 칩이 정면 + 이동·확대 초기화다.
- 시점마다 `target`(선택, `[x, y, z]`)을 두면 그 시점은 그 점을 본다(없으면 `camera.target`). 정면 시점을 조금 높여 장치 위쪽이 핵심 카드에 가리지 않게 할 때 쓴다(자유 낙하·던지기·도르래). 궤도는 공전면이 보이게 정면 시점을 40° 내려다본다.
- 빗면의 기본 시점(Task 2c): 대상 (0.8, 2.8, 0), 3/4 거리 8.5 m, 정면 9.5 m, 옆 12 m, 따라가기 4 m. 상자(0.4 m)와 연출이 보이게 Task 2a(11 m)보다 당겼다.
- 터치: 두 손가락을 함께 끌면 회전(시점이 프리셋이면 `제한 회전`으로 바뀐다), 벌리거나 오므리면 확대·축소, 그 상태로 손가락을 옮기면 이동, 비틀면 좌우 회전(시작 대비 8°를 넘긴 만큼만 돌려, 확대만 할 때 손 떨림으로 프리셋이 바뀌지 않는다). 두 손가락 제스처는 처음 14 UI 단위 움직임으로 회전과 확대·이동 중 하나로 정한다. 한 손가락을 고정하고 다른 손가락만 움직여도(28 단위 이상) 확대·이동으로 인식한다.
- 한 손가락은 카메라에 쓰지 않는다. `View3D.single_pointer` 신호로 물체 조작(아래 "조작")에 쓴다. 빈 곳 한 손가락 드래그는 아무 일도 하지 않는다.
- 데스크톱: 오른쪽 드래그 회전, 가운데 드래그 또는 Shift + 오른쪽 드래그 이동, 휠 확대·축소. 왼쪽 드래그는 한 손가락과 같다(물체 조작).

### 조작 (Task 2b)

물체를 손가락 하나로 집어, 실험이 정한 면 위에서만 옮기고 놓는다. 높이는 따로 손잡이로 바꾼다. 셸의 `Manipulator`(`scripts/shell/manipulator.gd`)가 맡고, 실험은 어떤 물체를 어떤 면 위에서 어떤 격자로 옮기는지만 정한다.

| 동작 | 사용자가 하는 것 | 일어나는 일 |
|---|---|---|
| 집기 | 물체를 누른다 | 손가락 광선 하나로 조작 가능한 물체만 찾는다. 빗나가면 화면에서 물체 중심이 44 UI 단위 안에 있고 카메라에서 물체 중심까지 다른 물체가 가리지 않는 물체를 집는다(받치고 있는 바닥·면은 가림이 아니다. 0.4 m 상자는 기본 거리에서 화면 폭 약 36 단위라 아이 손끝보다 작다). 물체는 물리에서 얼려지고(freeze) 메시가 12 cm 떠오른다 |
| 끌기 | 누른 채 움직인다 | 손가락 광선을 물체 중심 높이의 조작 평면(바닥, 빗면 윗면)에 투영해 그 자리로 옮긴다. 집을 때의 손가락–물체 간격은 면 위 좌표로 유지해, 보조 시점으로 카메라가 도는 동안에도 물체가 손가락 아래에 남는다. 평면을 7° 안쪽으로 스치는 광선(평면과 거의 나란한 시점)과 뒤쪽을 향하는 광선은 물체를 움직이지 않는다. 선(빗면 출발 위치)은 광선에 가장 가까운 선 위의 점을 쓴다. 놓을 수 있는 영역 밖으로는 최대 0.6 m까지만 나간다 |
| 미리보기 | — | 물체는 손가락을 매끄럽게 따라가고, 발밑 표시(바닥에 닿는 네모 테두리)가 실제로 놓일 격자 칸에 붙는다. 흰색 = 놓을 수 있음, 남색 + X = 놓을 수 없음(영역 밖, 다른 물체·고정 블록과 겹침, 실험의 추가 규칙). 놓을 수 없게 바뀌는 순간 물체가 옆으로 흔들린다 |
| 놓기 | 손가락을 뗀다 | 놓을 수 있으면 격자 칸에 정지 상태로 내려앉는다(메시가 내려오며 살짝 눌림 + 먼지). 놓을 수 없으면 집은 자리로 돌아가며 흔들린다 |
| 취소 | 두 번째 손가락을 댄다, 시스템이 터치를 취소한다, 화면을 떠난다, 조건·버튼을 바꾼다 | 집은 자리로 돌아간다. 두 손가락은 그다음부터 카메라 제스처다 |
| 높이 | 놓은 물체 옆 세로 손잡이(파란 막대 + 노란 손잡이)를 위아래로 끈다 | 실험이 허용한 물체만 손잡이가 보인다. 높이만 바뀌고(면의 법선 방향, 격자 단위) 수평 위치는 그대로다. 손잡이 터치 영역은 반지름 52 UI 단위. 손잡이는 카메라 오른쪽 옆에 붙어 시점을 돌려도 물체에 가리지 않는다. 빈 곳을 누르면 손잡이가 사라진다 |

- 보조 시점: 끄는 동안 카메라가 면 위를 움직이는 물체(화살표·진자 호·궤도 화살표)의 조작 평면을 25° 이상 내려다보고, 선 위를 움직이는 물체(바닥 레인·빗면·막대·누르는 손잡이 등 1차원 표면)·높이 손잡이는 그 선과 시선이 35° 이상 벌어지게 한다. 선은 평면을 보는 조건을 걸지 않는다(손가락 광선에 가장 가까운 선 위의 점을 쓰므로 선만 시선과 나란하지 않으면 어느 방향에서든 끌린다). 그래서 기본 정면 시점(고도 −4~−8°)에서 11개 실험의 어떤 물체를 끌어도 카메라가 돌지 않는다(Task 2d 리뷰: 이전에는 선 표면에서도 평면 25° 조건이 걸려 정면 시점에서 끌 때마다 카메라가 돌았다). 지금 시점이 이미 그러면 움직이지 않는다. 아니면 실험의 회전 제한 안에서 가장 가까운 방위·고도로 0.4초에 걸쳐 돌고, 놓거나 취소하면 원래 시점으로 돌아간다. 끄는 동안 따라가기 대상은 고정한다. 작은 보조 뷰(화면 속 화면) 대신 카메라 보정을 고른 근거는 [Task 2b 결과](../../spikes/bench/results/phase1-task2b/README.md) 2절.
- 비용: 집을 때 광선 1개, 끄는 동안 이벤트마다 평면 계산(광선 없음) + 격자 칸·높이가 바뀔 때만 모양 질의 1개. 발밑 표시·손잡이 메시는 물체마다 한 번 만든다.
- 실험 정의(`content/experiments/<id>.json`의 선택 필드 `manipulation`, `ExperimentRegistry.validate`가 검사):

```json
"manipulation": {
  "objects": [
    { "id": "box", "surface": "incline", "snap": 0.5, "height": false },
    { "id": "red", "surface": "floor", "snap": 0.25, "height": { "max": 2.0, "step": 0.25 } }
  ],
  "demo_action": "release"
}
```

| 필드 | 뜻 |
|---|---|
| `id` | 조작 가능한 물체(실험 스크립트의 `manipulation_body(id)`가 바디를 돌려준다). 중복 불가 |
| `surface` | 옮길 면의 id. 실험 스크립트의 `manipulation_surface(id)`가 지금 모양의 `ManipSurface`(면 좌표계 `frame`, 놓을 수 있는 영역 `region_min`·`region_max`, 겹쳐도 되는 바디 `exclude`)를 돌려준다. z 폭이 0인 영역은 선이다 |
| `snap` | 격자 간격(m, 면 좌표계 원점부터). 0이면 스냅 없음. 스크립트가 `ManipSurface.snap`을 정하면 그쪽이 먼저다 |
| `height` | `false`(높이 손잡이 없음) 또는 `{ "max": m, "step": m }`. 집는 순간에는 지금 높이를 그대로 두고, `step` 단위 반올림은 손잡이로 바꿀 때만 한다 |
| `demo_action` | (manipulation 수준, 선택) `--auto-drag` 데모가 물체를 놓은 뒤 실행할 실험 액션 id. 없으면 놓기만 한다. `actions`에 있는 id여야 한다 |

- 실험 스크립트는 결과를 받아 상태를 바꾼다: `manipulation_started`(멈추기), `manipulation_placed(id, transform)`(새 위치 반영), `manipulation_cancelled`. 셸이 이미 바디를 얼리고 옮겨 둔 뒤 부른다. 놓인 물체가 그다음 어떻게 움직일지는 실험이 정한다(빗면은 새 출발 위치에서 대기, 개발 장면은 `상자 떨어뜨리기` 전까지 그 자리에 고정).
- 빗면: 상자를 빗면 위에서만(빗면 아래 끝에서 1 m ~ 기본 출발점 7.5 m) 0.5 m 눈금으로 옮긴다. 빗면 앞 가장자리에 스냅 격자와 같은 자리(빗면 가운데 기준 `snap`의 배수)마다 짧은 눈금, 1 m마다 긴 눈금이 있다(`snap`이 없으면 눈금도 없다). 미끄러지는 상자나 바닥에 떨어진 상자를 집어도 된다(그 실행은 멈추고 새 출발 위치에서 기다린다). `이동 거리`·그래프 공식 곡선의 상한은 출발점에서 빗면 끝까지의 거리(`출발점에서 빗면 끝까지` 관찰값)다. 예전의 고정 7.5 m는 기본 출발점의 값이다.
- 개발 장면(`--experiment=manipulation-dev`): 바닥 8 × 6 m(흰 테두리) 위 상자 3개와 고정 파란 블록. 0.25 m 격자, 높이 0–2 m(0.25 m 단위). 다른 상자·블록과 겹치는 자리와 테두리 밖에는 놓을 수 없고, 블록보다 높이 올린 상자는 블록 위로 옮길 수 있다. `상자 떨어뜨리기`는 얼린 상자를 풀어 떨어뜨린다. `content/experiments/index.json`의 `hidden`에 있어 목록에는 나오지 않는다.

### 레이아웃과 해상도

- 앱은 가로 전용이다(Task 2d). `display/window/handheld/orientation=4`(sensor landscape: 가로 두 방향만)로 Android export(매니페스트 `screenOrientation`)와 iOS export(`UISupportedInterfaceOrientations`, iOS 프리셋은 아직 없음)가 같은 설정을 쓴다. 목록·설정 화면도 가로다. 세로 레이아웃은 없다.
- `window/stretch`는 `canvas_items` + `expand`, 기준 크기 720×720이다. 화면의 짧은 변(가로 화면의 높이)이 항상 720 UI 단위다(SM-P200에서 1 단위 = 1.67 px). 폰 2340×1080은 1560×720 단위, 태블릿 1920×1200은 1152×720 단위다.
- 실험 화면(사이드바 닫힘, 기본): 3D 뷰가 화면 전체다. 그 위에 왼쪽 위 `← 목록`(Android 뒤로 가기와 같아 열린 사이드바를 먼저 닫음)·제목(창이 아주 좁으면 제목 글자, 그다음 `← 목록` 글자를 줄여 설정 버튼과 겹치지 않음), 오른쪽 위 `설정`·`설명·조건`(사이드바 열기), 제목 아래 핵심 관찰값 카드 2~3개(폭 200, 사이드바 패널과 같은 글자), 오른쪽 아래 실험 액션 버튼(놓기·처음으로 등), 왼쪽 아래 조작 안내 한 줄(`app.tip_short`, 앱 실행 중 그 실험을 처음 열 때만 4초 또는 첫 제스처까지 보이고 페이드아웃. 보여준 것으로 치는 때는 그 페이드가 시작될 때이므로, 그 전에 화면이 다시 만들어지면(조건 변경 등) 한 번 더 뜨고, 보인 뒤에는 다시 열거나 다시 만들어도 안 나옴. 전체 문구 `app.tip`은 사이드바 설명의 "조작 방법" 카드. 액션 버튼 옆 폭이 240 단위보다 좁으면 버튼 위로 올라감). 카드는 터치를 3D로 통과시킨다.
- 사이드바(오른쪽, 470 단위 또는 화면 폭의 42% 중 작은 값): 질문, 시점, 조건 바꾸기, 관찰(전체), 그래프, 설명(단계·관찰 포인트·법칙·용어). `닫기`로 닫는다. 열고 닫을 때 사이드바 노드의 위치만 0.22초 Tween으로 옮긴다(전체 화면 반투명 레이어 없음).
- 사이드바가 열리면 3D 뷰가 왼쪽 남은 영역으로 줄어든다(사이드바가 3D 위에 겹치지 않음). 근거: 장면의 물체가 사이드바 뒤에 가리지 않고, 사이드바는 바탕을 칠하지 않아(clear color가 비침) 겹쳐 칠하는 면적이 늘지 않으며, 3D SubViewport도 작아진다. 뷰 크기는 열 때 한 번(시작에), 닫을 때 한 번(끝에)만 바꾸고 슬라이드 중에는 바꾸지 않는다(크기를 바꿀 때마다 SubViewport를 다시 할당). 3D 뷰가 16:10보다 좁아지면(태블릿에서 사이드바를 열면 거의 정사각형) 16:10 화면의 가로 시야(73.4°)를 유지해 장치 전체가 화면에 남는다(`CameraRig.fit_aspect`).
- low에서도 UI는 원본 해상도로 그린다. 3D만 SubViewport에서 화면 픽셀의 45%로 그린 뒤 늘린다. 근거는 [UI 해상도 결정](docs/ui-resolution.md)이다.
- 배경은 전체 화면 사각형이 아니라 clear color다. 원본 해상도에서는 전체 화면 레이어 하나가 SM-P200의 60 fps 예산을 넘긴다(같은 문서).

### 품질 단계

`scripts/core/quality.gd`(autoload `Quality`). Task 1의 단계에서 "루트 뷰포트 너비"를 "3D 뷰 배율"로 바꿨다.

| 항목 | low | medium | high |
|---|---|---|---|
| 렌더러 | Compatibility (OpenGL ES 3) | Mobile (Vulkan) | Mobile (Vulkan) |
| 3D 뷰 해상도 | 화면 픽셀의 45% (`view_scale` 0.45) | 60% | 100% |
| UI | 원본 해상도 | 원본 해상도 | 원본 해상도 |
| MSAA | 끔 | 2x | 2x |

- 잔디 섬 스타일은 엔진 조명·실시간 그림자를 쓰지 않아 모든 단계에서 블롭 그림자만 보인다(단계 차이는 3D 해상도·MSAA). high에 실시간 그림자를 더하지 않은 근거는 [Task 2c 결과](../../spikes/bench/results/phase1-task2c/README.md).
- 기본 단계는 low다. `project.godot`의 기본 렌더러도 Compatibility라 첫 실행에 재시작이 없다.
- 설정 화면에서 low ↔ medium·high를 바꾸면 렌더러가 달라 앱이 한 번 재시작하고 설정 화면으로 돌아온다(`user://renderer_override.cfg`, 방식은 스파이크와 같다). medium ↔ high는 바로 적용된다.
- 측정용 단일 항목 덮어쓰기: `--q-<항목>=<값>`(저장하지 않음). 예: `--q-ui_mode=root`(Task 1 방식, UI까지 540), `--q-ui_mode=scale3d`, `--q-view_scale=0.6`.

## 2. 실행

Godot 바이너리·export 템플릿은 스파이크와 같은 것을 쓴다(`spikes/godot/tools/setup_editor.sh`, `~/.local/share/godot-spike/`). `GODOT` 환경변수로 바꿀 수 있다.

```bash
GODOT=~/.local/share/godot-spike/godot
$GODOT --path apps/lab3d                                   # 데스크톱(1280×720 창)
$GODOT --path apps/lab3d -- --experiment=incline-friction  # 실험 화면으로 바로
```

Android:

```bash
apps/lab3d/tools/build.sh android
adb install -r apps/lab3d/exports/android/open-physics-lab3d.apk
adb shell am start -n org.openphysics.lab3d/com.godot.game.GodotAppLauncher \
  --es opargs "--experiment=incline-friction,--quality=low"
```

실행 인자(데스크톱은 `--` 뒤, Android는 launch intent의 `opargs` extra에 쉼표로 구분):

| 인자 | 뜻 |
|---|---|
| `--experiment=<id>` | 그 실험 화면으로 시작 |
| `--screen=settings` | 설정 화면으로 시작 |
| `--quality=<low\|medium\|high>` | 품질 단계(저장된다) |
| `--fps=1` | fps 표시 |
| `--camera=<front\|three_quarter\|top\|side\|follow\|orbit>` | 카메라 모드 |
| `--ctl-<조건 id>=<값>` | 조건 값(예: `--ctl-angle=30`, `--ctl-material=rubber`) |
| `--sidebar=open` | 사이드바를 연 채 시작 |
| `--scroll-to=<camera\|conditions\|observations\|graph\|explanation>` | 사이드바를 열고 그 카드로 스크롤 |
| `--auto-release=<초>` | 그 간격으로 상자를 다시 놓는다(측정용) |
| `--auto-drag=<초>` | 그 간격으로 첫 조작 물체를 손가락 입력 경로 그대로 1초 동안 끌어 놓고(영역 끝과 40% 지점을 번갈아), 0.4초 뒤 `상자 놓기`를 누른다(측정용, `bench_device.sh` 기본) |
| `--q-<항목>=<값>` | 품질 단계 항목 덮어쓰기(측정용) |

## 3. 빌드와 테스트

```bash
apps/lab3d/tools/build.sh          # all: import → 헤드리스 테스트 → APK
apps/lab3d/tools/build.sh test     # 헤드리스 테스트만 (exports/test.log)
apps/lab3d/tools/build.sh android  # exports/android/open-physics-lab3d.apk (약 27 MB)
npm test                           # 루트: TS 테스트 + apps/lab3d/tools/{incline,formula}-vectors.test.ts
```

| 테스트 | 위치 | 확인하는 것 |
|---|---|---|
| 벡터 생성·감시 | `tools/incline-vectors.test.ts`(루트 `npm test`) | TS 공식 코어(`SurfaceContactFrictionModifier`, `constantAccelerationDisplacement`)로 측정 기준 S3 쌍(μs 0.5/μk 0.4)과 재질 4종의 벡터를 만들어 `tests/incline_vectors.json`과 비교. 실험 JSON의 재질 계수가 TS `MATERIALS`와 같은지 |
| parity | `tests/run_tests.gd` | GDScript `PhysicsLaws`가 벡터와 같은 값(최대 차이 0) |
| 빗면 공식 일치 | `tests/run_tests.gd` | 앱의 빗면 실험(Jolt + 공식 보정)이 측정 기준 4절 표(26° 정지, 27° 1초 안에 미끄러짐, 35° 가속도·이동 거리 ±1%, 20° 10초 ≤ 1 mm)를 재현. 재질별로 임계각 −0.5° 정지, +0.5° 미끄러짐, 40°에서 s(1s)·s(1.5s) ±1%, 그래프 점이 공식과 일치 |
| 아트는 보이는 것만 | `tests/run_tests.gd` | 아트가 충돌 객체를 더하지 않음, 연출은 상자 메시만 바꾸고 충돌 모양은 그대로, 연출을 끈 실행과 운동·그래프·표시 값이 같음, 카메라 착지 반응이 모드·목표를 바꾸지 않음 |
| 셸 | `tests/run_tests.gd` | 레지스트리 검증(`tip`·`tip_short`를 실험 파일에 직접 쓰면 거부), 글꼴 서브셋이 쓰는 글자를 모두 포함, 카메라 모드 전환·제한·정면 초기화·시점별 target·따라가기, 제스처 분류(한 손가락은 카메라 불변), 가로 레이아웃(폰 1560×720·태블릿 1152×720 단위: 3D 전체·사이드바 닫힘, `정면으로`·3D 위 시점 칩 없음, 제목·버튼·카드·액션이 뷰 안에서 안 겹침, 사이드바 슬라이드·뷰 한 번 축소·닫으면 복귀, 좁은 뷰 가로 시야 유지), `key_observations` 검증, 실험 11개 모두 정면 기본·카드 값 = 패널 값·열린 사이드바 폭 유지, 조작 안내를 다 보기 전 재구성하면 다시 뜸, `← 목록`의 사이드바 우선 닫기, 좁은 창(300~700 단위)에서 제목·버튼 안 겹침 |
| 조작 | `tests/manipulation_checks.gd`(`run_tests.gd`가 부름) | 투영(바로 아래, 물체 중심 높이, 스치는 광선·뒤쪽 광선은 무시, 선 위 가장 가까운 점), 격자 스냅·영역·여유 0.6 m, 레지스트리의 `manipulation` 검사와 숨은 개발 장면, 보조 시점(필요할 때만 돌고 되돌아옴, 따라가기 대상 고정, 기본 정면 시점에서 11개 실험의 모든 물체·높이 손잡이를 잡아도 카메라 불변, 시선과 나란한 선만 카메라를 돌림). 실제 입력 경로(View3D 터치 → Manipulator → 실험)로: 빗면 끌어 놓기·0.5 m 눈금 스냅·놓을 수 없는 곳(남색 표시·흔들림·제자리 복귀)·두 번째 손가락과 시스템 취소·마우스·미끄러지는 상자 집기·조작 중 조건 변경·화면 재구성 유지. 개발 장면: 바닥 격자, 높이 손잡이(높이만, 0.25 m 단위), 높이 조작 중 두 손가락 취소, 다른 상자·블록과 겹침 금지, 블록 위 높이에 놓기, 영역 밖 금지, 빈 곳 탭으로 선택 해제, 떨어뜨리기. 리뷰 반영: 착지한 상자를 끌어 놓은 뒤 다시 착지 반응, 자동 놓기 타이머의 조작 취소, 높이 상한 초과 금지, 액션 때 손잡이 숨김, 떨어지는 상자 미저장, 손잡이 막대 기준 높이 끌기, 조작 중 사용자가 돌린 시점 유지, 보조 시점 탐색 횟수. 3차 리뷰 반영: 블록 위 상자 집기 높이 유지, 첫 목표가 막힌 곳이면 흔들지 않음, 눈금=스냅 격자·규칙 한 곳에서 읽기, 캡슐 축소, 놓기·취소 때 패널 갱신 1회, 데모 후속 액션 선언 |
| 공식 벡터 생성·감시 (Task 3) | `tools/formula-vectors.test.ts`(루트 `npm test`) | TS 코어 함수·클래스(`src/physics/laws`, `world.ts` 충돌, `PendulumModel`, `Lever`·`Pulley`·`OrbitChallenge`)로 10개 실험의 법칙 사례 587개와 대표 장면 목표값을 만들어 `tests/formula_vectors.json`과 비교. 10개 실험이 모두 법칙을 갖는지 |
| 공식 parity (Task 3) | `tests/formula_checks.gd`(`run_tests.gd`가 부름) | 실험마다 그 실험이 쓰는 `PhysicsLaws` 함수가 벡터와 상대 오차 1e-9 이내(측정 최대 3e-13), 벡터의 법칙에 포트가 모두 있음 |
| 보정 방식별 대표 장면 (Task 3) | `tests/formula_checks.gd` | 실제 Jolt 바디로: 자유 낙하·던지기 위치 = ½at²(≤ 1e-4 m, 질량 무관), 밀기 정지·s(t), 던지기·테이블 가장자리 출발 접촉은 착지 아님, 표시 공식은 엔진 장(달 중력·기울어진 장), 접촉 모니터가 꺼져 있어도 착지, 탄성·고무 충돌 뒤 속도(재질 반발 0·0.88, 느린 접근, 깊은 겹침, 중력 하 공중 충돌)·운동량, 충돌 보정이 재질·바닥 반발을 바꾸지 않음, 벽에 튕기는 옆 공·`apply_central_force` 접근·눌린 쌍·세 공 동시 접촉은 충돌 아님, 접촉 중 `apply_*` 힘 유지, 용수철 주기 ±0.1%·에너지 ±0.5%·감쇠 시 현재 상태 에너지·출발 속도 포함 전체 에너지, 원 궤도 주기·반지름 ±0.1%, 부력 평형 깊이 ±0.5%·가라앉음·중성 판정, 진자 각도 = TS 모델(≤ 1e-5 rad, 기본 감쇠 포함)·길이·주기·다른 바디 밀기, 도르래 높이·힘, 지렛대 들림. 기준은 [공식 보정 4절](docs/formula-correction.md#4-실험별-보정-방식) |
| 콘텐츠 공유 (Task 4a) | `src/app/mechanics-labs.test.ts`(루트 `npm test`), `tests/run_tests.gd` | 웹이 읽은 10개 실험·조작 팁의 SHA-256이 옮기기 전 TS 리터럴과 같음, 잘못된 공유 항목(없는 실험·분류, 단계 2개, 모르는 조건) 거부. 앱: 목록의 실험은 문구를 모두 공유 파일에서 가져오고 실험 파일에 쓰지 않음, 빗면 문구 불변, `content`와 문구를 같이 쓰거나 없는 id면 거부, 글꼴(대체 글꼴 포함)이 모든 글자를 덮음 |
| 균일장 실험 (Task 4a) | `tools/uniform-labs-vectors.test.ts` → `tests/uniform_labs_vectors.json`, `tests/uniform_lab_checks.gd`(`run_tests.gd`가 부름), 착지 시간·최고점 parity는 `formula_vectors.json` | 자유 낙하 6가지(달·지구·목성 × 높이): 고정 스텝의 표시 t·세 공 높이·v·p·K·U = TS(1e-9), 공 위치 = h₀ − gt²/2(1e-4 m), 0.5·1·3 kg가 같이 떨어짐(1e-6 m), 엔진 착지 = TS 착지 시간 ±2스텝, 착지 뒤 표시 = 공식 착지 값, 빨간 공 무게를 바꿔도 같은 운동, 무중력이면 그대로 떠 있음(바닥의 공도 시간은 시계), 그래프 점이 공식 선 위. 던지기 6가지(45°·30°·60°·15°·90°·0°, 높이 0–3 m): 표시 R·T·H와 x·y·속도 = TS(1e-9), 위치 = TS(1e-4 m), 착지 ±2스텝, 착지 거리 ±2스텝 이동, 최고점 ±2 mm, 착지 뒤 표시, 무중력 섬 밖 정지, 다음 던지기 같은 비행. 아트는 보이는 것만(충돌 객체, 연출 끈 실행과 같음), 3D 노드 16개 이하, 경로 점 = 공식. 실제 입력 경로: 공 끌기(선·0.5 m)·높이 손잡이·떨어진 공 집기, 화살표 손잡이(15°·0.5 m/s 스냅, 끄는 동안 미리보기, 슬라이더 동기화, 0–90° 밖은 막힘), 발사 선·높이. 착지 규칙(PR #9 리뷰): 처음 연 실험의 첫 바닥 던지기(45°)·바닥 위 공은 첫 스텝 착지 아님, 옆에 붙은 공끼리 닿지 않고 바닥에만 착지, 장 안 바닥 공·수평 바닥 던지기는 즉시 착지(시간 0, 그래프 리비전 멈춤), 낙하선 위 배치 막힘·옆 격자 허용, 1 mm 밖 발사 높이 스냅이 엔진·그래프·공식에 같음(`formula_checks.gd`: 얼어 있던 바닥 공 던지기, 지면 밖 바디 접촉은 착지 아님). 2차 리뷰: 바닥에서 15°·1 m/s 던지기(약 3스텝, 엔진 보고 없음)가 공식 시각에 한 번 착지·측정 거리·착지 뒤 그래프 점 없음, 5 mm 낙하의 측정 시각·그래프 점, 120 Hz에서 1 mm 낙하가 놓은 직후 깜빡이지 않음(`release()` 직후 스텝 길이 1/120), `landing_time` 정의역 밖 경계(위쪽 장·장 없음·출발보다 높은 착지면) parity. 돌연변이 9종(도약 출발 끔, 착지 시간 기준점, `gravity_scale` 미적용·이중 적용, 거리 식, 화살표 스냅 10°, 착지 표시, 집을 때 리셋, 미리보기) 실패 확인 |
| 충돌 실험 (Task 4c) | `tools/collision-lab-vectors.test.ts` → `tests/collision_lab_vectors.json`, `tests/collision_lab_checks.gd`(`run_tests.gd`가 부름) | 웹 `PhysicsSimulation`(world.ts 충돌)에 충돌 프리셋 감쇠·정지·벽 규칙(웹 소스의 상수를 읽어 확인)을 60 Hz로 적용한 7가지(웹 시작, 같은 질량 e = 1·고무, 점토·금속, 나무, 1 m/s 미만, 따라잡기): 모델 위치·속도·운동량(6스텝마다)·첫 충돌 값·충돌 횟수 = TS(1e-9, 측정 7e-15). 엔진 공 중심 = TS(≤ 1e-4 m, 측정 2.4e-7), 매 스텝 엔진 = 모델(위치 3.8e-7 m, 스텝 속도 2.8e-5 m/s), 패널 = TS, 운동량 보존·에너지 비증가, 같은 질량 e = 1 속도 교환, 재질별 e·1 m/s 미만 e = 0. 조건 변경, 아트는 보이는 것만(공은 엔진에서 아무것도 안 닿음, 바디는 돌지 않음), 3D 노드 16개 이하(14), 처음 연 화면의 첫 충돌(TS 94스텝), 부호 있는 운동량 그래프, 리뷰 반영(부호 그래프 눈금 +max/0/−max, 벽에 붙은 B의 미세 재접촉은 연출 반복 없음, 10초 넘는 29초 실행에서 엔진 위치·스텝 속도·운동량 = 공식, 느린 공 화살표 최소 길이, 화면 열기·상태 복원 때 재시작 1회, 최대 bump에서 공 바닥이 레일 아래로 안 내려감, 화살표 캐시 윗면 색, 손잡이 공용 생성), 실제 입력 경로(공 끌기 0.5 m, 손잡이 0.5 m/s·미리보기·슬라이더 동기화, 그 뒤 충돌 = 공식, 구르는 중 집으면 멈춤), 측정 데모. 돌연변이 7종(감쇠 끔, 밀어내기 끔, 충돌 결과 0.1% 변경, 벽 반발 무시, 구동 한 스텝 늦음, 손잡이 눈금 0.25 m/s, 엔진 접촉 켬) 실패 확인 |
| 용수철·부력·궤도 실험 (Task 4d) | `tools/{spring,buoyancy,orbit}-lab-vectors.test.ts` → `tests/*_lab_vectors.json`, `tests/{spring,buoyancy,orbit}_lab_checks.gd`(`run_tests.gd`가 부름) | TS 코어(`AnchoredSpringLaw`, `BuoyancyRegionLaw`, `PointGravityField`, `OrbitChallenge`)로 만든 사례(용수철 6·부력 7·궤도 8)와 모델·엔진 바디·패널을 스텝 단위로 대조(모델 ≤ 4e-15 상대, 엔진 ≤ 5e-7 m, 스텝 속도 ≤ 5.2e-5 m/s, 60초 실행 포함), 용수철 주기 2π√(m/k)·에너지 보존, 부력 ρ/ρ물 깊이·바닥·중성, 궤도 케플러 주기·에너지·탈출 속력·충돌 위치, 조작·끌기 뒤 출발 |
| 진자·지렛대·도르래 실험 (Task 4e) | `tools/{constraints,rotation,pulley}-lab-vectors.test.ts` → `tests/*_lab_vectors.json`, `tests/{constraints,rotation,pulley}_lab_checks.gd`(`run_tests.gd`가 부름) | TS 코어(`PendulumModel`, `LeverChallenge`, `PulleyAdvantageChallenge`, `torque`, `centripetalForce`, `work`)로 만든 사례(진자 7·지렛대 6 × 누름 51·도르래 5)와 모델·엔진 바디·패널을 스텝 단위로 대조(모델 ≤ 7e-14 상대, 엔진 ≤ 2.4e-7 m·막대 1.1e-7 rad, 진자 스텝 속도 2.9e-5 m/s, 60초 실행 포함). 엔진 바디에서: 진자 길이 일정·소진폭 주기 2π√(L/g)·대진폭 주기·에너지 보존과 e^(−bt) 감쇠, 지렛대가 기우는 첫 누름 = F₁r₁ ≥ F₂r₂, 도르래 줄 길이 일정·당김 = n × 상승·F·d = mgh. 처음 연 화면의 첫 동작, 실제 입력 경로(원 위 끌기, 손잡이 누르기·당기기, 짐·받침점 끌기와 막힘, 손 바꿔 당기기·취소), 측정 데모. 돌연변이 17종 실패 확인 |
| 빵고양이 (Task 4g) | `tests/bread_cat_checks.gd`(`run_tests.gd`가 부름) | 던지기 9가지(지구·달·목성·무중력, 0–90°, 높이 0–3 m)를 `공 놓기`로: 놓기 전 공 메시 = 손이 든 점(≤ 1e-4 m, 실측 0), 공 바디는 발사점에 그대로, 발사 프레임에 손 = 공 = 발사점(≤ 1e-4 m, 실측 2.4e-7 m), 그 전 물리 스텝 0, 29프레임(0.48초) 뒤. 높이 0·0.5·1·2·3 m에서 손 = 발사점·빵 상자 윗면 = 고양이 바닥·발사 기둥 없음. 높이 0.5–3 m × 0·15·45·75°에서 놓는 손이 어깨 위, 휘두르는 속력 증가, 놓기 직전 1/60초 손 방향 = 발사 방향(≤ 10°, 실측 0°), 감기는 반대쪽 뒤로. 발사 뒤 엔진 위치·패널 = 직접 `release()`(3초 매 스텝). 던지는 중 `처음으로`·집기는 늦은 발사 없음. 밀기: 미는·당기는·미끄러지는·멈춘 상자 면에 두 앞발(≤ 1e-4 m, 실측 4.8e-7 m), 상자 반응을 끄면 바디 면, 미는 쪽으로 기울기, 고양이 유무로 상자 운동·패널 같음(720스텝). 고양이 충돌 객체·모양·Area 0, 그리는 노드 ≤ 7, 정점 ≤ 3,500, 손 노드가 팔 선 위. 정면 시점(폰·태블릿·사이드바 연 태블릿)에서 고양이가 화면 안, 제목·카드·버튼·액션과 겹치지 않고 공·경로 점·상자·손잡이 시선을 가리지 않음. 돌연변이 6종 실패 확인(손 2 mm, 발사 3프레임 늦음, 발사 때 팔 2 % 늘어남, 앞발 3 mm, 고양이 아래 바디, 휘두르기 마지막 직선 29° 틀어짐). 털실·택배 박스: `ball_spin_checks.gd`가 공(자유 낙하·던지기·충돌·용수철) 털실 메시·크기·색, 조작 개발 씬 상자 테이프 색 확인(공 색 1 % 틀린 돌연변이 실패 확인) |
| 공 회전·튕김·구름 (Task 4f) | `tests/ball_spin_checks.gd`(`run_tests.gd`가 부름), `rolling_speed` parity는 `formula_vectors.json` | 시험 안의 독립 오라클(튕김 사슬·쿨롱 충격·미끄러짐·구름 저항·정지 닫힌 식)과 엔진 공을 매 스텝 대조: 던지기 8가지 위치 2.1e-5 m·회전각 3.3e-6 rad·바닥 아래 0, 충돌 시각·속도·정지 시각 1e-9, 자유 낙하 3가지(최고점 e²h, 튕김 시각) 6.5e-6 m, 착지 스텝 = ⌈T/dt⌉·착지 반응 1회. 비행 중 ω 0(주어진 ω₀ 일정), 메시 = 바디(털실 공), 자유 낙하 무회전·무이동, 충돌 메시 회전 = 이동/r, 울타리: 굴러온 공의 충돌 시각·속도·되튐·뜀 = 닫힌 식, 기본·가장 먼 던지기가 섬 위 정지, 날아가다 맞는 공(맞는 시각·속도 = 닫힌 식, 그때까지 비행 = 공식, 패널, 달 스캔 통과 0·판자 침투 0), 꼭대기 모서리(원-점, 닫힌 식·전수 탐색 1e-9), 바닥 위 역회전 공의 면·바닥 동시 충격 = 닫힌 식, μ 0 미끄러짐, 무중력 울타리(0°·2°·15°), 미리보기 점·고리, 던지기 선 위 그림 꼭대기 = 1.8 m·기둥 없음, 울타리 없을 때 정지 자리 보고, 공·라벨·그래프 색 일치, 받침판 흰색·회색. 돌연변이 25종 실패 확인, 울타리 꼭짓점이 섬 윗면 안 |
| 새 출발 위치의 표시 수치 | `tools/incline-vectors.test.ts` → `tests/incline_vectors.json` `runs`, `manipulation_checks.gd` | 재질·각도·출발 위치 4가지(1–6 m)에서 s(t) ±1%, 표시 `이동 거리`가 출발점에서 빗면 끝까지 거리에서 멈춤, 공식 곡선이 그 거리에서 끝남, 상자가 빗면을 떠나는 시각이 TS 공식 √(2L/a)와 3 step 안 |

- TS 공식을 바꾸면 vitest가 먼저 깨진다. `UPDATE_INCLINE_VECTORS=1 UPDATE_FORMULA_VECTORS=1 UPDATE_UNIFORM_VECTORS=1 UPDATE_FRICTION_VECTORS=1 UPDATE_COLLISION_VECTORS=1 UPDATE_SPRING_VECTORS=1 UPDATE_BUOYANCY_VECTORS=1 UPDATE_ORBIT_VECTORS=1 UPDATE_CONSTRAINTS_VECTORS=1 UPDATE_ROTATION_VECTORS=1 UPDATE_PULLEY_VECTORS=1 npx vitest run apps/lab3d`로 벡터를 다시 만든 뒤 Godot 테스트로 GDScript 쪽 불일치를 확인한다.
- UI 문구를 바꾸면 `apps/lab3d/tools/subset_font.sh`로 글꼴을 다시 만든다(fonttools가 없으면 `uvx`로 실행). 빠진 글자는 테스트가 잡는다. Noto Sans CJK에 없는 아래·위 첨자(ₛ, ₖ, ⁻¹)는 쓰지 않는다.
- `build.sh test`(앱·스파이크 둘 다)는 `SCRIPT ERROR`(스크립트 컴파일·실행 오류)나 `ERROR`로 시작하는 줄이 로그에 있으면 PASS여도 실패로 본다. 코루틴 안 오류로 멈춘 실행은 `GODOT_TEST_TIMEOUT`(기본 900초) 뒤 실패한다. Godot 경로는 `GODOT`로 바꾼다(기본 `~/.local/share/godot-spike/godot`).
- `-s`로 실행하는 테스트에서는 autoload 이름이 컴파일 시점에 없어서, `Quality`·`Bench`를 쓰는 스크립트는 테스트에서 `load()`로 불러 쓴다.

### 테스트와 CI

`.github/workflows/ci.yml`이 모든 PR과 dev·main push에서 돌고, 수동 실행(workflow_dispatch)도 된다(Pages 배포 `pages.yml`은 따로). checkout은 토큰을 남기지 않는다(`persist-credentials: false`). Jolt 조사용 `spikes/jolt-probes/`는 CI에 넣지 않았고 `run.sh`로 수동 실행한다.

| 잡 | 단계 |
|---|---|
| `node` | `npm ci` → `npm test`(웹·공식 코어·3D 벡터) → `npm run test:spikes` → `npm run build` |
| `godot` | 공식 릴리스 `Godot_v4.7.2-stable_linux.x86_64.zip`을 `.github/scripts/install-godot.sh`로 내려받아 SHA-512(릴리스 `SHA512-SUMS.txt` 값, 스크립트에 고정)를 검증·압축 해제 → `apps/lab3d/tools/build.sh test` → `spikes/godot/tools/build.sh test`. zip만 `actions/cache`에 두고 매번 다시 검증한다. 실패하면 두 `exports/test.log`를 아티팩트로 올린다 |

로컬에서 같은 단계를 재현한다(작업 트리를 건드리지 않게 깨끗한 사본에서):

```bash
mkdir -p /tmp/ci-ws && git archive HEAD | tar -x -C /tmp/ci-ws && cd /tmp/ci-ws
npm ci && npm test && npm run test:spikes && npm run build
export GODOT=$(.github/scripts/install-godot.sh "$PWD/.godot-bin")
apps/lab3d/tools/build.sh test && spikes/godot/tools/build.sh test
```

## 4. 실기기 측정과 확인

```bash
apps/lab3d/tools/bench_device.sh low 3 90 60        # 90초 × 3회(회차 사이 60초) + 10분 지속 → spikes/bench/results/lab3d-incline-friction-drag
OPBENCH_RESULTS_DIR=$PWD/spikes/bench/results/phase1-task2c apps/lab3d/tools/bench_device.sh low  # 결과 폴더 지정
node spikes/bench/summarize.mjs spikes/bench/results/phase1-task2c
OPBENCH_PACKAGE=org.openphysics.lab3d OPBENCH_VARIANT_DIR=<dir> \
  spikes/bench/godot-variant.sh <이름> 20 40 --experiment=incline-friction --quality=low --q-ui_mode=root
python3 -I apps/lab3d/tools/device_gesture.py orbit  # orbit | pinch | pinch-fixed | pan | one-finger | drag-cancel
```

- 다른 실험: `OPBENCH_EXPERIMENT=free-fall OPBENCH_SUSTAINED=0 apps/lab3d/tools/bench_device.sh low 3 90 60`(던지기는 `projectile`, 마찰 밀기는 `friction`, 충돌은 `collision`, 용수철·부력·궤도는 `spring`·`buoyancy`·`orbit`, 진자·지렛대·도르래는 `constraints`·`rotation`·`pulley`). 장면 이름은 실험 정의의 `bench_id`(`FF`·`PJ`·`FR`·`CO`·`S3`, 앱이 기록하는 이름)에서 읽고, 빗면 전용 `--ctl-angle=30`은 `incline-friction`일 때만 기본으로 붙는다(`OPBENCH_CTL`로 바꿈). 기본 결과 폴더는 실험·조작 방식별 `spikes/bench/results/lab3d-<실험>-<drag|release>`이고, 이미 같은 등급·장면 결과가 있는 폴더(기록된 기준선 `phase1-task*` 포함)에는 쓰지 않는다(`OPBENCH_OVERWRITE=1`일 때만 덮어씀). `--auto-drag=4`가 실험의 첫 조작 물체(자유 낙하 빨간 공, 던지기 공, 마찰 밀기 손잡이, 충돌 공 A)를 4초마다 끌어 놓고 0.4초 뒤 `demo_action`(공 놓기, 마찰 밀기는 `처음으로`)을 누른다. 마찰 밀기는 손잡이를 끝(+4 m, 80 N: 상자가 미끄러짐)과 40% 지점(−0.8 m, −16 N: 버팀)으로 번갈아 끈다. 충돌은 공 A를 자기 구간 끝(x −0.5 m)과 40% 지점(−4 m)으로 번갈아 옮기고 `출발`을 눌러 4초마다 충돌·벽 튐을 되풀이한다. 진자는 줄 추를 원 위 두 각도로 옮겨 놓고(두 추가 출발), 지렛대는 손잡이를 끝까지(250 N, 들림)와 40 %(100 N)로 번갈아 누르고, 도르래는 손잡이를 끝까지와 40 %로 당긴 뒤 `처음으로`를 누른다. Task 4a 결과는 [phase1-task4a](../../spikes/bench/results/phase1-task4a/README.md).
- `bench_device.sh`는 가로 기본 화면(사이드바 닫힘)에서 잰다. `OPBENCH_SIDEBAR=open`이면 사이드바를 열어 관찰값·그래프 위치로 스크롤하고(`--scroll-to=observations`, 기본 결과 폴더에 `-sidebar`), Task 2d 이전(세로, 패널 스크롤)과 비교할 때 쓴다. 각도 30°에서 4초마다 상자를 손가락 입력 경로로 끌어 새 출발 위치에 놓고 0.4초 뒤 놓기를 눌러(`--auto-drag=4`) 끌기·보조 시점·물리·관찰값·그래프가 계속 바뀌는 상태로 잰다. Task 2a·2c는 `OPBENCH_PLAY=--auto-release=4`(4초마다 다시 놓기만)로 쟀다. 빗면의 OPBENCH 장면 이름은 `S3`(측정 기준의 안내형 빗면)다.
- 한 손가락 끌기는 `adb shell input swipe x1 y1 x2 y2 <ms>`로 재생한다. `device_gesture.py drag-cancel`은 빗면 상자(20°, 기본 정면 시점)를 끄는 중 두 번째 손가락을 대 취소를 재생한다.
- `device_gesture.py`는 Android `hid` 명령으로 2점 가상 멀티터치 화면을 등록해 두 손가락 제스처를 재생한다. `adb shell input`은 한 손가락만 되고, 실제 터치스크린 노드 쓰기는 SELinux가 막는다. 좌표는 가로 기준 SM-P200 화면 픽셀(1920×1200)이고, 가상 화면은 자연 방향(세로) 좌표로 보고하므로 `dumpsys input`의 현재 회전으로 바꿔 보낸다. `tap --at X,Y`는 그 점을 한 번 누른다.
- 결과: [Phase 1 Task 2a 측정 결과](../../spikes/bench/results/phase1-task2a/README.md), [Task 2c(잔디 섬 스타일)](../../spikes/bench/results/phase1-task2c/README.md), [Task 2b(조작)](../../spikes/bench/results/phase1-task2b/README.md).

## 5. 실험 추가

1. `content/experiments/<id>.json`을 만든다. 필드는 `incline-friction.json`을 따른다. 문구는 `content`에 공유 실험 id를 적어 `content/mechanics-labs.json`에서 가져온다(웹 2D 실험이면 `labs`의 그 항목에 3D 조작 안내 `app.tip`을 더하고, 3D 전용이면 `app_labs`에 더한다, 1절 "콘텐츠 공유"). 합친 정의에서 `ExperimentRegistry.validate()`가 검사하는 필수 필드는 `id`, `title`, `category`, `question`, `steps`, `observe`, `law`, `scene`, `camera`, `controls`, `actions`, `observations`, `key_observations`, `graph`다. 나머지(`icon`, `terms`, `tip`)는 선택이다.
   - 문구(공유 파일): `title`, `category`, `icon`, `question`, `steps`(3개), `observe`, `terms`, `law`(`title`·`description`·`equation`), `app.tip`
   - `scene`: 실험 스크립트 경로, `bench_id`: OPBENCH 장면 이름
   - `camera`: `target`, `distance`, `distance_range`, `yaw_range_deg`, `pitch_range_deg`, `pan_radius`, `default_mode`(안내형 실험은 `front`), `views`(front·three_quarter·top·side·follow의 `yaw_deg`·`pitch_deg`, 선택 `distance`·`target`). 정면 시점에서 장치가 핵심 카드(왼쪽 위)·액션 버튼(오른쪽 아래)에 가리지 않는지 폰 가로(2340×1080)·태블릿 가로(1920×1200)에서 확인한다
   - `controls`: `slider`(`min`·`max`·`step`·`default`·`unit`·`digits`) 또는 `choice`(`options`·`default`). `options` 항목은 `id`·`label`이고, 재질 선택처럼 실험이 쓰는 계수(`mu_s`·`mu_k`)를 함께 둘 수 있다
   - `actions`: 버튼(`id`·`label`, `style: "primary"`)
   - `observations`: `id`·`label`·`unit`·`digits`(문자열 값이면 단위 없음)
   - `key_observations`: 3D 위 카드로 늘 보일 관찰값 id 2~3개(실험 질문에 답하는 값). 레지스트리가 개수·중복·id를 검사한다
   - `graph`: `title`, `x`(`label`·`unit`·`max`), `y`(`label`·`unit`·`min_max`), `series`(`id`·`label`·`color`·`style: line|points`)
2. `content/experiments/index.json`의 `experiments`에 파일 이름을 더한다. 목록 화면은 이 순서와 `category`로 묶어 보여준다.
3. `experiments/<이름>/<이름>.gd`에 `extends Experiment` 스크립트를 만든다(공식 모델을 `BodyModelDriver`로 구동하는 안내형 실험은 `extends ModelDrivenLab`: `_ready()`·run 상태·그래프 장부·`release()`를 베이스가 맡고 `_build_world()`·`_load_model()`·`_graph_point()` 등을 채운다. 조건이 바뀌어 run을 다시 시작할 때는 `_restart()`와 `reset_run()`). `_ready()`에서 3D 월드를 만들고 `definition.controls`의 기본값으로 `set_control()`을 부른다. 보이는 소품·환경·연출은 `<이름>_props.gd`로 나눠 [아트 디렉션 9절](docs/art-direction.md#9-새-실험-소품-만드는-법)을 따른다. 바닥·마찰 없는 재질·보정 바디 설정과 상태 변화 알림은 `Experiment` 베이스의 `_add_floor()`·`_frictionless_material()`·`_setup_free_body()`·`_update_status()`(반응은 `_status_changed()`를 재정의)를 쓰고, 공식의 중력은 베이스의 `engine_g`에서 읽는다. 화면 숫자는 공식(`PhysicsLaws`)에서 내고, 엔진 측정값은 따로 표시한다(공식 보정 원칙, [CONTEXT](../../CONTEXT.md)).
4. 움직임은 [공식 보정](docs/formula-correction.md) 4절 표의 방식으로 보정한다(보정기를 붙이고 화면 숫자는 `formula_values()`에서). 새 법칙은 `tools/formula-vectors.test.ts`의 실험 그룹에 TS 사례를 더하고 `PhysicsLaws`에 포트한다(parity는 자동). 문구를 바꿨으면 글꼴 서브셋을 다시 만든다.
5. `tools/build.sh`로 테스트·APK를 만들고 `bench_device.sh`로 low 60 fps를 확인한다.

`ExperimentRegistry.validate()`가 필수 필드·카메라 모드·조건 형식·`manipulation` 규칙을 검사하고, 잘못된 실험은 목록에서 빼고 오류를 남긴다.

물체를 손으로 옮기게 하려면 JSON에 `manipulation`을 더하고 스크립트에 `manipulation_body`·`manipulation_surface`(필요하면 `manipulation_juice`·`placement_allowed`·`placements`)와 결과 통보를 구현한다(1절 "조작"). 목록에 내지 않을 장면은 `index.json`의 `hidden`에 둔다.

## 6. 한계

- 조작은 물체를 면에 똑바로 세워 놓는다(면 좌표계 방향). 물체 회전·줄·용수철 연결·도구 팔레트는 Task 5다. 조작 대상의 충돌 모양은 바디의 첫 `CollisionShape3D`(상자·구·원기둥·캡슐, 원점에 놓인 것)로 본다.
- 공식 보정 계층은 알려진 면 하나 위의 마찰, 알려진 두 구의 충돌, 실험이 정한 힘·모델만 다룬다. 빈 실험실(Task 5)의 일반 다접촉 마찰·조인트는 따로 설계한다([공식 보정 2절 한계](docs/formula-correction.md#한계)).
- Web export와 iOS는 아직 만들지 않았다.
- 사이드바에서는 시점·조건 카드까지만 한 화면에 보이고 관찰값·그래프는 스크롤해야 한다. 핵심 카드에 없는 값은 사이드바를 열어야 보인다.
- 균일장 실험(Task 4a): 그래프 가로축이 3초로 고정이라 달에서 길게 나는 운동(던지기 T 최대 약 11초)은 앞부분만 그려진다. 공식 값(거리·시간·최고점)은 패널에 그대로 나온다. 실험 정의의 웹 2D 조건 중 웹 캔버스 크기에 따라 달라지는 출발 높이(웹 약 7.8 m)는 3D에서 0.5–8 m 조건으로 바꿨고, 던지기 출발 높이(웹 0.42 m)는 기본 0.5 m(손잡이 0.25 m 눈금)다.
- 공은 회전을 잠갔다(착지 뒤 굴러가지 않고 미끄러진다). 자유 비행에는 회전이 없어 공식 운동과 무관하다.
