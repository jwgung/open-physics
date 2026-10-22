# Phase 1 Task 4b 결과 — 접촉 힘 실험(마찰 밀기)

- 기기: SM-P200 (Galaxy Tab A 8.0 2019, Exynos 7904 / Mali-G71 MP2, Android 11, 1200×1920, 60 Hz) — 하한 기기
- 일시: 2026-10-22 17:09–17:28(정식 측정 17:09–17:19)
- 빌드: `apps/lab3d` release APK(디버그 키스토어), Godot 4.7.2 + Jolt. 커밋 `442ddd9`.
- 계약: [Phase 1 README의 Task 4 상세](../../../../docs/3d-phase1/README.md#task-4-상세). 실험 설명은 [앱 README "실험 목록"](../../../../apps/lab3d/README.md#실험-목록), 보정은 [공식 보정 4절 Task 4b](../../../../apps/lab3d/docs/formula-correction.md#실험-구현-task-4b-마찰-밀기).
- 조건: Task 4a와 같다. USB 연결(adb), 충전 중(배터리 100%, 시작 전 27 °C). 손가락 입력은 `--auto-drag`(손가락 입력 경로 재생)와 `adb shell input swipe`(시스템 터치 이벤트)이다. 사람 손으로 한 확인은 아니다. 기기 설정(`stay_on_while_plugged_in` 2, 밝기 128·수동, 화면 꺼짐 1800 s, 화면 크기)은 측정 전후 같다.

## 1. low 단계 fps

`OPBENCH_EXPERIMENT=friction OPBENCH_SUSTAINED=0 OPBENCH_RESULTS_DIR=spikes/bench/results/phase1-task4b apps/lab3d/tools/bench_device.sh low 3 90 60`. 화면: 세로, 기본 3/4 시점, 패널을 관찰값 위치로 스크롤, 기본 조건(나무, 처음 상자 8 kg). 4초마다 손잡이를 손가락 입력 경로로 1초 끌고(`--auto-drag=4`) 0.4초 뒤 `처음으로`(실험의 시범 동작)를 누른다. 셰이더 캐시 1회 → 90초 × 3회(회차 사이 60초). 10분 지속 측정은 하지 않았다. 표는 `node spikes/bench/summarize.mjs spikes/bench/results/phase1-task4b`(앞 30초 제외).

| 후보 | 장면 | 평균 FPS | 1% low* | p95 ms | 최고 온도 °C | PSS MB |
|---|---|---|---|---|---|---|
| Task 2b 빗면 끄기 재생(기준) | S3 | 59.8 | 39.0 | 18.5 | 28.9 | 160 |
| Task 4a 자유 낙하 | FF | 59.7 | 36.8 | 18.6 | 29.4 | 165 |
| Task 4a 던지기 | PJ | 59.8 | 41.0 | 18.1 | 29.3 | 166 |
| **마찰 밀기** | FR | **59.8** | 41.0 | 18.1 | 28.1 | 163 |

\* 1% low는 초당 p99 프레임 시간 평균의 역수 근사(측정 기준 결과표와 같다).

| 회차 | 기록 초(30초 이후) | 평균 fps | 최저 초당 fps | 33 ms 넘는 프레임 | 드로우콜(평균 범위) | 프리미티브 | 렌더 CPU ms | 물리 ms |
|---|---|---|---|---|---|---|---|---|
| FR 1 | 92 | 59.78 | 55.9 | 8 | 112–113 | 12.4k | 3.64 | 2.92 |
| FR 2 | 92 | 59.80 | 56.9 | 8 | 112–113 | 12.4k | 3.64 | 2.83 |
| FR 3 | 92 | 59.80 | 56.9 | 8 | 112–113 | 12.4k | 3.68 | 3.03 |

- 33 ms 넘는 프레임 8개는 2a~4a와 같은 패턴(수집기의 `dumpsys meminfo` 몫).
- 원본: `lab3d-low-FR-{1,2,3}.jsonl` / `.device.jsonl` / `.perf.jsonl`, `gpu-clock-low.log`(Mali 최고 545 MHz, AP 최고 40.4 °C).

## 2. 스크린샷과 화면 기록

| 파일 | 내용 |
|---|---|
| `screens/friction-3q.jpg`, `screens/friction-front.jpg` | 기본 3/4·정면. 바닥 선, 출발선의 상자, 빨간 손잡이, 양 끝 범퍼 |
| `screens/friction-panel-observations.jpg` | 손잡이를 끄는 동안 관찰값(F 35.0 N > 최대 정지 마찰력 31.39 N, 지금 마찰력 17.27 N = μk·mg, 속력 0.91 m/s, 열에너지) |
| `screens/friction-panel-graph.jpg` | 그래프: 주는 힘(빨강)이 최대 정지 마찰력(파랑)을 넘는 순간 마찰력(주황)이 31.4 N에서 17.3 N으로 떨어짐 |
| `screens/friction-phone-portrait.jpg` | 폰 세로(`wm size 1080x2340`로 찍고 `wm size reset`으로 1200x1920 복원 확인) |
| `friction-pull-release.mp4` | 16초(600×960): 손잡이 끌기 → 힘이 커지다 상자가 미끄러짐 → 놓으면 힘 0 → 바닥 끝에 닿아 멈춤(상태 "바닥 끝에 닿았어요", 8.63 m, 열에너지 150.18 J) |

## 3. 남은 일

- 화면 기록은 한 번의 긴 끌기로 상자가 트랙 끝까지 가서 "놓으면 멈춤"보다 "바닥 끝 범퍼"가 보인다. 중간에서 놓는 장면은 따로 찍지 않았다.
- 사람 손가락으로 손잡이를 집기 쉬운지는 확인하지 않았다.
