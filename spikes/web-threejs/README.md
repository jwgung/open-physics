# Spike A: Three.js + Rapier + Capacitor

3D 스택 비교 Phase 0의 웹 후보 측정 앱이다. 측정 기준은 [benchmark-spec](../../docs/3d-phase0/benchmark-spec.md), 후보 선택 근거는 [3D 스택 후보 조사](../../docs/research/3d-stack-candidates.md)를 따른다. 버리는 코드이며 제품 코드(`src/`)를 바꾸지 않는다.

- 렌더러: Three.js r186 `WebGPURenderer` (WebGPU, 실패하면 WebGL2 자동 fallback), 블룸은 TSL `RenderPipeline` + `BloomNode`
- 물리: `@dimforge/rapier3d-compat` 0.21.0 (wasm이 JS에 base64로 들어 있는 빌드)
- 앱: Capacitor 8.5.3 Android, `dev.openphysics.spike.web`

## 빌드와 실행

```bash
cd spikes/web-threejs
npm ci
npm test              # S3 공식 기준 테스트 + OPBENCH 형식 테스트 (헤드리스)
npm run dev           # 브라우저 개발 서버
npm run build         # dist/ 웹 빌드
```

Android release APK (디버그 키스토어 `~/.android/debug.keystore`로 서명):

```bash
export ANDROID_HOME=$HOME/Android/Sdk   # 또는 android/local.properties에 sdk.dir
npm run android:release
# 결과: android/app/build/outputs/apk/release/app-release.apk
adb install -r android/app/build/outputs/apk/release/app-release.apk
```

JDK 21, Android SDK 36(compile/target), Gradle 8.14.3(wrapper)로 빌드를 확인했다.

### 쿼리 파라미터와 버튼

| 파라미터 | 값 | 뜻 |
|---|---|---|
| `backend` | `auto`(기본) · `webgpu` · `webgl` · `classic` | 렌더 백엔드. `webgl`은 `WebGPURenderer`의 `forceWebGL`로 WebGL2를 강제한다. `classic`은 `THREE.WebGLRenderer`(오버레이 라벨 `WebGL(classic)`)로 S1–S3를 같은 씬·그림자·`antialias`·pixelRatio로 그린다 |

백엔드 우선순위: `?backend=` > localStorage(`opspike.backend`) > 빌드 시 환경변수 `VITE_DEFAULT_BACKEND`(예: `classic`) > `auto`. `adb shell pm clear` 후 classic으로 시작하는 APK는 `VITE_DEFAULT_BACKEND=classic npm run android:release`로 만든다.

`classic` 경로와 node 경로의 차이(비교 시 유의):
- S1 bloom: node는 TSL `bloom(0.9, 0.4, 0.85)`를 색에 더한다. classic은 `EffectComposer`(HalfFloat, MSAA 4x 타깃) + `RenderPass` + `UnrealBloomPass(0.9, 0.4, 0.85)` + `OutputPass`(ACES 톤매핑·sRGB)이다. 파라미터는 같지만 블룸 구현(밉 체인 커널)이 달라 번짐 모양은 완전히 같지 않을 수 있다.
- S1 별: node는 `PointsNodeMaterial` 스프라이트, classic은 `Points` + 작은 `ShaderMaterial`(점별 크기·색, `gl_PointSize = size × pixelRatio`)이다. 점 크기 스케일은 근사값이다.
- S2/S3 및 재질·조명·그림자(PCF, 맵 크기)는 동일 코드를 쓴다. 환경 IBL만 `PMREMGenerator`를 렌더러 종류에 맞게 고른다.
| `scene` | `S1` · `S2` · `S3` | 시작 장면 |
| `tex` | `2048`(기본) · `1024` · `512` | S1 행성 텍스처 크기 |

상단 막대에 장면 버튼(S1/S2/S3), FPS 오버레이 토글, 백엔드 선택이 있다. 오버레이에는 실제로 잡힌 백엔드(`WebGPU`/`WebGL2`)와 `navigator.gpu` 유무가 함께 보인다. 백엔드를 바꾸면 페이지를 다시 연다. 마지막 장면과 백엔드는 `localStorage`에 남아서, 앱을 재시작해도 같은 장면·백엔드로 열린다(Android에서는 쿼리 파라미터를 줄 수 없어서 이 방식으로 회차를 반복한다).

## 측정: collect.sh

앱은 1초마다 spec 6절 형식의 JSON 한 줄을 logcat 태그 `OPBENCH`로 남긴다.

- Capacitor는 `console.*`를 태그 `Capacitor/Console`로 보내므로, 작은 로컬 플러그인 `android/app/src/main/java/dev/openphysics/spike/web/OpBenchPlugin.java`가 `Log.i("OPBENCH", line)`을 직접 호출한다. `MainActivity`에서 등록한다. 호출은 초당 1번이다.
- 브라우저에서는 같은 줄을 `OPBENCH {...}`로 콘솔에 찍는다.
- 그래서 `spikes/bench/collect.sh`는 수정하지 않았다.

회차마다(spec 5절: 30초 워밍업 → 60초 측정 × 3, 회차 사이 재시작):

```bash
PKG=dev.openphysics.spike.web
# 1) 앱에서 측정할 장면(과 백엔드)을 한 번 골라 둔다. 이후 재시작해도 유지된다.
adb shell am force-stop $PKG && adb shell am start -n $PKG/.MainActivity
sleep 30                                             # 워밍업
spikes/bench/collect.sh web-threejs S1 1 $PKG 60     # S1 1회차
# S2, S3도 같은 방식. 백엔드를 강제로 바꿔 측정할 때는 후보명을 web-threejs-webgl2처럼 나눠 저장한다.
spikes/bench/collect.sh web-threejs S2 sustained $PKG 600   # 10분 지속
```

- `t`는 장면을 연(또는 전환한) 시점부터 센다. 워밍업 구간도 로그에 남으므로 집계할 때 `t ≥ 30`만 쓴다.
- `long`은 33 ms를 넘은 rAF 간격 수, `p50ms`·`p95ms`·`p99ms`는 그 1초 창 안의 nearest-rank 백분위다. 1% low FPS는 프레임 단위 기록이 없으므로 회차 전체에서 `1000 / p99ms`의 하위값으로 근사해야 한다(집계 규칙은 결과표에서 정한다).
- 120Hz 기기는 spec대로 시스템 설정에서 60Hz로 고정한다. 앱은 주사율을 고정하지 않는다.

## 장면 구현

### S1 궤도 (그래픽 상한)

- 중심 천체: 발광 재질(`emissiveIntensity` 3) + TSL 블룸(strength 0.9, radius 0.4, threshold 0.85), 점광원 1개.
- 행성 8개: PBR(`MeshStandardMaterial`), 알베도 2048² 8장, 노멀맵 2048² 3장(암석·얼음·가스 유형별 공유), 고리 행성 1개(반경 방향 알파 텍스처).
- 궤도선 8개, 별 5,000개. 별은 WebGPU 점 primitive가 1px만 지원해서 `Sprite` + `PointsNodeMaterial` 인스턴싱(TSL `instancedBufferAttribute`)으로 그린다.
- 운동: `src/physics/laws/orbit.ts`의 `circularOrbitSpeed`로 ω = v/r을 구해 위치를 갱신한다(장면 단위 G = 1, M = 300).
- 카메라: 30초 주기, 앞 15초 전체 보기 회전 → 뒤 15초 행성 따라가기(주기마다 다음 행성). 장면 시간 기준이라 재현된다.

### S2 역학 빈 실험실

- 바닥, 30° 빗면, 고정 블록 3개. 상자 25 + 공 25(한 변/지름 0.4 m), 재질 고무·나무·금속 3종은 `src/app/physics-playground.ts`의 `MATERIALS`에서 반발·마찰을 그대로 가져온다(금속 = `steel`).
- 방향광 실시간 그림자 1개(2048² 그림자 맵, PCF) + 반구광·환경광, 물체 PBR. 금속이 검게 보이지 않도록 절차 생성 `RoomEnvironment` IBL을 쓴다.
- 고정 seed(20260)로 높이 3~6 m에서 낙하, 20초마다 10개씩 순서대로 다시 낙하.
- 조작: 한 손가락으로 물체를 잡으면 kinematic으로 바꾸고, 바닥 평면 교차점 아래로 Rapier ray를 쏴서 바닥·빗면·블록 윗면 위로 끌고 간다. 놓으면 0.25 m 격자로 스냅하고 dynamic으로 되돌린다. 빈 곳 한 손가락·두 손가락은 카메라 회전, 핀치·휠은 확대.
- 물리는 1/60 s 고정 step(프레임당 최대 4 step).

### S3 안내형 빗면 마찰

- 각도 슬라이더(0~45°)와 20°·26°·27°·35° 프리셋, `다시` 버튼. 기본 35°. 상자가 빗면 끝을 지나면 같은 각도로 다시 놓는다(측정 중 부하 유지).
- 표시: 빗면 각도와 임계각, mg·sinθ, μs·N, 가속도 g(sinθ − μk·cosθ), 이동 거리(엔진 측정값 / 공식 ½at²), 상태. 화면 갱신은 약 10 Hz다.

## S3 공식 보정 계층

Rapier는 정지/운동 마찰을 구분하지 않는 단일 Coulomb 계수만 있다. 그래서 다음처럼 나눴다.

- **표시값은 공식 코어에서만 나온다** (`src/physics/incline-formula.ts`). `src/physics/core.ts`의 `accelerationFromForce`, `src/physics/laws/basic.ts`의 `KineticFriction`, `src/physics/laws/mechanics.ts`의 `constantAccelerationDisplacement`를 import한다. 정지 판정 규칙(|v| < 0.01 m/s 이고 |F접선| ≤ μs·N이면 정지, 아니면 μk·N, 속도 반전 시 클램프)은 제품의 `SurfaceContactFrictionModifier`와 같은 규칙을 1D 빗면 좌표로 옮겼다. 빗면 전용 공식 함수가 코어에 없어서 이 조합 코드는 스파이크에 있다.
- **움직임은 Rapier가 적분한다** (`src/physics/incline-rig.ts`). 빗면·상자 collider 마찰을 0(combine rule `Min`)으로 두고, 매 고정 step 전에 공식이 정한 마찰력을 빗면 방향 외력(`addForce`)으로 넣는다. 법선 접촉은 Rapier가 푼다. 상자 회전은 잠근다.
- 적분기 보정은 넣지 않았다. Rapier 0.21의 substep 솔버(기본 4회)는 등가속도에서 거리 오차가 +0.44%(1 s), +0.21%(2 s)라 ±1% 안이다. 처음에 semi-implicit Euler 오차(약 +1.7%)를 가정하고 leapfrog half-kick을 넣었더니 오히려 −1.2%가 되어 뺐다.

헤드리스 테스트 결과(`src/physics/incline-rig.test.ts`, dt = 1/60 s, 엔진 시간 기준):

| 검사 | 기준 | 결과 |
|---|---|---|
| 임계각 | 26.565° | 26.565° (표시값) |
| 26.0° 시작 | 정지 유지 | 3초 동안 holding, 이동 ≤ 1 mm |
| 27.0° 시작 | 1초 안에 미끄러짐 | 첫 step에 미끄러짐 시작 |
| 35° 가속도 | 표시 2.412, 측정 ±1% | 표시 2.4124, 측정 2.4124 (v(2s)−v(1s)) |
| 35° 거리 | 1.206 m / 4.825 m ±1% | 1.2112 m (+0.44%) / 4.8349 m (+0.21%) |
| 20° 10초 | 누적 이동 ≤ 1 mm | 0.017 mm |
| 보정 없음(대조군) | — | 마찰 0 Rapier는 20°에서 1초에 0.5 m 넘게 미끄러짐 |

비용:

- 연산: 데스크톱 Node 기준 step당 9.3 µs → 18.6 µs(JS↔WASM 호출 `linvel`·`resetForces`·`addForce`가 대부분). 16.7 ms 프레임 대비 무시할 수준이다.
- 구조: 이 계층은 "평평한 빗면 1개 위 상자 1개"라는 접촉을 코드가 미리 안다는 전제에서만 맞다. 여러 물체가 서로·임의 면과 닿는 빈 실험실에 정지/운동 마찰을 넣으려면 접촉마다 법선·하중을 알아야 하고, Rapier JS의 contact modification(solver contact 수정) 노출 범위는 이번에 확인하지 않았다 **[미확인]**. 즉 안내형 실험은 장치별 보정 계층으로 감당할 수 있지만, 일반 접촉 마찰을 공식 코어와 맞추는 것은 별도 설계가 필요하다.
- 결정론 패키지(`rapier3d-deterministic-compat`)는 쓰지 않았다. 테스트는 같은 머신에서 재현되지만 플랫폼 간 동일 궤적은 검증하지 않았다.

## 절차 생성·단순화한 것

- 행성·태양 텍스처, 노멀맵, 고리 텍스처는 모두 2D canvas로 절차 생성한다(띠, 얼룩, 크레이터 + 높이맵 Sobel). 등장방형 이음매·극 왜곡은 처리하지 않았다. 부하용 대체물이지 아트가 아니다.
- 별 배경은 큐브맵 대신 스프라이트 5,000개, 환경광은 HDR 대신 `RoomEnvironment`.
- 텍스처 압축(KTX2/Basis) 없음. 2048² RGBA8 + mipmap은 장당 약 21 MB라 S1은 텍스처만 약 230 MB GPU 메모리를 쓴다. 실제 제품은 압축 텍스처를 써야 하므로 S1의 메모리·업로드 비용은 실제보다 나쁘게 나온다.
- r186은 `PCFSoftShadowMap`을 없앴으므로 `PCFShadowMap`을 쓴다.

## 크기

- 웹 빌드: JS 5,273 KB(raw) / 1,913 KB(gzip -9), CSS 1.5 KB. 대부분이 base64로 들어간 Rapier wasm이다. `@dimforge/rapier3d`(별도 `.wasm`)로 바꾸면 줄일 수 있다.
- APK(release, 디버그 키 서명): 약 5.1 MB(5,084,831 B).

## 알려진 한계

- 실기기 측정은 [실측 결과](../bench/results/README.md)에 있다(SM-P200, backend auto → WebGPU). WebGL2 강제 경로는 아직 측정하지 않았다.
- 화면 확인은 헤드리스 Chromium의 SwiftShader로만 했다. WebGL2 경로는 세 장면 모두 스크린샷으로 렌더링을 확인했고, WebGPU 경로는 어댑터 획득·백엔드 선택·오류 없음까지만 확인했다(헤드리스 캡처가 WebGPU 캔버스를 비워서 찍음).
- S1은 시작할 때 2048² 텍스처 11장을 메인 스레드에서 만든다. 중급 기기에서 첫 프레임까지 수 초 걸릴 수 있고, 콜드 스타트 수치에 이 생성 시간이 들어간다.
- Capacitor 기본 템플릿의 `INTERNET` 권한을 그대로 두었다. 아동 정책 점검은 후속 과제다.
- `window.__opspike`에 현재 장면을 노출한다(헤드리스 점검용 디버그 훅).
