# Open Physics 3D (apps/lab3d)

역학 3D 실험 앱이다. Godot 4.7.2 + Jolt, GDScript. Phase 1 Task 2a에서 셸 뼈대(실험 등록, 카메라·제스처, 2D 패널, 품질 설정)와 첫 실험(빗면 마찰)을 만들었고, Task 2c에서 시각 스타일(잔디 섬: 선명한 원색, 각진 로우폴리, 하늘에 뜬 잔디 섬)과 연출을 정했다. Task 2b에서 한 손가락으로 물체를 집어 정해진 면 위로 옮기는 조작(조작 평면·스냅·높이 손잡이·보조 시점)을 더했다. Task 3에서 역학 안내형 10개 실험이 쓸 공식 보정 계층(`scripts/formula/`)과 TS↔GDScript parity, CI를 만들었다([공식 보정](docs/formula-correction.md)). 기준은 [아트 디렉션](docs/art-direction.md)이다. 계획과 진행은 [Phase 1 문서](../../docs/3d-phase1/README.md), 스택 결정은 [ADR 0001](../../docs/adr/0001-3d-app-stack.md)에 있다.

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
  scripts/art/                        셸 공용 아트: ArtPalette, ArtMeshBuilder(로우폴리 메시), art_lit 셰이더(구운 조명),
                                      ArtKit(재질·환경·떠 있는 섬), ArtJuice(연출·블롭 그림자)
  scripts/shell/                      Experiment(실험 기반 클래스), ExperimentRegistry, ExperimentScreen,
                                      View3D(3D 뷰·제스처), CameraRig(카메라 6모드·보조 시점), GraphView,
                                      Manipulator(물체 조작), ManipSurface(조작 평면)
  experiments/incline_friction/       빗면 마찰 실험(장면, InclineFrictionCorrector = 접촉 힘 보정 설정, InclineProps 소품)
  experiments/manipulation_dev/       조작 확인용 개발 장면(목록에 없음, --experiment=manipulation-dev)
  content/experiments/                실험 콘텐츠 JSON(index.json + 실험별 파일)
  assets/fonts/                       Noto Sans CJK KR 서브셋(Regular·Bold, SIL OFL 1.1)
  tests/                              헤드리스 테스트, TS 생성 parity 벡터
  tools/                              빌드·글꼴·벡터 생성·실기기 측정·제스처 도구
  docs/ui-resolution.md               low 단계 UI 해상도 방식 결정과 측정 근거
  docs/art-direction.md               스타일 가이드(팔레트, 형태, 조명, 연출, 성능 예산, 새 실험 소품)
  docs/formula-correction.md          공식 보정: Jolt 조사, 보정 방식, 실험 10개 표, 테스트 파이프라인
```

화면 흐름은 실험 목록 → 실험 화면이고, 두 화면 모두 위쪽 `설정`에서 품질 설정 화면으로 간다. Android 뒤로 가기는 실험 → 목록 → 종료 순서다. 실험 화면에서 설정을 열어도 실험 화면은 해제되지 않고 보관돼, 돌아오면 각도·재질·놓기 상태·카메라가 그대로다. 같은 렌더러에서 품질(medium ↔ high)을 바꾸면 3D 뷰를 다시 만들며 이때는 조건 값과 카메라만 유지한다. 렌더러가 바뀌는 재시작은 앱이 다시 뜨므로 실험 화면 상태는 유지되지 않고 설정 화면으로 돌아온다. 실행 인자(`--ctl-*`, `--camera` 등)는 `--experiment`로 연 실험 화면에만 적용한다.

### 셸과 실험의 경계

셸(`ExperimentScreen`)이 카메라·제스처·2D 패널·품질을 맡고, 실험은 3D 월드와 물리만 맡는다.

| 셸이 하는 일 | 실험이 답하는 것(`Experiment`) |
|---|---|
| 패널에 질문·조건·관찰값·그래프·설명을 그린다 | `set_control(id, value)` · `control_value(id)` · `run_action(id)` |
| 관찰값·그래프를 10 Hz로 갱신한다 | `observations()` → `{id: 숫자 또는 문자열}`, `graph_series()` → `{시리즈 id: PackedVector2Array}` |
| 카메라 모드·제한·"정면으로"를 처리한다 | `follow_point()`(따라가기 대상), JSON의 `camera` |
| 3D를 품질 단계 해상도의 SubViewport에 그린다 | 장면은 `ArtKit`·`ArtMeshBuilder`로 꾸민다(엔진 조명·그림자 없음, [아트 디렉션](docs/art-direction.md)) |
| 착지 때 카메라를 살짝 흔든다(`CameraRig.nudge`) | `impact(strength)` 신호(연출용, 선택) |
| 한 손가락 조작: 집기·끌기·스냅·미리보기·높이 손잡이·취소·보조 시점(`Manipulator`) | JSON `manipulation`의 규칙, `manipulation_body`·`manipulation_surface`·`manipulation_juice`, 결과 통보(`manipulation_started`·`_placed`·`_cancelled`), 추가 규칙 `placement_allowed`, 화면 재구성 때 유지할 `placements()` |

콘텐츠(문구·조건·관찰값·그래프·시점)는 JSON 데이터다. Task 4에서 웹 2D와 같은 파일을 공유할 수 있게 코드와 분리했다.

### 공식 보정 계층 (Task 3)

안내형 실험의 핵심 운동과 화면 수치를 TS 공식 코어에 맞추는 공용 계층이다. 실험은 보정 방식 하나를 골라 보정기를 붙이고, 화면 숫자는 보정기의 `formula_values()`(또는 `PhysicsLaws`)에서만 가져온다. 엔진 측정값(`engine_values()`, `samples`)은 "(시뮬레이션)" 표시와 그래프 측정 점에만 쓴다. 보정은 고정 스텝마다 물리 서버 스텝 **전**(`_physics_process`)에 한다. 근거와 실험별 표는 [docs/formula-correction.md](docs/formula-correction.md).

| 방식 | 보정기 | 실험 |
|---|---|---|
| 접촉 힘 보정 | `ContactFrictionCorrector`(빗면은 `InclineFrictionCorrector`) | 마찰(밀기), 빗면 |
| 균일장 출발 보정 | `UniformFieldCorrector` | 자유 낙하, 던지기 |
| 충돌 결과 보정 | `CollisionCorrector` | 충돌 |
| 공식 힘 주입 | `SpringInjector`, `BuoyancyInjector`, `PointGravityInjector` | 용수철, 부력, 궤도 |
| 해석 모델 구동 | `PendulumModelDriver`, `LeverModelDriver`, `PulleyModelDriver` | 줄·막대(진자), 지렛대, 도르래 |

- 한 바디 보정기는 바디를 `FormulaBody`로 만들고 `body.corrector`에 넣는다. 여러 바디를 다루는 보정기(충돌, 모델 구동)는 `FormulaDriver`의 `correctors`에 넣고 `running`을 켠다.
- 실행 순서: 놓는 스텝에 같은 `_physics_process`에서 보정이 시작된다. 그래서 놓기·리셋은 실험의 `_physics_process`나 그 전에 한다(빗면 `release()`와 같다).

### 카메라와 제스처

| 모드 | 동작 |
|---|---|
| 정면 · 3/4 · 위 · 옆 | 실험 JSON `camera.views`의 시점으로 약 0.4초에 걸쳐 부드럽게 옮긴다. 이동·확대는 기본값으로 돌아간다 |
| 따라가기 | `follow_point()`(빗면에서는 상자)를 따라간다 |
| 제한 회전 | 사용자가 돌린 시점. `yaw_range_deg`·`pitch_range_deg`·`distance_range`·`pan_radius` 안에서만 움직인다 |

- `정면으로` 버튼은 3D 뷰 오른쪽 위에 항상 있다. 정면 모드 + 이동·확대 초기화다.
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

- 보조 시점: 끄는 동안 카메라가 조작 평면을 25° 이상 내려다보고, 선으로 움직이는 물체(빗면)·높이 손잡이는 그 선과 시선이 35° 이상 벌어지게 한다. 지금 시점이 이미 그러면 움직이지 않는다. 아니면 실험의 회전 제한 안에서 가장 가까운 방위·고도로 0.4초에 걸쳐 돌고, 놓거나 취소하면 원래 시점으로 돌아간다. 끄는 동안 따라가기 대상은 고정한다. 작은 보조 뷰(화면 속 화면) 대신 카메라 보정을 고른 근거는 [Task 2b 결과](../../spikes/bench/results/phase1-task2b/README.md) 2절.
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

- `window/stretch`는 `canvas_items` + `expand`, 기준 크기 720×720이다. 화면의 짧은 변이 항상 720 UI 단위라 세로·가로에서 글자 크기가 같다(SM-P200에서 1 단위 = 1.67 px).
- 세로(폰·태블릿 세로): 위쪽 3D 뷰(본문 높이의 46%), 아래 스크롤 패널. 가로(태블릿): 왼쪽 3D 뷰, 오른쪽 470 단위 패널.
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
$GODOT --path apps/lab3d                                   # 데스크톱(720×1280 창)
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
| `--orientation=<portrait\|landscape>` | 화면 방향 고정(스크린샷용, 기본은 센서) |
| `--camera=<front\|three_quarter\|top\|side\|follow\|orbit>` | 카메라 모드 |
| `--ctl-<조건 id>=<값>` | 조건 값(예: `--ctl-angle=30`, `--ctl-material=rubber`) |
| `--scroll-to=<conditions\|observations\|graph\|explanation>` | 패널 스크롤 위치 |
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
| 셸 | `tests/run_tests.gd` | 레지스트리 검증, 글꼴 서브셋이 쓰는 글자를 모두 포함, 카메라 모드 전환·제한·정면으로·따라가기, 제스처 분류(한 손가락은 카메라 불변), 세로·가로 레이아웃 |
| 조작 | `tests/manipulation_checks.gd`(`run_tests.gd`가 부름) | 투영(바로 아래, 물체 중심 높이, 스치는 광선·뒤쪽 광선은 무시, 선 위 가장 가까운 점), 격자 스냅·영역·여유 0.6 m, 레지스트리의 `manipulation` 검사와 숨은 개발 장면, 보조 시점(필요할 때만 돌고 되돌아옴, 따라가기 대상 고정). 실제 입력 경로(View3D 터치 → Manipulator → 실험)로: 빗면 끌어 놓기·0.5 m 눈금 스냅·놓을 수 없는 곳(남색 표시·흔들림·제자리 복귀)·두 번째 손가락과 시스템 취소·마우스·미끄러지는 상자 집기·조작 중 조건 변경·화면 재구성 유지. 개발 장면: 바닥 격자, 높이 손잡이(높이만, 0.25 m 단위), 높이 조작 중 두 손가락 취소, 다른 상자·블록과 겹침 금지, 블록 위 높이에 놓기, 영역 밖 금지, 빈 곳 탭으로 선택 해제, 떨어뜨리기. 리뷰 반영: 착지한 상자를 끌어 놓은 뒤 다시 착지 반응, 자동 놓기 타이머의 조작 취소, 높이 상한 초과 금지, 액션 때 손잡이 숨김, 떨어지는 상자 미저장, 손잡이 막대 기준 높이 끌기, 조작 중 사용자가 돌린 시점 유지, 보조 시점 탐색 횟수. 3차 리뷰 반영: 블록 위 상자 집기 높이 유지, 첫 목표가 막힌 곳이면 흔들지 않음, 눈금=스냅 격자·규칙 한 곳에서 읽기, 캡슐 축소, 놓기·취소 때 패널 갱신 1회, 데모 후속 액션 선언 |
| 공식 벡터 생성·감시 (Task 3) | `tools/formula-vectors.test.ts`(루트 `npm test`) | TS 코어 함수·클래스(`src/physics/laws`, `world.ts` 충돌, `PendulumModel`, `Lever`·`Pulley`·`OrbitChallenge`)로 10개 실험의 법칙 사례 519개와 대표 장면 목표값을 만들어 `tests/formula_vectors.json`과 비교. 10개 실험이 모두 법칙을 갖는지 |
| 공식 parity (Task 3) | `tests/formula_checks.gd`(`run_tests.gd`가 부름) | 실험마다 그 실험이 쓰는 `PhysicsLaws` 함수가 벡터와 상대 오차 1e-9 이내(측정 최대 3e-13), 벡터의 법칙에 포트가 모두 있음 |
| 보정 방식별 대표 장면 (Task 3) | `tests/formula_checks.gd` | 실제 Jolt 바디로: 자유 낙하·던지기 위치 = ½at²(≤ 1e-4 m, 질량 무관), 밀기 정지·s(t), 탄성·고무 충돌 뒤 속도(재질 안 맞춘 경우 포함)·운동량, 용수철 주기 ±0.1%·에너지 ±0.5%, 원 궤도 주기·반지름 ±0.1%, 부력 평형 깊이 ±0.5%·가라앉음, 진자 각도 = TS 모델(≤ 1e-5 rad)·길이·주기·다른 바디 밀기, 도르래 높이·힘, 지렛대 들림. 기준은 [공식 보정 4절](docs/formula-correction.md#4-실험별-보정-방식) |
| 새 출발 위치의 표시 수치 | `tools/incline-vectors.test.ts` → `tests/incline_vectors.json` `runs`, `manipulation_checks.gd` | 재질·각도·출발 위치 4가지(1–6 m)에서 s(t) ±1%, 표시 `이동 거리`가 출발점에서 빗면 끝까지 거리에서 멈춤, 공식 곡선이 그 거리에서 끝남, 상자가 빗면을 떠나는 시각이 TS 공식 √(2L/a)와 3 step 안 |

- TS 공식을 바꾸면 vitest가 먼저 깨진다. `UPDATE_INCLINE_VECTORS=1 UPDATE_FORMULA_VECTORS=1 npx vitest run apps/lab3d`로 벡터를 다시 만든 뒤 Godot 테스트로 GDScript 쪽 불일치를 확인한다.
- UI 문구를 바꾸면 `apps/lab3d/tools/subset_font.sh`로 글꼴을 다시 만든다(fonttools가 없으면 `uvx`로 실행). 빠진 글자는 테스트가 잡는다. Noto Sans CJK에 없는 아래·위 첨자(ₛ, ₖ, ⁻¹)는 쓰지 않는다.
- `build.sh test`는 `SCRIPT ERROR`(스크립트 컴파일·실행 오류)가 로그에 있으면 PASS여도 실패로 본다. 코루틴 안 오류로 멈춘 실행은 `GODOT_TEST_TIMEOUT`(기본 900초) 뒤 실패한다. Godot 경로는 `GODOT`로 바꾼다(기본 `~/.local/share/godot-spike/godot`).
- `-s`로 실행하는 테스트에서는 autoload 이름이 컴파일 시점에 없어서, `Quality`·`Bench`를 쓰는 스크립트는 테스트에서 `load()`로 불러 쓴다.

### 테스트와 CI

`.github/workflows/ci.yml`이 모든 PR과 dev·main push에서 돈다(Pages 배포 `pages.yml`은 따로).

| 잡 | 단계 |
|---|---|
| `node` | `npm ci` → `npm test`(웹·공식 코어·3D 벡터) → `npm run test:spikes` → `npm run build` |
| `godot` | 공식 릴리스 `Godot_v4.7.2-stable_linux.x86_64.zip`을 `.github/scripts/install-godot.sh`로 내려받아 SHA-512(릴리스 `SHA512-SUMS.txt` 값, 스크립트에 고정)를 검증·압축 해제 → `apps/lab3d/tools/build.sh test` → `spikes/godot/tools/build.sh test`. zip만 `actions/cache`에 두고 매번 다시 검증한다. 실패하면 두 `exports/test.log`를 아티팩트로 올린다 |

로컬에서 같은 단계를 재현한다(작업 트리를 건드리지 않게 깨끗한 사본에서):

```bash
git archive HEAD | tar -x -C /tmp/ci-ws && cd /tmp/ci-ws
npm ci && npm test && npm run test:spikes && npm run build
export GODOT=$(.github/scripts/install-godot.sh "$PWD/.godot-bin")
apps/lab3d/tools/build.sh test && spikes/godot/tools/build.sh test
```

## 4. 실기기 측정과 확인

```bash
apps/lab3d/tools/bench_device.sh low 3 90 60        # 90초 × 3회(회차 사이 60초) + 10분 지속
OPBENCH_RESULTS_DIR=$PWD/spikes/bench/results/phase1-task2c apps/lab3d/tools/bench_device.sh low  # 결과 폴더 지정
node spikes/bench/summarize.mjs spikes/bench/results/phase1-task2c
OPBENCH_PACKAGE=org.openphysics.lab3d OPBENCH_VARIANT_DIR=<dir> \
  spikes/bench/godot-variant.sh <이름> 20 40 --experiment=incline-friction --quality=low --q-ui_mode=root
python3 -I apps/lab3d/tools/device_gesture.py orbit  # orbit | pinch | pinch-fixed | pan | one-finger | drag-cancel
```

- `bench_device.sh`는 패널을 관찰값·그래프 위치로 스크롤하고(`--scroll-to=observations`), 각도 30°에서 4초마다 상자를 손가락 입력 경로로 끌어 새 출발 위치에 놓고 0.4초 뒤 놓기를 눌러(`--auto-drag=4`) 끌기·보조 시점·물리·관찰값·그래프가 계속 바뀌는 상태로 잰다. Task 2a·2c는 `OPBENCH_PLAY=--auto-release=4`(4초마다 다시 놓기만)로 쟀다. OPBENCH 장면 이름은 `S3`(측정 기준의 안내형 빗면)다.
- 한 손가락 끌기는 `adb shell input swipe x1 y1 x2 y2 <ms>`로 재생한다. `device_gesture.py drag-cancel`은 빗면 상자(20°, 기본 시점)를 끄는 중 두 번째 손가락을 대 취소를 재생한다.
- `device_gesture.py`는 Android `hid` 명령으로 2점 가상 멀티터치 화면을 등록해 두 손가락 제스처를 재생한다. `adb shell input`은 한 손가락만 되고, 실제 터치스크린 노드 쓰기는 SELinux가 막는다. 좌표는 세로 기준 SM-P200 화면 픽셀이다.
- 결과: [Phase 1 Task 2a 측정 결과](../../spikes/bench/results/phase1-task2a/README.md), [Task 2c(잔디 섬 스타일)](../../spikes/bench/results/phase1-task2c/README.md), [Task 2b(조작)](../../spikes/bench/results/phase1-task2b/README.md).

## 5. 실험 추가

1. `content/experiments/<id>.json`을 만든다. 필드는 `incline-friction.json`을 따른다. `ExperimentRegistry.validate()`가 검사하는 필수 필드는 `id`, `title`, `category`, `question`, `steps`, `observe`, `law`, `scene`, `camera`, `controls`, `actions`, `observations`, `graph`다. 나머지(`icon`, `terms`, `tip`)는 선택이다.
   - 문구: `title`, `category`, `icon`, `question`, `steps`(웹 2D처럼 3개 권장), `observe`, `terms`, `law`(`title`·`description`·`equation`), `tip`
   - `scene`: 실험 스크립트 경로, `bench_id`: OPBENCH 장면 이름
   - `camera`: `target`, `distance`, `distance_range`, `yaw_range_deg`, `pitch_range_deg`, `pan_radius`, `default_mode`, `views`(front·three_quarter·top·side·follow의 `yaw_deg`·`pitch_deg`, 선택 `distance`)
   - `controls`: `slider`(`min`·`max`·`step`·`default`·`unit`·`digits`) 또는 `choice`(`options`·`default`). `options` 항목은 `id`·`label`이고, 재질 선택처럼 실험이 쓰는 계수(`mu_s`·`mu_k`)를 함께 둘 수 있다
   - `actions`: 버튼(`id`·`label`, `style: "primary"`)
   - `observations`: `id`·`label`·`unit`·`digits`(문자열 값이면 단위 없음)
   - `graph`: `title`, `x`(`label`·`unit`·`max`), `y`(`label`·`unit`·`min_max`), `series`(`id`·`label`·`color`·`style: line|points`)
2. `content/experiments/index.json`의 `experiments`에 파일 이름을 더한다. 목록 화면은 이 순서와 `category`로 묶어 보여준다.
3. `experiments/<이름>/<이름>.gd`에 `extends Experiment` 스크립트를 만든다. `_ready()`에서 3D 월드를 만들고 `definition.controls`의 기본값으로 `set_control()`을 부른다. 보이는 소품·환경·연출은 `<이름>_props.gd`로 나눠 [아트 디렉션 9절](docs/art-direction.md#9-새-실험-소품-만드는-법)을 따른다. 화면 숫자는 공식(`PhysicsLaws`)에서 내고, 엔진 측정값은 따로 표시한다(공식 보정 원칙, [CONTEXT](../../CONTEXT.md)).
4. 움직임은 [공식 보정](docs/formula-correction.md) 4절 표의 방식으로 보정한다(보정기를 붙이고 화면 숫자는 `formula_values()`에서). 새 법칙은 `tools/formula-vectors.test.ts`의 실험 그룹에 TS 사례를 더하고 `PhysicsLaws`에 포트한다(parity는 자동). 문구를 바꿨으면 글꼴 서브셋을 다시 만든다.
5. `tools/build.sh`로 테스트·APK를 만들고 `bench_device.sh`로 low 60 fps를 확인한다.

`ExperimentRegistry.validate()`가 필수 필드·카메라 모드·조건 형식·`manipulation` 규칙을 검사하고, 잘못된 실험은 목록에서 빼고 오류를 남긴다.

물체를 손으로 옮기게 하려면 JSON에 `manipulation`을 더하고 스크립트에 `manipulation_body`·`manipulation_surface`(필요하면 `manipulation_juice`·`placement_allowed`·`placements`)와 결과 통보를 구현한다(1절 "조작"). 목록에 내지 않을 장면은 `index.json`의 `hidden`에 둔다.

## 6. 한계

- 조작은 물체를 면에 똑바로 세워 놓는다(면 좌표계 방향). 물체 회전·줄·용수철 연결·도구 팔레트는 Task 5다. 조작 대상의 충돌 모양은 바디의 첫 `CollisionShape3D`(상자·구·원기둥·캡슐, 원점에 놓인 것)로 본다.
- 공식 보정 계층은 알려진 면 하나 위의 마찰, 알려진 두 구의 충돌, 실험이 정한 힘·모델만 다룬다. 빈 실험실(Task 5)의 일반 다접촉 마찰·조인트는 따로 설계한다([공식 보정 2절 한계](docs/formula-correction.md#한계)).
- Web export와 iOS는 아직 만들지 않았다.
- 가로 모드에서는 패널이 조건 카드까지만 한 화면에 보이고 관찰값·그래프는 스크롤해야 한다.
