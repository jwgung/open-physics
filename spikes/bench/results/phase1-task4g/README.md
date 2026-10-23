# Phase 1 Task 4g 결과 — 빵고양이(던지기·마찰 밀기), 털실 공, 택배 박스

- 기기: SM-P200 (Galaxy Tab A 8.0 2019, Exynos 7904 / Mali-G71 MP2, Android 11, 1200×1920, 60 Hz) — 하한 기기
- 일시: 2026-10-23 16:18–17:50(최종 측정·촬영 17:37–17:50)
- 빌드: `apps/lab3d` release APK(디버그 키스토어), Godot 4.7.2 + Jolt
  - 빵고양이: 사용자가 고른 Blender 모델 `assets/characters/bread_cat.glb`(소스 `art_src/characters/bread_cat.py`)
  - 털실 공: `assets/props/yarn_ball.glb`
  - 택배 박스: `assets/props/parcel_box.glb`
  - 반영한 사용자 결정(2026-10-23): 발사 기둥 제거·빵 상자, 오버핸드 던지기, 모든 공 털실, 상자 택배 박스, 봉투 문양 식빵 하나
- 계약: [Phase 1 README Task 표 4g](../../../../docs/3d-phase1/README.md), 규칙·모양·예산: [아트 디렉션 11절](../../../../apps/lab3d/docs/art-direction.md#11-빵고양이-task-4g)
- 조건:
  - USB 연결(adb, SM-P200만 사용), 충전 중.
  - 기기 설정(밝기 128, `stay_on_while_plugged_in` 2, 1200x1920)은 측정 전후 같다(변경하지 않음).
  - fps 측정 중에는 호스트 Godot를 돌리지 않았다. 사람 손으로 한 확인은 아니다.

## 1. low 단계 fps (최종 빌드)

명령: `OPBENCH_EXPERIMENT=<projectile|friction> OPBENCH_SUSTAINED=0 OPBENCH_OVERWRITE=1 OPBENCH_RESULTS_DIR=$PWD/spikes/bench/results/phase1-task4g apps/lab3d/tools/bench_device.sh low 1 90 30`

- 화면: 가로, 사이드바 닫힘, 정면 시점, 기본 조건.
- 조작 `--auto-drag=4`: 4초마다 손가락 입력 경로로 끌어 놓는다.
  - 던지기: 공을 끌어 놓고 0.4초 뒤 `공 놓기`. 고양이가 0.48초 동안 오버핸드로 던진다.
  - 마찰 밀기: 손잡이를 끌어 고양이가 택배 박스를 민다.
- 셰이더 캐시 1회 → 90초 × 1회.
- 표는 `node spikes/bench/summarize.mjs spikes/bench/results/phase1-task4g`로 만들었고, 평균은 원본에서 소수 둘째 자리까지 구했다.

| 실험 | 장면 | 평균 FPS | 최저 초당 fps | 33 ms 넘는 프레임 | 1% low* | p95 ms | 최고 온도 °C | PSS MB |
|---|---|---|---|---|---|---|---|---|
| 던지기 | PJ | **59.81** | 57.0 | 8 | 39.9 | 18.4 | 28.7 | 166 |
| 마찰 밀기 | FR | **59.73** | 54.9 | 8 | 37.3 | 18.8 | 28.7 | 166 |

두 실험 모두 기준(1회 평균 ≥ 59.5)을 충족한다.

- 던지기 정점은 약 16,100개다(고양이 3,362, 털실 공 포함, 빵 상자 없을 때). 아트 예산 15,000을 넘어 문서에 예외로 적었다.
- 같은 날 앞선 빌드의 측정값:
  - 고양이 첫 연결: 던지기 59.81, 마찰 밀기 59.78
  - 털실 공 빌드: 던지기 59.79

\* 1% low는 초당 p99 프레임 시간 평균의 역수 근사.

원본: `lab3d-low-{PJ,FR}-1.{jsonl,device.jsonl,perf.jsonl}`, `gpu-clock-low.log`.

## 2. 스크린샷과 화면 기록 (최종 빌드)

근접 사진의 카메라 각도·거리와 3 m 발사 높이는 촬영할 때만 쓴 임시 실행 인자로 정했다(코드에 남기지 않음). 나머지는 앱의 시점 그대로다.

| 파일 | 내용 |
|---|---|
| `screens/idle-close-front.png`, `idle-close-left.png`, `idle-close-right.png` | 대기 근접(세 각도): 털실 공을 오버핸드 놓기 자세(어깨 위·옆·앞)로 든 고양이, 식빵 문양 봉투 |
| `screens/bag-close.png` | 봉투 근접: 식빵 그림 하나 |
| `screens/idle-front.png` | 대기 정면 기본 시점(카드·버튼과 겹치지 않음, 발사 기둥 없음) |
| `screens/high-3m-front.png`, `high-3m-follow.png` | 발사 높이 3 m: 나무 빵 상자 6개 위의 고양이 |
| `screens/throw0-windup.png`, `throw0-release.png` | 0° 던지기: 감기(공이 머리 위 오른쪽), 놓은 직후(수평으로 날아감) |
| `screens/throw45-release.png` | 45° 던지기: 놓은 직후 |
| `screens/push-sliding.png` | 마찰 밀기 53 N으로 미끄러지는 택배 박스를 두 앞발로 미는 고양이 |
| `screens/parcel-push-front.png`, `parcel-push-close.png` | 마찰 밀기 택배 박스(정면, 근접) |
| `screens/parcel-incline.png`, `parcel-incline-close.png` | 빗면 마찰 택배 박스(정면, 근접) |
| `screens/yarn-close.png`, `yarn-close-high.png` | 자유 낙하 털실 공 빨강·노랑·보라(선명한 색 수정 뒤, low / high) |
| `screens/yarn-pendulum.png`, `yarn-pendulum-close.png` | 진자 털실 추(줄 파랑·막대 주황) |
| `screens/yarn-orbit.png`, `yarn-orbit-close.png` | 궤도 털실 행성(파랑, 우주 무대) |
| `screens/yarn-collision.png` | 충돌 털실 공 A 파랑·B 주황 |
| `cat-throw.mp4` | 14초(960×600), 따라가기 시점, 45°·9 m/s를 4초마다 던짐 |
| `cat-throw-0deg.mp4` | 8초, 0°·6 m/s(수평 던지기: 머리 위로 감았다가 수평으로 놓음) |
| `preview/v3-close.png`, `preview/v3-close-high.png` | 모델 교체 직후 근접 low / high. 셰이더 sRGB 수정 뒤 low와 high 색이 같다 |
| `preview/bag-logo-front.png` | 봉투 문양 수정 뒤 Blender 미리보기 |
| `preview/yarn-front.png`, `yarn-close.png` | 털실 공 Blender 미리보기 |
| `preview/parcel-front.png`, `parcel-close.png` | 택배 박스 Blender 미리보기(갈색·빨강·노랑·보라 테이프) |

색:
- 처음 low 빌드에서 아틀라스 색이 하얗게 떴다. Compatibility 렌더러가 `source_color` 텍스처를 sRGB에서 풀지 않았기 때문이다. 지금은 셰이더(`art_lit_tex.gdshader`)가 직접 푼다.
- 그늘 면은 따뜻한 색이 남도록 그늘 색 비율을 35 %로 낮췄다.
- 앞서 바래 보인 v3 밀기·감기 사진은 sRGB 수정 전 빌드라 지웠다.
- 털실 공 색(18:00–18:07 빌드): 렌더 평균 low 노랑 `#f1c016`·빨강 `#f4393a`·보라 `#482799`(팔레트 `#ffc61a`·`#ff3b3b`·`#4b2a9a`와 ΔE 4.6·4.2·1.6)이고, high는 `#e9ba19`·`#f1393a`·`#472797`이다.
  - 수정 전에는 빨강이 `#e57879`였다. low가 `source_color` tint를 sRGB로 풀지 않았기 때문이다. 지금은 tint를 `Vector4` 선형 값으로 넘기고, 텍스처 평균으로 나눈다.
  - 이 색 수정은 셰이더 uniform 값만 바꿨고, fps는 다시 재지 않았다.

## 3. 헤드리스 확인 (요약)

자세한 항목은 [앱 README 테스트 표 "빵고양이"](../../../../apps/lab3d/README.md#3-빌드와-테스트)에 있다.

던지기:
- 발사 프레임의 손-공-발사점 오차는 2.4e-7 m다(허용 1e-4).
- 놓기 전 손과 보이는 공의 차이는 0 m다.
- 발사 뒤 엔진 위치·패널은 직접 놓기와 같다(9가지 조건, 3초).
- 높이 0–3 m에서 손 = 발사점이고, 빵 상자 윗면 = 고양이 바닥이다.
- 오버핸드(높이 0.5–3 m × 0·15·45·75°): 놓는 손이 어깨 위이고, 휘두르는 속력이 계속 늘며, 놓기 직전 1/60초 손 방향과 발사 방향의 차이는 0°다(허용 10°).

마찰 밀기:
- 앞발과 상자 면의 간격은 4.8e-7 m다.
- 고양이가 있든 없든 상자 운동과 패널 값이 720스텝 동안 같다.

작업 전 커밋과의 로그 비교(고양이 첫 연결 때):
- 마찰 밀기 720줄은 같다.
- 던지기는 같은 스텝 1,365줄이 같다. 다른 1줄은 섬 밖으로 나가 멈춘 공의 기록 창 끝 시각뿐이다.

돌연변이 7종의 실패를 확인하고 원복했다.
- 빵고양이 6종: 손 2 mm, 발사 3프레임 늦음, 팔 2 % 늘어남, 앞발 3 mm, 고양이 아래 바디, 휘두르기 마지막 직선 29° 틀어짐
- 털실 공 1종: 공 색 1 % 틀림

털실 공·택배 박스로 바꾼 뒤에도 앱 전체 시험이 통과한다. 운동·패널·parity 값은 그대로다.

## 4. 남은 일·판단 필요

- 큰 머리 때문에 생기는 겹침과 가림:
  - 낮은 각도(0–15°) 던지기에서는 휘두르기 끝에 공이 볼 옆을 스친다.
  - 감기는 머리 뒤로 가서 정면에서는 일부 가려진다.
- 던지기 정점 예산 초과(약 16,100, 3 m에서 약 17,600 / 15,000): 문서 예외로 두었다(fps 충족).
- 대기 변형(눕힌 봉투)과 다른 실험 확장은 이번 범위 밖이다.
