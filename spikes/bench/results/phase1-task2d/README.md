# Phase 1 Task 2d 결과 — 가로 전용 화면 레이아웃

- 기기: SM-P200 (Galaxy Tab A 8.0 2019, Exynos 7904 / Mali-G71 MP2, Android 11, 1200×1920, 60 Hz) — 하한 기기. 앱은 가로로만 돈다(1920×1200).
- 일시: 2026-10-23 08:34–09:02
- 빌드: `apps/lab3d` release APK(디버그 키스토어), Godot 4.7.2 + Jolt. fps는 브랜치 `feat/lab-layout-drawer`의 커밋 `ad629cb`, 스크린샷은 `3869bac`에서 빌드했다. 사이에 바뀐 것은 뒤로 가기가 열린 사이드바를 먼저 닫는 것(`9380957`)과 좁은 3D 뷰에서 조작 안내를 액션 버튼 위로 올리는 것(`3869bac`)뿐이다(그리는 요소 수·면적은 같다).
- 계약: [Phase 1 README의 Task 2d 상세](../../../../docs/3d-phase1/README.md#task-2d-상세). 레이아웃 규칙은 [앱 README "레이아웃과 해상도"](../../../../apps/lab3d/README.md#레이아웃과-해상도)와 [아트 디렉션 7.1절](../../../../apps/lab3d/docs/art-direction.md#71-실험-화면-레이아웃-task-2d), 성능 근거는 [UI 해상도 결정 6절](../../../../apps/lab3d/docs/ui-resolution.md#6-가로-전용-레이아웃-task-2d).
- 조건: USB 연결(adb, SM-P200만 사용), 충전 중. 기기 설정(`stay_on_while_plugged_in` 2, 밝기 128, 화면 크기 1200x1920)은 측정·촬영 전후 같다(변경하지 않음. 폰 가로 스크린샷은 `wm size 1080x2340`으로 찍고 `wm size reset`으로 1200x1920 복원 확인). 측정 중 호스트에서 Godot를 돌리지 않았다.

## 1. low 단계 fps (사이드바 닫힘·열림)

`OPBENCH_EXPERIMENT=<id> OPBENCH_SUSTAINED=0 OPBENCH_SIDEBAR=<closed|open> OPBENCH_RESULTS_DIR=$PWD/spikes/bench/results/phase1-task2d/sidebar-<closed|open> apps/lab3d/tools/bench_device.sh low 1 90 20`(빗면, 충돌, 진자 차례로). 셰이더 캐시 1회 → 앱 재시작·30초 대기 → 90초 기록 1회. 화면: 가로, 기본 정면 시점, 기본 조건(빗면만 30°). 사이드바 닫힘은 기본 화면(3D 전체 + 핵심 카드 + 액션), 열림은 `--scroll-to=observations`(사이드바를 열고 관찰값·그래프 위치). 4초마다 첫 조작 물체를 손가락 입력 경로로 1초 동안 끌어 놓고 0.4초 뒤 `demo_action`(`--auto-drag=4`: 빗면 상자 놓기, 충돌 출발, 진자 두 추 놓기). 표는 `node spikes/bench/summarize.mjs spikes/bench/results/phase1-task2d/sidebar-<closed|open>`(앞 30초 제외)와 같은 기록의 초당 평균.

| 실험 | 장면 | 사이드바 | 평균 FPS | 최저 초당 fps | 1% low* | p95 ms | 33 ms 넘는 프레임 | 드로우콜 | 렌더 CPU ms | 물리 ms |
|---|---|---|---|---|---|---|---|---|---|---|
| 빗면 마찰 | S3 | 닫힘 | **59.81** | 57.2 | 38.3 | 18.8 | 8 | 32.5 | 2.80 | 4.23 |
| 충돌 | CO | 닫힘 | **59.78** | 56.6 | 38.3 | 18.9 | 8 | 32.7 | 2.39 | 3.52 |
| 줄·막대 진자 | CN | 닫힘 | **59.80** | 56.9 | 38.9 | 18.8 | 8 | 33.3 | 1.98 | 3.65 |
| 빗면 마찰 | S3 | 열림 | **59.79** | 56.5 | 38.9 | 18.6 | 8 | 106.1 | 3.59 | 3.50 |
| 충돌 | CO | 열림 | **59.81** | 57.3 | 39.7 | 18.4 | 8 | 67.0 | 2.59 | 3.31 |
| 줄·막대 진자 | CN | 열림 | **59.77** | 54.6 | 39.8 | 18.2 | 8 | 91.4 | 3.07 | 2.37 |

\* 1% low는 초당 p99 프레임 시간 평균의 역수 근사(측정 기준 결과표와 같다).

- 여섯 경우 모두 평균 59.5 fps 이상(판정 기준)이다. Task 4c·4e의 세로 화면(패널 스크롤, 3/4 시점) 59.7–59.8 fps와 같은 수준이다.
- 사이드바를 닫으면 2D 드로우콜이 크게 준다(빗면 106 → 33). 3D는 화면 전체(1920×1200의 45% = 864×540 픽셀)로 커지지만 fps는 같다. Mali 평균 클럭은 두 경우 모두 499 MHz(최고 676 MHz), AP 최고 40.2·42.1 °C다.
- 원본: `sidebar-{closed,open}/lab3d-low-{S3,CO,CN}-1.{jsonl,device.jsonl,perf.jsonl}`, `sidebar-*/gpu-clock-low.log`("<unix 초> <Mali kHz> <AP °C>", 5초마다).
- 한계: 실험당 1회 90초다(Task 4의 3회 측정과 다르다). 10분 지속 측정은 하지 않았다.

## 2. 스크린샷

`--experiment=<id>,--quality=low`로 열고 8초 뒤 `adb exec-out screencap`(조작 안내가 보이는 첫 화면). 모두 `screens/`.

| 파일 | 내용 |
|---|---|
| `{incline-friction,free-fall,projectile,collision,spring,friction,rotation,orbit,buoyancy,constraints,pulley}.jpg` | 태블릿 가로(1920×1200) 기본 화면 11개: 3D 전체, 정면 시점, 핵심 관찰값 카드, 액션 버튼 |
| `incline-friction-sidebar.jpg` | 사이드바 열림(`--sidebar=open`): 질문·시점·조건. 3D 뷰가 왼쪽으로 줄고 빗면 전체가 보인다 |
| `orbit-sidebar-observations.jpg` | 사이드바 열림, 관찰값 위치(`--scroll-to=observations`). 액션 버튼이 셋이라 조작 안내가 버튼 위로 간다 |
| `phone-incline-friction.jpg`, `phone-collision-sidebar.jpg` | 폰 가로 비율(`wm size 1080x2340` → 2340×1080) 기본 화면, 사이드바 열림 |
| `list.jpg`, `settings.jpg`, `phone-list.jpg` | 목록·설정 화면 가로(태블릿), 목록 폰 가로 |

## 3. 손가락 도구 확인

`apps/lab3d/tools/device_gesture.py`를 가로 좌표로 바꿨다(가상 HID 화면은 자연 방향 세로 좌표로 보고하므로 `dumpsys input`의 SurfaceOrientation으로 돌려 보냄). 같은 기기에서 `tap --at 1800,65`가 오른쪽 위 `설명·조건`을 눌러 사이드바가 열리고, `orbit`이 시점을 돌려 시점 칩이 `제한 회전`으로 바뀌는 것을 스크린샷으로 확인했다(기록 파일은 남기지 않음).

## 4. 남은 일

- 사람 손으로 사이드바 열고 닫기·카드 읽기를 확인하지 않았다(모두 실행 인자와 가상 입력).
- 실제 폰 기기에서는 찍지 않았다(태블릿 화면 크기만 바꿈). 폰의 노치·둥근 모서리·제스처 영역은 확인하지 않았다.
- iOS export 프리셋은 아직 없다. 가로 고정은 프로젝트 설정(`display/window/handheld/orientation=4`)이라 iOS에도 같은 값이 들어가지만 iOS 빌드로 확인하지 않았다.
