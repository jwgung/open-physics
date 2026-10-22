# Phase 1 Task 4a 결과 — 균일장 실험(자유 낙하, 던지기)과 콘텐츠 공유

- 기기: SM-P200 (Galaxy Tab A 8.0 2019, Exynos 7904 / Mali-G71 MP2, Android 11, 1200×1920, 60 Hz) — 하한 기기
- 일시: 2026-10-22 14:41–15:16(정식 측정 14:53–15:13)
- 빌드: `apps/lab3d` release APK(디버그 키스토어), Godot 4.7.2 + Jolt. 앱 코드는 커밋 `970742d`와 같다(이후 커밋은 문서).
- 계약: [Phase 1 README의 Task 4 상세](../../../../docs/3d-phase1/README.md#task-4-상세). 실험 설명은 [앱 README "실험 목록"·"콘텐츠 공유"](../../../../apps/lab3d/README.md#실험-목록), 보정은 [공식 보정 4절](../../../../apps/lab3d/docs/formula-correction.md#실험-구현-task-4a-균일장).
- 조건: Task 2a·2b·2c와 같다. USB 연결(adb), 충전 중. 손가락 입력은 `adb shell input swipe/tap`(시스템 터치 이벤트)과 앱의 `--auto-drag`(손가락 입력 경로 재생)이다. 사람 손으로 한 확인은 아니다.

## 요약

| 판정 항목 | 결과 | 근거 |
|---|---|---|
| 10개 실험 콘텐츠를 공유 JSON으로, 웹 2D가 같은 JSON을 읽음(웹 화면·동작 불변) | 충족 | 3절 |
| 실험별 핵심 운동·표시 수치가 TS 공식과 일치(헤드리스, CI) | 충족 — `build.sh test` RESULT: PASS, 루트 `npm test` 449개 통과 | 4절 |
| SM-P200 low 60 fps(90초 × 3회, 반복 동작 상태) | 충족 — 자유 낙하 59.7, 던지기 59.8 fps | 1절 |
| 실험별 스크린샷과 짧은 화면 기록 | 충족 | 2절 |

## 1. low 단계 fps

`OPBENCH_RESULTS_DIR=spikes/bench/results/phase1-task4a OPBENCH_EXPERIMENT=<free-fall|projectile> OPBENCH_SCENE=<FF|PJ> OPBENCH_CTL= OPBENCH_SUSTAINED=0 apps/lab3d/tools/bench_device.sh low 3 90 60`. 화면: 세로, 기본 3/4 시점, 패널을 관찰값 위치로 스크롤, 조건은 기본값(지구, 높이 5 m / 45°·9 m/s). **4초마다 첫 조작 물체를 손가락 입력 경로 그대로 1초 동안 끌어 놓고 0.4초 뒤 `공 놓기`**(`--auto-drag=4`): 자유 낙하는 빨간 공을 바닥 선 끝(x 3 m)과 40% 지점(−0.5 m)으로 번갈아 옮긴 뒤 세 공을 떨어뜨리고(약 1초 낙하·착지 연출·관찰값·그래프 갱신), 던지기는 공을 발사 선 끝(−3 m)과 40% 지점(−6 m)으로 옮긴 뒤 던진다(1.4초 비행, 화살표·경로 미리보기 갱신). 끌 때마다 보조 시점이 돌고, 높이 손잡이가 선택된다. 셰이더 캐시 1회 → 90초 × 3회(회차 사이 60초). 10분 지속 측정은 하지 않았다(계약은 90초 × 3회). 표는 `node spikes/bench/summarize.mjs spikes/bench/results/phase1-task4a`(앞 30초 제외).

| 후보 | 장면 | 평균 FPS | 1% low* | p95 ms | 최고 온도 °C | PSS MB |
|---|---|---|---|---|---|---|
| Task 2b 빗면 끄기 재생(기준, [결과](../phase1-task2b/README.md)) | S3 | 59.8 | 39.0 | 18.5 | 28.9 | 160 |
| **자유 낙하** | FF | **59.7** | 36.8 | 18.6 | 29.4 | 165 |
| **던지기** | PJ | **59.8** | 41.0 | 18.1 | 29.3 | 166 |

\* 1% low는 초당 p99 프레임 시간 평균의 역수 근사(측정 기준 결과표와 같다).

| 회차 | 기록 초(30초 이후) | 평균 fps | 최저 초당 fps | 33 ms 넘는 프레임 | 드로우콜(최소–최대) | 프리미티브 | 렌더 CPU ms | 물리 ms |
|---|---|---|---|---|---|---|---|---|
| FF 1 | 92 | 59.69 | 52.5 | 10 | 106–110 | 13.5k | 3.91 | 4.20 |
| FF 2 | 92 | 59.76 | 56.8 | 8 | 106–110 | 13.5k | 3.93 | 4.08 |
| FF 3 | 92 | 59.76 | 56.8 | 8 | 106–110 | 13.5k | 3.94 | 4.07 |
| PJ 1 | 92 | 59.80 | 56.6 | 8 | 121–125 | 13.0k | 4.30 | 1.51 |
| PJ 2 | 92 | 59.81 | 57.1 | 8 | 121–125 | 13.0k | 4.26 | 1.45 |
| PJ 3 | 92 | 59.78 | 55.9 | 8 | 121–125 | 13.0k | 4.31 | 1.46 |

- 33 ms를 넘는 프레임이 회당 8개로 2a·2b·2c와 같은 패턴이다(수집기의 10초 간격 `dumpsys meminfo` 몫, Task 2a 1-1절). FF 1회차만 10개, 최저 초 52.5 fps였다.
- 자유 낙하 물리 4.1 ms는 공 세 개의 접촉 보고·착지 반응(빗면 2b 3.1–3.4 ms)이다. 1% low가 빗면보다 조금 낮다(36.8 vs 39.0). 평균은 같다.
- 원본: `lab3d-low-{FF,PJ}-{1,2,3}.jsonl` / `.device.jsonl` / `.perf.jsonl`, `gpu-clock-low.log`.
- 검증 반영 후 확인(공용 베이스·PadProps 리팩터 뒤 같은 절차, 90초 × 1회): 자유 낙하 59.7 fps(1% low 36.0, p95 18.7 ms), 던지기 59.7 fps(1% low 37.8, p95 18.2 ms), 둘 다 기준 59.5 이상. 원본 `review-check/`.

## 2. 스크린샷과 화면 기록

| 파일 | 내용 |
|---|---|
| `screens/list.jpg`, `screens/list-phone-portrait.jpg` | 실험 목록(자유 낙하·던지기·빗면), 태블릿 세로·폰 세로(`wm size 1080x2340`) |
| `screens/free-fall-3q.jpg`, `screens/free-fall-front.jpg` | 자유 낙하 기본 3/4·정면. 높이 자, 받침판 위 세 공(5 m) |
| `screens/free-fall-panel-observations.jpg`, `screens/free-fall-panel-graph.jpg` | 관찰값(낙하 중)·그래프(세 공 공식 선이 겹침 + 시뮬레이션 점) |
| `screens/free-fall-phone-portrait.jpg` | 폰 세로 |
| `screens/projectile-3q.jpg`, `screens/projectile-front.jpg` | 던지기 기본 3/4·정면. 발사대, 보라색 화살표와 노란 손잡이, 공식 경로 점, 착지 고리, 거리 눈금 |
| `screens/projectile-panel-observations.jpg`, `screens/projectile-panel-graph.jpg` | 관찰값(R 8.73 m, T 1.37 s, H 2.56 m)·그래프(공식 y(t) + 시뮬레이션 점) |
| `screens/projectile-phone-portrait.jpg` | 폰 세로 |
| `free-fall-auto-drag.mp4` | 13초: 빨간 공 끌어 옮기기(높이 유지, 높이 손잡이 표시) → 받침판이 젖혀지며 세 공 낙하 → 동시 착지(납작·먼지) |
| `projectile-auto-drag.mp4` | 13초: 공을 발사 선 위로 끌기(화살표·경로가 따라옴) → 던지기 → 착지 |
| `projectile-arrow-drag.mp4` | 15초: 화살표 끝 노란 손잡이를 `adb input swipe`로 끌어 각도를 낮춤(끄는 동안 화살표·경로 미리보기, 놓으면 15° 눈금으로 스냅) → `공 놓기` 탭 → 낮은 궤적으로 비행 |

## 3. 콘텐츠 공유와 웹 불변

- 공유 파일: `apps/lab3d/content/mechanics-labs.json`. `labs` = 웹 10개 실험(제목·분류·아이콘·질문·단계 3·관찰·용어·법칙, `web.controls`·`web.tip`, 3D로 옮긴 실험만 `app.tip`), `app_labs` = 3D 전용 빗면 마찰.
- 웹: `src/app/mechanics-labs.ts`가 `import { labs }`로 읽는다(`parseMechanicsLabs`가 id·분류·단계 수·조건 검사). `tsconfig.json`에 `resolveJsonModule`.
- 웹 불변 근거: (1) `src/app/mechanics-labs.test.ts` — 웹이 읽은 `MECHANICS_LABS`와 조작 팁 10개의 JSON SHA-256이 옮기기 전 TS 리터럴(커밋 4cb04a4)에서 잰 값 `9fcf3b93…`과 같다. 공유 파일 한 글자를 바꾸면 실패(확인). (2) `vite build` 결과의 한글 문자열 2,083개 집합이 옮기기 전과 같다(다른 것은 압축 변수 이름뿐). 이름 있는 가져오기라 `app_labs`·`about`은 웹 번들에 들어가지 않는다. (3) 기존 웹 테스트 모두 통과(445 → 447, 새 테스트 2개).
- 앱: `ExperimentRegistry.resolve()`가 실험 정의의 `content` id로 문구를 합친다. 실험 파일(`content/experiments/*.json`)에는 3D 필드(scene·camera·controls·actions·observations·graph·manipulation)만 있다. 빗면 문구는 옮긴 뒤에도 같다(헤드리스 검사). 공유 문구의 아래 첨자(`x₀`)·`⚖`·`⌁`·`▰`는 Noto Sans CJK에 없어 DejaVu Sans 서브셋을 대체 글꼴로 더했다.

## 4. 테스트

- `apps/lab3d/tools/build.sh test` RESULT: PASS(SCRIPT ERROR·`^ERROR` 없음), 루트 `npm test` 449개, `npm run build`, `npm run test:spikes`, `spikes/godot/tools/build.sh test` PASS. 커밋마다 `git archive`한 깨끗한 사본에서 같은 명령으로 확인했다.
- 균일장 실험 검사(`apps/lab3d/tests/uniform_lab_checks.gd`, 기대값 `tests/uniform_labs_vectors.json` = TS 코어 생성): 자유 낙하 6가지 표시값 최대 상대 오차 1.3e-15, 공 위치 ≤ 1e-4 m, 질량 차 0 m, 엔진 착지 ±2스텝 이내(지구 5 m: 공식 1.0096 s, 착지 62스텝), 던지기 6가지 표시값 = TS(1e-9), 위치 ≤ 1e-4 m, 착지 ±2스텝, 최고점 ±2 mm, 착지 뒤 표시 = 공식 착지 값. 실제 입력 경로(View3D 터치 → Manipulator → 실험)로 공 끌기·높이 손잡이·화살표 손잡이 스냅·막힌 방향을 확인.
- 돌연변이 9종(도약 출발 끔, 착지 시간 기준점 변경, `gravity_scale` 미적용, `gravity_scale` 이중 적용, 거리 식에 vy, 화살표 스냅 10°, 착지 표시 안 함, 떨어진 공 집을 때 리셋 안 함, 손잡이 미리보기 끔)이 모두 해당 검사를 실패시켰고 원복했다. 착지 뒤 감속을 넣었다 뺀 변경은 헤드리스에서 공이 원래 착지점에 멈춰 검사로 구분되지 않아 코드에서 뺐다.

## 5. 발견한 문제와 남은 일

- **Task 3 보정기 버그(고침)**: Godot 4.7 + Jolt의 `get_gravity()`는 `gravity_scale`을 이미 포함한다(배율 0.165에서 −1.62 반환, 실측). Task 3의 균일장·접촉 힘·충돌·힘 주입 보정기가 배율을 한 번 더 곱해, 배율이 0·1이 아닌 바디에서 도약 출발 힘과 표시 g가 틀렸다(달 낙하 1초에 0.21 m 오차). 커밋 `8351e45`에서 네 곳을 고치고 회귀 검사를 더했다. 기존 실험·테스트는 배율 0·1만 써서 영향이 없었다.
- 그래프 가로축이 3초 고정이라 달에서의 긴 비행은 앞부분만 그려진다.
- 공은 회전을 잠갔다(착지 뒤 굴러가지 않고 미끄러짐).
- 사람 손가락으로 화살표 손잡이(0.3 m, 기본 거리에서 화면 약 30 UI 단위)를 집기 쉬운지는 확인하지 않았다.
