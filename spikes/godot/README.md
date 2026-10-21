# Spike B: Godot 4.7.2 + Jolt

Phase 0 T4. [측정 기준](../../docs/3d-phase0/benchmark-spec.md)의 S1~S3 장면을 Godot 4.7.2 stable(Jolt 기본, GDScript)로 구현한 비교용 스파이크다. 제품 코드가 아니다.

- Android: Mobile 렌더러(Vulkan), arm64-v8a, release APK(디버그 키스토어 서명)
- Web: Compatibility 렌더러(WebGL 2), 단일 스레드 빌드
- 모든 작업은 헤드리스 CLI(`godot --headless`)로 한다. 에디터 GUI를 쓰지 않는다.

## 1. 준비

```bash
spikes/godot/tools/setup_editor.sh
```

- 공식 GitHub 릴리스에서 `Godot_v4.7.2-stable_linux.x86_64.zip`과 `Godot_v4.7.2-stable_export_templates.tpz`를 받아 공식 `SHA512-SUMS.txt`로 검증한 뒤 `~/.local/share/godot-spike/`에 푼다.
- `_sc_` 파일을 둬서 self-contained 모드로 실행한다. 에디터 설정과 export 템플릿(Android·Web만)은 `~/.local/share/godot-spike/editor_data/`에 있고 `~/.config/godot`는 건드리지 않는다.
- 에디터 설정에 Android SDK(`~/Android/Sdk`), JDK(`/usr/bin/java`가 가리키는 JDK 21), 디버그 키스토어(`~/.android/debug.keystore`)를 기록한다. 경로는 `GODOT_HOME`, `ANDROID_SDK`, `JAVA_HOME_SPIKE` 환경변수로 바꿀 수 있다.

## 2. 빌드와 테스트

```bash
spikes/godot/tools/build.sh          # all: 텍스처 생성 → import → S3 테스트 → APK → Web
spikes/godot/tools/build.sh test     # S3 헤드리스 테스트만
spikes/godot/tools/build.sh android  # exports/android/open-physics-godot.apk
spikes/godot/tools/build.sh web      # exports/web/index.html
```

- 행성 텍스처는 저장소에 넣지 않는다. 처음 빌드할 때 `tools/bake_textures.gd`가 `assets/generated/`(2048², Android용)와 `assets/generated/web/`(1024², Web용)를 만든다(약 1분). Godot import가 VRAM 압축(ETC2/EAC, S3TC/BPTC)으로 바꾼다.
- release APK는 `GODOT_ANDROID_KEYSTORE_RELEASE_*` 환경변수로 디버그 키스토어를 넘겨 서명한다. 배포용이 아니다.
- 루트 vitest는 `spikes/**`를 제외하므로 `tools/s3-vectors.test.ts`는 루트 `npm test`에 들어가지 않는다. 따로 `npx vitest run --config /dev/null --root . spikes/godot/tools/s3-vectors.test.ts`로 실행한다.
- 새 worktree에서는 class cache가 없어 `build.sh test`가 실패할 수 있다. 먼저 `godot --headless --path spikes/godot --import`를 한 번 실행한다.

### 결과물 크기 (2026-10-21 빌드)

| 결과물 | 크기 | 비고 |
|---|---|---|
| Android release APK | 93.7 MB (93,656,917 B) | `libgodot_android.so` 71 MB(압축 전), 2048² 텍스처 16장 ETC2/EAC 약 67 MB(압축 전) |
| Web export 합계 | 73.5 MB raw | `index.wasm` 39.5 MB(gzip -9 10.1 MB), `index.pck` 33.7 MB(gzip -9 26.6 MB), `index.js` 0.28 MB(gzip 68 KB) |

Web 전송 크기는 gzip 기준 약 36.8 MB다. pck는 1024² 텍스처를 데스크톱(S3TC/BPTC)·모바일 브라우저(ETC2)용으로 두 벌 담는다. APK 권한은 없다(`aapt2 dump permissions` 결과 비어 있음, `permissions/internet=false`).

## 3. 설치와 측정

```bash
adb install -r spikes/godot/exports/android/open-physics-godot.apk
adb shell am start -n org.openphysics.spike.godot/com.godot.game.GodotAppLauncher
```

- 앱은 마지막으로 고른 장면을 `user://last_scene.txt`에 저장하고 다음 실행 때 그 장면으로 시작한다. 측정 기준 5절의 "회차 사이 앱 재시작"은 장면을 한 번 고른 뒤 `am force-stop` → `am start`로 하면 된다.
- 장면 전환·FPS 오버레이 토글은 화면 위쪽 버튼이다. OPBENCH의 `t`는 장면을 열 때마다 0부터 다시 센다.
- 장면별 수집(30초 워밍업은 장면을 연 뒤 기다린다):

```bash
spikes/bench/collect.sh godot S1 1 org.openphysics.spike.godot 60
spikes/bench/collect.sh godot S2 1 org.openphysics.spike.godot 60
spikes/bench/collect.sh godot S3 1 org.openphysics.spike.godot 60
spikes/bench/collect.sh godot S2 sustained org.openphysics.spike.godot 600
```

### OPBENCH 로그 경로

`scripts/bench.gd`(autoload)가 1초마다 측정 기준 6절과 같은 JSON 한 줄을 만든다. 프레임 시간은 `_process` delta다.

- Android: `JavaClassWrapper.wrap("android.util.Log")`로 `Log.i("OPBENCH", line)`을 직접 부른다. 플러그인·Gradle 빌드가 필요 없어 `collect.sh`의 `adb logcat -s OPBENCH:I`를 그대로 쓴다. `collect.sh`는 바꾸지 않았다.
- 모든 플랫폼에서 `print("OPBENCH ", line)`도 남긴다(Android logcat 태그 `godot`, Web 콘솔, 데스크톱 stdout).
- SM-P200 실기기에서 `OPBENCH` 태그로 수집되는 것을 확인했다. `OPBENCH` 태그가 비어 있는 기기에서는 다음처럼 `godot` 태그에서 뽑아 같은 파일 형식으로 저장한다.

```bash
adb logcat -v raw -s godot:I | sed -un 's/^OPBENCH //p' > spikes/bench/results/godot-S2-1.jsonl
```

### Web 실행

```bash
cd spikes/godot/exports/web && python3 -m http.server 8765
# http://127.0.0.1:8765/index.html#S2  (#S1/#S2/#S3로 시작 장면 지정)
```

단일 스레드 빌드라 COOP/COEP 헤더가 필요 없다. 헤드리스 Chromium(SwiftShader WebGL 2)에서 세 장면이 그려지고 오류가 없는 것만 확인했다. 이 환경의 FPS는 소프트웨어 렌더링이라 의미가 없다.

## 4. 장면 구현과 단순화한 부분

| 장면 | 구현 | 절차적/단순화 |
|---|---|---|
| S1 궤도 | 발광 중심 천체 + glow(HDR threshold 1.0), PBR 행성 8개(알베도+노멀맵), 고리 행성 1개, 궤도선 8개(256분할 line strip), 별 5,000개(점 메시), 30초 주기 카메라(15초 전체 보기 → 15초 행성 따라가기, 주기마다 다음 행성) | 텍스처는 FastNoiseLite로 만든 절차적 노이즈(실제 행성 사진 아님). 고리는 납작하게 누른 TorusMesh. 위치는 `circularOrbitSpeed`(GM=60, 장면 단위) 해석해 |
| S2 빈 실험실 | 바닥, 30° 빗면, 고정 블록 3개, 상자 25 + 공 25(고무·나무·강철), 그림자 있는 방향광 1개 + 하늘 환경광, seed 20261021 낙하(높이 3~6 m), 20초마다 10개 재낙하, 한 손가락 드래그(아래 표면 평면 위 0.25 m 스냅), 두 손가락 회전·핀치 확대 | 반발·마찰은 `MATERIALS`의 rubber·wood·steel 값을 Jolt `PhysicsMaterial`에 그대로 넣었다. Jolt는 정지/운동 마찰을 나누지 않고 두 표면 값의 조합 규칙도 TS와 다르다. 밀도는 스파이크용 임의값. 바닥·빗면은 wood, 블록은 steel |
| S3 안내형 빗면 | 0~45° 슬라이더와 26°/27°/35° 버튼, 상자 놓기/처음으로, 질문 문구, 공식 표시 5종(각도, 중력 접선 성분, 최대 정지 마찰력, 가속도, ½at²) + 시뮬레이션 이동 거리 | 관찰 그래프는 없다(측정 대상이 아님) |

공통: 세로 720×1280 기준, `canvas_items` stretch, 카메라는 `KEEP_WIDTH`. 한글 UI는 Noto Sans CJK KR에서 쓰는 글자만 뽑은 66 KB 서브셋(`assets/fonts/`, SIL OFL 1.1, `tools/subset_font.sh`)이라 Web에서도 시스템 글꼴 없이 보인다. UI 문구를 바꾸면 서브셋을 다시 만들어야 한다.

## 5. S3 공식 보정 설계

Jolt는 마찰 계수가 하나뿐이라 μs=0.5 / μk=0.4를 구분할 수 없다. 그래서 역할을 나눈다.

- **Jolt가 맡는 것**: 법선 방향 접촉, 적분, 충돌. 상자·빗면 재질의 마찰은 0, 반발 0, 감쇠 0.
- **보정 계층이 맡는 것**(`scripts/incline_friction.gd`): 매 고정 스텝(60 Hz) 물리 스텝 직전에 상자의 `_physics_process`에서 TS `SurfaceContactFrictionModifier`를 1차원으로 옮긴 `PhysicsLaws.corrected_tangential_force`로 접선 방향 마찰력을 계산해 `apply_central_force`로 넣는다. 접촉 판정도 TS처럼 기하(빗면 좌표계에서 상자 바닥이 표면 ±2 cm)로 한다.
- **화면 숫자**: 모두 `scripts/physics_laws.gd`의 공식 값이다. 시뮬레이션 이동 거리만 엔진 측정값으로 따로 표시한다.

구현 중 확인한 엔진 특성 두 가지:

1. Godot-Jolt는 `_integrate_forces`를 스텝 뒤에 부른다. 거기서 넣은 힘은 다음 스텝에 적용돼, 놓은 직후 첫 스텝이 보정 없이 미끄러진다(26°에서 3.7 m 미끄러짐). 그래서 보정을 `_physics_process`(스텝 전)로 옮겼다.
2. Jolt의 symplectic Euler는 정지 출발에서 s = a(t² + t·Δt)/2가 된다. 60 Hz에서 t=1s 이동 거리가 +1.7%로 허용 오차(±1%)를 넘는다. 정지에서 미끄러지기 시작하는 첫 스텝에만 접선 합력을 절반 넣는 leapfrog 시작 보정으로 s = at²/2와 일치시켰다(`--no-leapfrog`로 끄고 비교 가능).

### 헤드리스 테스트 결과

`godot --headless --path spikes/godot --fixed-fps 60 -s res://tests/run_tests.gd` (엔진 고정 스텝 기준)

| 검사 | 기준 | 결과 |
|---|---|---|
| TS↔GDScript 마찰 보정 일치 | — | 18개 벡터, 최대 차이 0.0 m/s² |
| 26.0° 정지 유지 | 정지 | 3초간 이동 0.000 mm, holding |
| 27.0° 미끄러짐 시작 | 1초 이내 | 3스텝(0.05 s)에 1 mm 넘음, s(1s)=0.4787 m(공식 0.4787) |
| 35° 가속도 | 2.412 ±1% | 2s/t² 2.4124(+0.018%), Δv/Δt 2.4124(+0.017%), 표시값 2.4124 |
| 35° 이동 거리 | 1.206 / 4.825 ±1% | 1.2062 m(+0.018%) / 4.8249 m(−0.003%) |
| 20° 10초 안정성 | ≤ 1 mm | 0.000 mm |

leapfrog 시작 보정을 끄면 s(1s)=1.2263 m(+1.685%)로 실패한다.

### 두 언어로 공식을 유지하는 비용

- 이번에 옮긴 것은 GDScript 67줄(`physics_laws.gd`: 원궤도 속력·주기, 등가속도 변위·속도, 빗면 분해, 임계각, 마찰 보정 1D)과 보정 계층 73줄(`incline_friction.gd`)이다. 전체 TS 코어(`src/physics/laws` 15개 파일(테스트 제외))를 옮기면 분량이 수십 배가 되고, 2D TS 코어를 3D로 바꾸는 설계 작업도 따로 생긴다.
- 일치 검증은 두 단계다. `tools/s3-vectors.test.ts`(별도 vitest 실행)가 TS 코어로 `tests/s3_vectors.json`을 계산해 커밋된 파일과 비교하고, `tests/run_tests.gd`가 같은 JSON으로 GDScript 포트를 검사한다. TS 공식을 바꾸면 vitest가 먼저 깨지고(`UPDATE_S3_VECTORS=1`로 재생성), 그 뒤 Godot 테스트가 GDScript 쪽 불일치를 잡는다. 공식을 추가할 때마다 벡터 생성 코드·JSON·GDScript 포트·Godot 테스트 네 곳을 손대야 한다.
- CI에는 Node와 Godot 바이너리(약 150 MB)가 둘 다 필요하다. GDScript에는 정적 타입 검사·테스트 러너 생태계가 약해 테스트 러너를 직접 썼다.
- 보정은 엔진 동작(콜백 순서, 적분기)에 기대므로 Godot·Jolt를 올릴 때마다 S3 테스트를 다시 돌려야 한다. 위 두 특성은 문서화된 계약이 아니라 이번에 실험으로 확인한 동작이다.

## 6. 한계와 위험

- 실기기 측정과 `Log.i` 경로는 SM-P200에서 확인했다([1차 실측 결과](../bench/results/README.md)). 터치 조작(두 손가락 회전·드래그 스냅)은 실기기에서 확인하지 않았다.
- Mobile 렌더러는 Vulkan이 필요하다. Vulkan 드라이버가 불안정한 기기에서는 크래시·폴백 위험이 있다.
- Web은 Compatibility 렌더러라 그림자·glow 품질과 조명 계산이 Android와 다르고, 텍스처도 1024²로 낮췄다.
- S2의 마찰은 보정하지 않은 Jolt 단일 계수다. TS `MATERIALS`의 정지 마찰(`friction + 0.18`)·기하평균 조합은 S3 보정 계층에만 있다.
- S1 텍스처 메모리: 2048² 알베도(ETC2) + 노멀(EAC RG) 16장을 밉맵까지 합치면 GPU 메모리가 약 67 MB다.
- release APK를 디버그 키스토어로 서명했다. 스토어 배포 전에 별도 키가 필요하다.

## 파일

- `project.godot`, `export_presets.cfg`: 렌더러(Android `mobile`, Web `gl_compatibility`), Jolt, 60 Hz 고정 스텝, 세로 화면, export 설정
- `scenes/*.tscn`, `scripts/*.gd`: 장면 전환(`main`), OPBENCH(`bench`), S1~S3, 궤도 카메라, 공식 포트, 보정 계층
- `tests/run_tests.gd`, `tests/s3_vectors.json`: 헤드리스 S3 테스트와 TS 생성 벡터
- `tools/`: 에디터 준비, 빌드, 텍스처 생성, 글꼴 서브셋, 벡터 생성(vitest)
