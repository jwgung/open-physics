# Phase 1 Task 4c 결과 — 충돌 실험

- 기기: SM-P200 (Galaxy Tab A 8.0 2019, Exynos 7904 / Mali-G71 MP2, Android 11, 1200×1920, 60 Hz) — 하한 기기
- 일시: 2026-10-22 18:09–18:22
- 빌드: `apps/lab3d` release APK(디버그 키스토어), Godot 4.7.2 + Jolt. 브랜치 `feat/labs-collision`(커밋 `25b06ee` 위, 문서 보완 포함).
- 계약: [Phase 1 README의 Task 4 상세](../../../../docs/3d-phase1/README.md#task-4-상세). 실험 설명은 [앱 README "실험 목록"](../../../../apps/lab3d/README.md#실험-목록), 보정은 [공식 보정 4절 Task 4c](../../../../apps/lab3d/docs/formula-correction.md#실험-구현-task-4c-충돌).
- 조건: Task 4b와 같다. USB 연결(adb, SM-P200만 사용), 충전 중(시작 전 약 27.7 °C). 손가락 입력은 `--auto-drag`(손가락 입력 경로 재생)다. 사람 손으로 한 확인은 아니다. 기기 설정(`stay_on_while_plugged_in` 2, 밝기 128, 화면 꺼짐 1800 s, 화면 크기 1200x1920)은 측정 전후 같다.

## 1. low 단계 fps

`OPBENCH_EXPERIMENT=collision OPBENCH_SUSTAINED=0 OPBENCH_OVERWRITE=1 OPBENCH_RESULTS_DIR=spikes/bench/results/phase1-task4c apps/lab3d/tools/bench_device.sh low 3 90 60`. 화면: 세로, 기본 3/4 시점, 패널을 관찰값 위치로 스크롤, 기본 조건(1 kg·2 kg 고무, 3.4·−1.7 m/s). 4초마다 공 A를 손가락 입력 경로로 끌어 놓고 0.4초 뒤 `출발`(demo_action `release`)을 눌러 충돌이 반복된다. 셰이더 캐시 1회 → 90초 × 3회(회차 사이 60초). 10분 지속 측정은 하지 않았다. 표는 `node spikes/bench/summarize.mjs spikes/bench/results/phase1-task4c`(앞 30초 제외).

| 후보 | 장면 | 평균 FPS | 1% low* | p95 ms | 최고 온도 °C | PSS MB |
|---|---|---|---|---|---|---|
| Task 4b 마찰 밀기(비교) | FR | 59.8 | 41.0 | 18.1 | 28.1 | 163 |
| **충돌** | CO | **59.7** | 37.2 | 18.1 | 27.9 | 159 |

\* 1% low는 초당 p99 프레임 시간 평균의 역수 근사(측정 기준 결과표와 같다).

| 회차 | 기록 초(30초 이후) | 평균 fps | 최저 초당 fps | 33 ms 넘는 프레임 | 드로우콜(평균 범위) | 프리미티브 | 렌더 CPU ms | 물리 ms |
|---|---|---|---|---|---|---|---|---|
| CO 1 | 76 | 59.51 | 54.3 | 14 | 100–103 | 13.9k | 3.47 | 3.64 |
| CO 2 | 92 | 59.77 | 55.0 | 8 | 100–103 | 13.9k | 3.46 | 2.87 |
| CO 3 | 92 | 59.77 | 55.9 | 8 | 100–103 | 13.9k | 3.45 | 3.04 |

- 1회차는 기록 초가 76개뿐이고 33 ms 넘는 프레임이 14개다(수집기의 `dumpsys meminfo` 몫과 첫 회차 영향으로 보이나 원인은 따로 확인하지 않았다). 2·3회차는 4b와 같은 8개다.
- 원본: `lab3d-low-CO-{1,2,3}.jsonl` / `.device.jsonl` / `.perf.jsonl`, `gpu-clock-low.log`(Mali 최고 845 MHz, AP 최고 40.4 °C).

## 2. 스크린샷과 화면 기록

| 파일 | 내용 |
|---|---|
| `screens/collision-3q.jpg`, `screens/collision-front.jpg` | 기본 3/4·정면. 노란 레일, 파란 공 A·주황 공 B, 보라색 속도 화살표와 노란 손잡이, 양 끝 범퍼 |
| `screens/collision-hit.jpg` | 두 공이 부딪히는 순간(3/4) |
| `screens/collision-panel-observations.jpg` | 충돌 뒤 관찰값(e 0.88, 충돌 전·뒤 속도 A·B, 운동량 합, A·B 충격량 ∓5.73 N·s) |
| `screens/collision-panel-graph.jpg` | 그래프: 두 물체의 운동량이 충돌 순간 서로 바뀌고 합이 유지됨 |
| `screens/collision-phone-portrait.jpg` | 폰 세로(`wm size 1080x2340`로 찍고 `wm size reset`으로 1200x1920 복원 확인) |
| `collision-drag-hit.mp4` | 12초(600×960): 공 A를 끌어 놓기 → 출발 → 충돌 → 튕김(`--auto-drag` 재생). 화살표 손잡이를 끄는 장면은 따로 찍지 않았다 |

## 3. 남은 일

- 사람 손가락으로 공·화살표 손잡이를 집기 쉬운지는 확인하지 않았다.
- 화면 기록은 영상 내용을 프레임 단위로 검토하지 않았다(스크린샷으로 장면은 확인).
