# Open Physics 3D (apps/lab3d)

역학 3D 실험 앱이다. Godot 4.7.2 + Jolt, GDScript. Phase 1 Task 2a에서 셸 뼈대(실험 등록, 카메라·제스처, 2D 패널, 품질 설정)와 첫 실험(빗면 마찰)을 만들었다. 계획과 진행은 [Phase 1 문서](../../docs/3d-phase1/README.md), 스택 결정은 [ADR 0001](../../docs/adr/0001-3d-app-stack.md)에 있다.

- Android: arm64-v8a release APK(디버그 키스토어 서명, 배포용 아님). 렌더러는 품질 단계가 정한다(low = Compatibility, medium·high = Mobile).
- 모든 작업은 헤드리스 CLI(`godot --headless`)로 한다. 에디터 GUI를 쓰지 않는다.
- `spikes/godot/`은 Phase 0·Task 1 참고용으로 그대로 둔다. 이 앱은 거기서 품질 단계·측정 로그·parity 테스트·빌드 스크립트를 옮겨 왔다.

## 1. 구조

```
apps/lab3d/
  project.godot, export_presets.cfg   Jolt, 60 Hz 고정 스텝, 짧은 변 720 UI 단위, 방향 sensor, Android export
  scenes/main.tscn                    App(루트 Control)
  scripts/core/                       autoload Quality(품질 단계)·Bench(OPBENCH/OPPERF), PhysicsLaws(TS 공식 포트)
  scripts/app/                        App(화면 전환·fps 표시), 목록·설정 화면, UiTheme(웹 2D 스타일), Ui(위젯 헬퍼)
  scripts/shell/                      Experiment(실험 기반 클래스), ExperimentRegistry, ExperimentScreen,
                                      View3D(3D 뷰·제스처), CameraRig(카메라 6모드), GraphView
  experiments/incline_friction/       빗면 마찰 실험(장면·공식 보정 계층)
  content/experiments/                실험 콘텐츠 JSON(index.json + 실험별 파일)
  assets/fonts/                       Noto Sans CJK KR 서브셋(Regular·Bold, SIL OFL 1.1)
  tests/                              헤드리스 테스트, TS 생성 parity 벡터
  tools/                              빌드·글꼴·벡터 생성·실기기 측정·제스처 도구
  docs/ui-resolution.md               low 단계 UI 해상도 방식 결정과 측정 근거
```

화면 흐름은 실험 목록 → 실험 화면이고, 두 화면 모두 위쪽 `설정`에서 품질 설정 화면으로 간다. Android 뒤로 가기는 실험 → 목록 → 종료 순서다. 실험 화면에서 설정을 열어도 실험 화면은 해제되지 않고 보관돼, 돌아오면 각도·재질·놓기 상태·카메라가 그대로다. 같은 렌더러에서 품질(medium ↔ high)을 바꾸면 3D 뷰를 다시 만들며 이때는 조건 값과 카메라만 유지한다. 렌더러가 바뀌는 재시작은 앱이 다시 뜨므로 실험 화면 상태는 유지되지 않고 설정 화면으로 돌아온다. 실행 인자(`--ctl-*`, `--camera` 등)는 `--experiment`로 연 실험 화면에만 적용한다.

### 셸과 실험의 경계

셸(`ExperimentScreen`)이 카메라·제스처·2D 패널·품질을 맡고, 실험은 3D 월드와 물리만 맡는다.

| 셸이 하는 일 | 실험이 답하는 것(`Experiment`) |
|---|---|
| 패널에 질문·조건·관찰값·그래프·설명을 그린다 | `set_control(id, value)` · `control_value(id)` · `run_action(id)` |
| 관찰값·그래프를 10 Hz로 갱신한다 | `observations()` → `{id: 숫자 또는 문자열}`, `graph_series()` → `{시리즈 id: PackedVector2Array}` |
| 카메라 모드·제한·"정면으로"를 처리한다 | `follow_point()`(따라가기 대상), JSON의 `camera` |
| 3D를 품질 단계 해상도의 SubViewport에 그린다 | 조명은 `Quality.configure_sun()`으로 단계에 맞춘다 |

콘텐츠(문구·조건·관찰값·그래프·시점)는 JSON 데이터다. Task 4에서 웹 2D와 같은 파일을 공유할 수 있게 코드와 분리했다.

### 카메라와 제스처

| 모드 | 동작 |
|---|---|
| 정면 · 3/4 · 위 · 옆 | 실험 JSON `camera.views`의 시점으로 약 0.4초에 걸쳐 부드럽게 옮긴다. 이동·확대는 기본값으로 돌아간다 |
| 따라가기 | `follow_point()`(빗면에서는 상자)를 따라간다 |
| 제한 회전 | 사용자가 돌린 시점. `yaw_range_deg`·`pitch_range_deg`·`distance_range`·`pan_radius` 안에서만 움직인다 |

- `정면으로` 버튼은 3D 뷰 오른쪽 위에 항상 있다. 정면 모드 + 이동·확대 초기화다.
- 터치: 두 손가락을 함께 끌면 회전(시점이 프리셋이면 `제한 회전`으로 바뀐다), 벌리거나 오므리면 확대·축소, 그 상태로 손가락을 옮기면 이동, 비틀면 좌우 회전(시작 대비 8°를 넘긴 만큼만 돌려, 확대만 할 때 손 떨림으로 프리셋이 바뀌지 않는다). 두 손가락 제스처는 처음 14 UI 단위 움직임으로 회전과 확대·이동 중 하나로 정한다. 한 손가락을 고정하고 다른 손가락만 움직여도(28 단위 이상) 확대·이동으로 인식한다.
- 빈 곳 한 손가락 드래그는 카메라에 쓰지 않는다. `View3D.single_pointer` 신호로만 내보낸다(2b 조작용).
- 데스크톱: 오른쪽 드래그 회전, 가운데 드래그 또는 Shift + 오른쪽 드래그 이동, 휠 확대·축소. 왼쪽 드래그는 한 손가락과 같이 비워 둔다.

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
| 방향광 그림자 | 끔 | 직교 1장, 1024 | 장면 최대(빗면 4분할), 2048 |

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
| `--q-<항목>=<값>` | 품질 단계 항목 덮어쓰기(측정용) |

## 3. 빌드와 테스트

```bash
apps/lab3d/tools/build.sh          # all: import → 헤드리스 테스트 → APK
apps/lab3d/tools/build.sh test     # 헤드리스 테스트만 (exports/test.log)
apps/lab3d/tools/build.sh android  # exports/android/open-physics-lab3d.apk (약 27 MB)
npm test                           # 루트: TS 테스트 + apps/lab3d/tools/incline-vectors.test.ts
```

| 테스트 | 위치 | 확인하는 것 |
|---|---|---|
| 벡터 생성·감시 | `tools/incline-vectors.test.ts`(루트 `npm test`) | TS 공식 코어(`SurfaceContactFrictionModifier`, `constantAccelerationDisplacement`)로 측정 기준 S3 쌍(μs 0.5/μk 0.4)과 재질 4종의 벡터를 만들어 `tests/incline_vectors.json`과 비교. 실험 JSON의 재질 계수가 TS `MATERIALS`와 같은지 |
| parity | `tests/run_tests.gd` | GDScript `PhysicsLaws`가 벡터와 같은 값(최대 차이 0) |
| 빗면 공식 일치 | `tests/run_tests.gd` | 앱의 빗면 실험(Jolt + 공식 보정)이 측정 기준 4절 표(26° 정지, 27° 1초 안에 미끄러짐, 35° 가속도·이동 거리 ±1%, 20° 10초 ≤ 1 mm)를 재현. 재질별로 임계각 −0.5° 정지, +0.5° 미끄러짐, 40°에서 s(1s)·s(1.5s) ±1%, 그래프 점이 공식과 일치 |
| 셸 | `tests/run_tests.gd` | 레지스트리 검증, 글꼴 서브셋이 쓰는 글자를 모두 포함, 카메라 모드 전환·제한·정면으로·따라가기, 제스처 분류(한 손가락은 카메라 불변), 세로·가로 레이아웃 |

- TS 공식을 바꾸면 vitest가 먼저 깨진다. `UPDATE_INCLINE_VECTORS=1 npx vitest run apps/lab3d`로 벡터를 다시 만든 뒤 Godot 테스트로 GDScript 쪽 불일치를 확인한다.
- UI 문구를 바꾸면 `apps/lab3d/tools/subset_font.sh`로 글꼴을 다시 만든다(fonttools가 없으면 `uvx`로 실행). 빠진 글자는 테스트가 잡는다. Noto Sans CJK에 없는 아래·위 첨자(ₛ, ₖ, ⁻¹)는 쓰지 않는다.
- `-s`로 실행하는 테스트에서는 autoload 이름이 컴파일 시점에 없어서, `Quality`·`Bench`를 쓰는 스크립트는 테스트에서 `load()`로 불러 쓴다.

## 4. 실기기 측정과 확인

```bash
apps/lab3d/tools/bench_device.sh low 3 90 60        # 90초 × 3회(회차 사이 60초) + 10분 지속
node spikes/bench/summarize.mjs spikes/bench/results/phase1-task2a
OPBENCH_PACKAGE=org.openphysics.lab3d OPBENCH_VARIANT_DIR=<dir> \
  spikes/bench/godot-variant.sh <이름> 20 40 --experiment=incline-friction --quality=low --q-ui_mode=root
python3 -I apps/lab3d/tools/device_gesture.py orbit  # orbit | pinch | pinch-fixed | pan | one-finger
```

- `bench_device.sh`는 패널을 관찰값·그래프 위치로 스크롤하고(`--scroll-to=observations`), 각도 30°에서 4초마다 상자를 다시 놓아 물리·관찰값·그래프가 계속 바뀌는 상태로 잰다. OPBENCH 장면 이름은 `S3`(측정 기준의 안내형 빗면)다.
- `device_gesture.py`는 Android `hid` 명령으로 2점 가상 멀티터치 화면을 등록해 두 손가락 제스처를 재생한다. `adb shell input`은 한 손가락만 되고, 실제 터치스크린 노드 쓰기는 SELinux가 막는다. 좌표는 세로 기준 SM-P200 화면 픽셀이다.
- 결과: [Phase 1 Task 2a 측정 결과](../../spikes/bench/results/phase1-task2a/README.md).

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
3. `experiments/<이름>/<이름>.gd`에 `extends Experiment` 스크립트를 만든다. `_ready()`에서 3D 월드를 만들고 `definition.controls`의 기본값으로 `set_control()`을 부른다. 화면 숫자는 공식(`PhysicsLaws`)에서 내고, 엔진 측정값은 따로 표시한다(공식 보정 원칙, [CONTEXT](../../CONTEXT.md)).
4. 공식을 새로 쓰면 TS 코어 기준 벡터를 `tools/`의 vitest로 만들고 `tests/run_tests.gd`에 parity·공식 일치 검사를 더한다. 문구를 바꿨으면 글꼴 서브셋을 다시 만든다.
5. `tools/build.sh`로 테스트·APK를 만들고 `bench_device.sh`로 low 60 fps를 확인한다.

`ExperimentRegistry.validate()`가 필수 필드·카메라 모드·조건 형식을 검사하고, 잘못된 실험은 목록에서 빼고 오류를 남긴다.

## 6. 한계

- 조작 평면·스냅·높이 손잡이는 Task 2b다. 한 손가락 입력은 지금 아무 일도 하지 않는다.
- 공식 보정은 빗면 전용(`friction_corrector.gd`)이다. 일반화와 CI는 Task 3이다.
- Web export와 iOS는 아직 만들지 않았다.
- 가로 모드에서는 패널이 조건 카드까지만 한 화면에 보이고 관찰값·그래프는 스크롤해야 한다.
