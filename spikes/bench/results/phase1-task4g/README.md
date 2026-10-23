# Phase 1 Task 4g 결과 — 빵고양이(던지기·마찰 밀기)

- 기기: SM-P200 (Galaxy Tab A 8.0 2019, Exynos 7904 / Mali-G71 MP2, Android 11, 1200×1920, 60 Hz) — 하한 기기
- 일시: 2026-10-23 16:18–16:36
- 빌드: `apps/lab3d` release APK(디버그 키스토어), Godot 4.7.2 + Jolt. 빵고양이 = 사용자가 고른 Blender 모델 `assets/characters/bread_cat.glb`(소스 `art_src/characters/bread_cat.py`)
- 계약: [Phase 1 README Task 표 4g](../../../../docs/3d-phase1/README.md), 규칙·모양·예산: [아트 디렉션 11절](../../../../apps/lab3d/docs/art-direction.md#11-빵고양이-task-4g)
- 조건: USB 연결(adb, SM-P200만 사용), 충전 중. 기기 설정(밝기 128, `stay_on_while_plugged_in` 2, 1200x1920)은 측정 전후 같다(변경하지 않음). 측정 중 호스트 Godot는 돌리지 않았다. 사람 손으로 한 확인은 아니다.

## 1. low 단계 fps

`OPBENCH_EXPERIMENT=<projectile|friction> OPBENCH_SUSTAINED=0 OPBENCH_RESULTS_DIR=$PWD/spikes/bench/results/phase1-task4g apps/lab3d/tools/bench_device.sh low 1 90 30`. 가로 화면, 사이드바 닫힘, 정면 시점, 기본 조건. `--auto-drag=4`: 4초마다 손가락 입력 경로로 끌어 놓는다. 던지기에서는 공을 끌어 놓고 0.4초 뒤 `공 놓기`를 눌러 고양이가 0.4초 동안 던진다. 마찰 밀기에서는 손잡이를 끌어 고양이가 민다. 셰이더 캐시 1회 → 90초 × 1회. 표는 `node spikes/bench/summarize.mjs spikes/bench/results/phase1-task4g`(평균은 원본에서 소수 둘째 자리).

| 실험 | 장면 | 평균 FPS | 최저 초당 fps | 33 ms 넘는 프레임 | 1% low* | p95 ms | 최고 온도 °C | PSS MB | 3D 드로우콜(패널 포함, 최빈) |
|---|---|---|---|---|---|---|---|---|---|
| 던지기 | PJ | **59.81** | 57.0 | 8 | 39.3 | 18.5 | 28.4 | 165 | 41 |
| 마찰 밀기 | FR | **59.78** | 56.6 | 8 | 39.0 | 18.4 | 28.5 | 165 | 35 |

기준(1회 평균 ≥ 59.5)을 충족한다. Task 4f(던지기 59.80)와 같은 수준이다. 던지기는 정점 약 16,200개(고양이 3,362 포함)로 아트 예산 15,000을 넘지만 low 60 fps는 유지된다.

\* 1% low는 초당 p99 프레임 시간 평균의 역수 근사.

측정 빌드와 스크린샷·화면 기록 빌드의 차이는 던지기 감기 방향(머리 위 → 머리 바깥쪽 위)과 휘두르기 곡선뿐이다. 둘 다 연기 경로라 그리는 노드·정점은 같다.

원본: `lab3d-low-{PJ,FR}-1.{jsonl,device.jsonl,perf.jsonl}`, `gpu-clock-low.log`.

## 2. 스크린샷과 화면 기록

| 파일 | 내용 |
|---|---|
| `screens/idle-follow.png` | 대기, 근접(따라가기 시점): 공을 옆 손으로 들고 있음. 얼굴·봉투를 가리지 않음 |
| `screens/idle-front.png` | 대기, 정면 기본 시점(카드·버튼과 겹치지 않음) |
| `screens/throw-windup.png` | 던지기 감기: 공이 머리 오른쪽 위로 올라감(팔 늘임) |
| `screens/throw-release.png` | 던지는 순간 직후: 공이 발사점에서 손을 떠나 공식 경로로 날아감 |
| `screens/push-sliding.png` | 마찰 밀기 58 N, 상자가 미끄러지는 중: 앞으로 기울여 두 앞발로 상자 면을 밂 |
| `screens/push-idle-front.png` | 마찰 밀기 대기, 정면 기본 시점 |
| `cat-throw.mp4` | 14초(960×600), 따라가기 시점, 5초마다 `공 놓기`(`--auto-release=5`): 감기 → 휘두르기 → 발사 → 착지 반응 |
| `preview/v3-close.png`, `preview/v3-close-high.png` | 근접 low / high. low와 high 색이 같고, Blender 미리보기(`art_src` 렌더)와 같은 모습 |
| `preview/v3-front.png`, `preview/v3-push.png` | 모델 교체 직후 정면·밀기 확인 |

색: 처음 low 빌드에서 아틀라스 색이 하얗게 떴다(크래프트 `#d9a066`이 약 `#f0d7af`로 나옴). Compatibility 렌더러가 `source_color` 텍스처를 sRGB에서 풀지 않아 출력 단계에서 sRGB로 한 번 더 인코딩됐기 때문이다. 지금은 셰이더(`art_lit_tex.gdshader`)가 직접 푼다. 고친 뒤 low와 high가 같은 색이다(`preview/v3-close*.png`).

## 3. 헤드리스 확인 (요약)

[앱 README 테스트 표 "빵고양이"](../../../../apps/lab3d/README.md#3-빌드와-테스트) 참고. 던지기 발사 프레임의 손-공 오차 2.5e-7 m(허용 1e-4), 놓기 전 공 메시와 손 0 m, 발사 뒤 3초 매 스텝 엔진 위치·패널 = 직접 놓기(7가지 조건). 밀기 앞발-상자 면 4.8e-7 m(허용 1e-4). 고양이 유무로 상자 720스텝·패널이 같다. 작업 전 커밋과의 로그 비교(던지기 6가지 × 240스텝, 마찰 밀기 2가지 × 360스텝)에서 마찰 밀기 720줄은 같다. 던지기는 같은 스텝 1,365줄이 같고, 다른 1줄은 섬 밖으로 나가 멈춘 공(달 30°)의 기록 창 끝 시각(3.95 / 3.97초)뿐이다. 기록 시작이 1스텝 다르기 때문이고 값은 같은 시각에서 같다. 돌연변이 5종(손 2 mm, 발사 3프레임 늦음, 발사 때 팔 2 % 늘어남, 앞발 3 mm 떨어짐, 고양이 아래 바디)이 실패하는 것을 확인하고 원복했다.

## 4. 남은 일·판단 필요

- 던지기 실험의 파란 발사 기둥·받침판이 고양이 봉투 앞을 조금 가린다. 고양이가 공을 드는 동안 숨길지는 사용자 판단이다.
- 던지기 정점 예산 초과(약 16,200 / 15,000): 모델 그대로 둘지, 모델 스크립트에서 줄일지 판단이 필요하다(fps는 충족).
- 대기 변형(눕힌 봉투에서 고개 내밀기)과 다른 실험 확장은 이번 범위 밖이다.
