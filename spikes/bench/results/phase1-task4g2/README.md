# Phase 1 Task 4g2 결과 — 캐릭터 동화책 스타일(셀 셰이딩 + 갈색 외곽선)

- 기기: SM-P200 (Galaxy Tab A 8.0 2019, Exynos 7904 / Mali-G71 MP2, Android 11, 1200×1920, 60 Hz) — 하한 기기
- 일시: 2026-10-24 07:09–07:30
- 빌드: `apps/lab3d` release APK(디버그 키스토어), Godot 4.7.2 + Jolt
  - 전: `feat/dugi-rabbit` 1ccd072(셀 셰이딩·외곽선 없음, 메시 수정·점 눈 포함)
  - 후: 같은 브랜치 + 이 작업(`ArtKit.toon_material`, `art_toon_tex.gdshader`, `art_outline.gdshader`)
- 계약·결정: [아트 디렉션 11절 재질과 빛](../../../../apps/lab3d/docs/art-direction.md#11-빵고양이-task-4g), [Phase 1 README 결정 로그](../../../../docs/3d-phase1/README.md)
- 조건:
  - USB 연결(adb, SM-P200만 사용), 충전 중.
  - 기기 설정(밝기 128, `stay_on_while_plugged_in` 2, 화면 꺼짐 1,800,000 ms, 1200x1920)은 측정 전후 같다(변경하지 않음).
  - fps 측정 중에는 호스트 Godot를 돌리지 않았다.

## 1. low 단계 fps

명령: `OPBENCH_EXPERIMENT=projectile OPBENCH_SUSTAINED=0 OPBENCH_OVERWRITE=1 OPBENCH_RESULTS_DIR=<dir> apps/lab3d/tools/bench_device.sh low 1 90 30`

- 화면: 가로, 사이드바 닫힘, 정면 시점, 기본 조건. 조작 `--auto-drag=4`(4초마다 공을 끌어 놓고 0.4초 뒤 `공 놓기`, 고양이가 던짐).
- 셰이더 캐시 1회 → 90초 × 1회. 평균은 원본에서 소수 둘째 자리까지 구했다. 나머지는 `node spikes/bench/summarize.mjs`.

| 빌드 | 장면 | 평균 FPS | 최저 초당 fps | 33 ms 넘는 프레임 | 1% low* | p95 ms | 최고 온도 °C | PSS MB |
|---|---|---|---|---|---|---|---|---|
| 전 | PJ | **59.74** | 54.8 | 9 | 38.7 | 18.3 | 28.3 | 171 |
| 후 | PJ | **59.77** | 55.8 | 9 | 40.5 | 18.1 | 28.9 | 171 |

차이는 측정 오차 안이다. 기준(1회 평균 ≥ 59.5)을 충족한다. 외곽선 패스로 고양이 그리기 호출이 6번 늘었다(그리는 노드 수는 그대로 7).

\* 1% low는 초당 p99 프레임 시간 평균의 역수 근사.

원본: 후 `lab3d-low-PJ-1.{jsonl,device.jsonl,perf.jsonl}`, `gpu-clock-low.log`, 전 `before/` 같은 이름.

## 2. 스크린샷

| 파일 | 내용 |
|---|---|
| `screens/toon-front.png` | low, 던지기 정면 기본 시점(대기). 고양이 둘레·봉투 둘레·앞발/꼬리 앞에 갈색 선 |
| `screens/toon-front-high.png` | high(Mobile), 같은 시점 |
| `screens/toon-vs-blender.png` | 왼쪽: low 화면의 고양이 부분(4배 확대), 오른쪽: Blender 참고 렌더(`duo.py`, 외곽선 0.010 m, 셀 0.86) |
| `screens/toon-zoom.png` | 두 손가락 벌리기 두 번 뒤(조금 가까이) |

외곽선 두께 고르기(low, 정면 기본 시점, 고양이 키 약 130 px / 1200):
- 세계 두께 0.010 m만: 1 px이 안 돼 점선처럼 끊겼다.
- 화면 높이의 0.28 %: 대부분 이어지나 몇 군데 끊김.
- 화면 높이의 0.35 %(채택): low 3D 버퍼(540 px 높이, MSAA 없음)에서 약 1.9 px, 화면에서 약 4 px. 끊김 없음.

버그 한 건: Compatibility는 SubViewport(3D 화면)에 그릴 때 y를 뒤집어 `PROJECTION_MATRIX[1][1]`이 음수다. 처음에는 화면 두께 항이 음수가 돼 세계 두께만 남았다(0.16 %와 0.35 %가 똑같이 얇았다). `abs`로 고쳤다.

## 3. 헤드리스 확인

`apps/lab3d/tools/build.sh test` 전체 통과. 새 확인(`tests/bread_cat_checks.gd` 5번, 던지기·마찰 밀기):
- 고양이 메시 6개 모두 `art_toon_tex` 셀 셰이더 + 다음 패스 `art_outline`(코드에 `cull_front`·`unshaded`·법선 방향으로 키움), 세계 두께 0.010 m, 화면 두께 > 0, 색 = `#6e4630`(선형).
- 같은 위치 정점의 법선 차이 최대 0.016°(허용 0.5°): 외곽선이 이음매에서 갈라지지 않는 메시 계약.
- 실험의 다른 메시(털실 공·상자·섬·장치)에는 셀 셰이더도 외곽선도 없다.

물리·패널·parity 시험은 그대로 통과한다(렌더링만 바뀜).

## 4. 남은 일·판단 필요

- 외곽선 두께 0.35 %는 기본 시점에서 참고 그림보다 상대적으로 두껍다(고양이 키 대비 약 3 %, 참고 그림 약 0.7 %). low 해상도에서 끊기지 않는 가장 얇은 값이라 골랐다.
- 털실 공·택배 박스는 외곽선이 없다(캐릭터만). 참고 그림처럼 공도 넣을지 판단 필요.
- 참고 그림의 드리운 그림자(머리 → 몸)는 없다(실시간 그림자 없음 원칙).
