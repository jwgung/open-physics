# Phase 1 Task 4f 결과 — 공 회전·구름(자유 낙하·던지기), 여러 공 색 구분

1–3절은 첫 구현(수평·회전만 공식, 수직 튕김은 엔진)의 측정이다. 사용자 결정 반영 뒤(착지 뒤 공 모델, 구름 저항, 흰 띠, 흰 받침판)의 측정은 4절.

- 기기: SM-P200 (Galaxy Tab A 8.0 2019, Exynos 7904 / Mali-G71 MP2, Android 11, 1200×1920, 60 Hz) — 하한 기기
- 일시: 2026-10-23 10:46–10:58
- 빌드: `apps/lab3d` release APK(디버그 키스토어), Godot 4.7.2 + Jolt. fps는 커밋 `a7875ac`(회전·구름) 빌드, 스크린샷·화면 기록은 `73a15f8`(+ 공 색 구분) 빌드. 두 커밋 사이 앱 변경은 공·상자 색과 이름(물리·화면 구성 같음).
- 계약: [Phase 1 README Task 표 4f](../../../../docs/3d-phase1/README.md), 공식·측정: [공식 보정 4절 Task 4f](../../../../apps/lab3d/docs/formula-correction.md#실험-구현-task-4f-공-회전구름), 색: [아트 디렉션 2절](../../../../apps/lab3d/docs/art-direction.md).
- 조건: USB 연결(adb, SM-P200만 사용), 충전 중. 기기 설정(밝기 128, `stay_on_while_plugged_in` 2, 1200x1920)은 측정 전후 같다(변경하지 않음). 사람 손으로 한 확인은 아니다. 자유 낙하 측정 중 호스트에서 헤드리스 Godot 탐침을 몇 초 돌렸다(기기 쪽 측정과는 별개 프로세스).

## 1. low 단계 fps

`OPBENCH_EXPERIMENT=<free-fall|projectile> OPBENCH_SUSTAINED=0 OPBENCH_RESULTS_DIR=$PWD/spikes/bench/results/phase1-ball-spin apps/lab3d/tools/bench_device.sh low 1 90 30`. 가로 화면, 사이드바 닫힘, 정면 시점, 기본 조건. `--auto-drag=4`: 4초마다 첫 공을 손가락 입력 경로로 끌어 놓고 0.4초 뒤 `공 놓기`(던지기 공은 1.4초 날고 착지 뒤 구른다). 셰이더 캐시 1회 → 90초 × 1회. 표는 `node spikes/bench/summarize.mjs spikes/bench/results/phase1-ball-spin`(앞 30초 제외).

| 실험 | 장면 | 평균 FPS | 최저 초당 fps | 33 ms 넘는 프레임 | 1% low* | p95 ms | 최고 온도 °C | PSS MB |
|---|---|---|---|---|---|---|---|---|
| 자유 낙하 | FF | **59.83** | 57.5 | 8 | 39.1 | 18.5 | 28.4 | 165 |
| 던지기 | PJ | **59.80** | 55.9 | 8 | 39.1 | 18.4 | 28.6 | 165 |

기준(1회 평균 ≥ 59.5) 충족. Task 4a(자유 낙하 59.7, 던지기 59.8)와 같은 수준이다.

\* 1% low는 초당 p99 프레임 시간 평균의 역수 근사.

원본: `lab3d-low-{FF,PJ}-1.{jsonl,device.jsonl,perf.jsonl}`, `gpu-clock-low.log`.

## 2. 스크린샷과 화면 기록

| 파일 | 내용 |
|---|---|
| `screens/free-fall-colours-landed.jpg`, `screens/free-fall-colours-falling.jpg` | 자유 낙하 새 색(왼쪽부터 노랑 0.5 kg·보라 1 kg·빨강 3 kg), 착지 뒤·떨어지는 중(정면) |
| `screens/projectile-landing-follow.jpg` | 던지기 첫 튕김(따라가기 시점, 먼지) |
| `screens/projectile-rolling-follow.jpg`, `screens/projectile-rolling-edge-follow.jpg` | 착지 뒤 5/7 vx = ωr로 굴러가는 공, 섬 끝 직전 |
| `screens/projectile-rolling-front.jpg` | 정면 시점에서 구르는 공(오른쪽 끝) |
| `projectile-roll.mp4` | 14초(960×600), 따라가기 시점: 던지기 → 튕김 → 구름 → 섬 끝에서 멈춤·숨김, 8초마다 다시 던짐(`--auto-release=8`) |

## 3. 남은 일

- 사람 눈으로 회전이 자연스러운지(흰 띠가 없는 단색 공이라 구름이 잘 보이는지)는 확인하지 않았다. 충돌 공처럼 흰 띠를 더할지는 사용자 판단.
- 화면 기록은 프레임 단위로 검토하지 않았다.

## 4. 착지 뒤 공 모델 반영 뒤 (커밋 `4babeea`) — 사용자 요청으로 중단

- 빌드: 커밋 `4babeea`(착지 뒤 64비트 공 모델: 튕김·쿨롱 충격·구름 저항 μ_r 0.05·정지, 흰 띠, 흰·회색 받침판)의 release APK. 같은 SM-P200, `OPBENCH_EXPERIMENT=<free-fall|projectile> OPBENCH_SUSTAINED=0 OPBENCH_RESULTS_DIR=$PWD/spikes/bench/results/phase1-ball-spin/contact-model apps/lab3d/tools/bench_device.sh low 1 90 30`.
- 측정 도중 사용자 요청으로 기기 작업을 중단했다(2026-10-23 11:30경). 그 뒤 adb·기기는 쓰지 않았다(설정 복원 여부는 확인하지 못함: 이 측정은 설정을 바꾸지 않는다).

| 실험 | 기록 초(30초 이후) | 평균 fps | 최저 초당 fps | 33 ms 넘는 프레임 | 판정 |
|---|---|---|---|---|---|
| 자유 낙하 FF | 91 | **59.83** | 57.0 | 8 | 90초 1회 완료(기준 59.5 이상) |
| 던지기 PJ | 68 | 59.81 | 58.0 | 6 | **미측정**(90초 중 68초에서 중단, 참고값) |

- 원본: `contact-model/lab3d-low-{FF,PJ}-1.{jsonl,device.jsonl,perf.jsonl}`, `contact-model/gpu-clock-low.log`(PJ는 중단된 부분 기록).
- 스크린샷(흰 띠, 멈춘 공 — 예: 45°·5 m/s는 x 6.65 m에서 7.25 s에 멈춤): **미측정**. 2절 스크린샷은 흰 띠·흰 받침판 이전 빌드다.
