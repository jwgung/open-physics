# 3D 스택 후보 조사 (T2)

- 조사일: 2026-10-21
- 범위: Open Physics 3D 모바일 앱 전환 후보 (A) 웹 스택(Three.js/Babylon.js + Rapier/Havok + Capacitor), (B) Godot 4 + Jolt
- 전제(승인된 결정, 재논의하지 않음): iOS(iPad 포함)+Android, 웹 유지(한 단계 낮은 그래픽 허용), 중급 폰 60fps 10분 지속, 단일 범용 3D 물리 엔진 + 가이드 실험은 기존 TS 공식 코어를 oracle로 보정, 무료·광고/계정/서버/제3자 추적 없음, Linux CLI 중심 AI 에이전트 개발, Unity 제외
- 표기: **[확인]** 1차/고신뢰 출처로 확인, **[간접]** 비공식 또는 추론, **[미확인]** 확인 못 함 → spike 측정 대상

---

## 1. Godot 4 (최신 stable: 4.7.2, 2026-08-18)

| 항목 | 내용 | 근거 |
|---|---|---|
| 최신 버전 | 4.7-stable 2026-06-18, 4.7.1 2026-07-14, 4.7.2 2026-08-18 **[확인]** | https://godotengine.org/download/archive/ |
| 렌더러 구분 | Forward+는 "suited for desktop platforms only", Mobile은 "Used by default on mobile platforms", Compatibility는 저사양·웹용 **[확인]** | https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html |
| Mobile 렌더러 제약 | VoxelGI/SDFGI/SSIL, volumetric fog, SSR, SSAO, SSS, TAA, FSR2, PCSS(directional) 미지원. 메시당 Omni/Spot 각 8개, 뷰당 256개, 메시당 reflection probe 8개 **[확인]** | 같은 문서 |
| Mobile 렌더러 하드웨어 | Vulkan/D3D12/Metal 필요("Newer or high-end"). 구형 기기에서는 Compatibility보다 느림 **[확인]** | 같은 문서 |
| 4.7 Mobile 개선 | Vulkan Mobile이 일부 벤치마크에서 Compatibility와 "matches or even outperforms" **[확인]** (XR 맥락) | https://godotengine.org/releases/4.7/ |
| iOS 최소 기기 | Forward+/Mobile 사용 시 A12 이상 요구 자동 설정 (4.6 beta 2) **[확인]** | https://godotengine.org/article/dev-snapshot-godot-4-6-beta-2/ |
| Android 안정성 | Vulkan 드라이버 다양성이 크래시 주원인. Foundation 수정으로 출시 게임 2종 크래시율 약 4% → 1% 미만 **[확인]** | https://godotengine.org/article/godot-mobile-update-apr-2026/ |
| Jolt | 4.4에서 내장(실험적), 4.6에서 실험 라벨 제거 + 신규 3D 프로젝트 기본값 **[확인]** | https://godotengine.org/releases/4.6/ , https://docs.godotengine.org/en/4.7/tutorials/physics/using_jolt_physics.html |
| Jolt 한계(Godot 통합) | 관절 soft limit 속성 다수 미지원(Pin/Hinge/Slider/ConeTwist/Generic6DOF), SliderJoint 각도·linear limit softness/restitution/damping 미지원, separate-thread 실행은 실험적 **[확인]** | using_jolt_physics 문서 |
| Jolt 자체 기능 | Distance(스프링 포함), **Pulley**, Rack and pinion, Gear, Path, soft body, "The simulation runs deterministically" **[확인]** | https://github.com/jrouwe/JoltPhysics |
| Jolt 고급 constraint 노출 | Godot 관절 노드는 Pin/Hinge/Slider/ConeTwist/Generic6DOF뿐이라 Jolt의 Pulley/Gear는 Godot API로 바로 쓸 수 없음 **[간접]** (GDExtension 필요 추정) | 위 Godot 문서 관절 목록 기준 추론 |
| Android export | Linux에서 가능. OpenJDK 17, Android SDK, AAB는 Gradle 빌드 필요 **[확인]** | https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html |
| iOS export | "You must export for iOS from a computer running macOS with Xcode installed." 시뮬레이터는 Compatibility만 **[확인]** | https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_ios.html |
| Web export 렌더러 | WebGL 2 + Compatibility만. "Godot currently does not support WebGPU" **[확인]** | https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html |
| Web 스레드 | 4.3부터 단일 스레드가 기본. 멀티스레드 빌드는 COOP/COEP 헤더(SharedArrayBuffer) 필요, PWA 서비스워커로 대체 가능 **[확인]** | 같은 문서 |
| Web 크기 | .wasm/.pck 큼, gzip으로 약 1/4, 커스텀 템플릿으로 축소 권장 **[확인]**. 실제 MB 수치 **[미확인]** | 같은 문서 |
| Web Safari | Safari의 WebGL 2 이슈 언급, Chromium/Firefox 권장 **[확인]** | 같은 문서 |
| C# | Android/iOS 모두 "experimental", 웹 export 불가 **[확인]** | https://docs.godotengine.org/en/4.7/tutorials/scripting/c_sharp/index.html |
| 텍스트 씬 | .tscn은 "mostly human-readable and easy for version control". 단, 에디터 저장 시 주석·기본값 속성 제거, 섹션 순서 규칙 존재 **[확인]** | https://docs.godotengine.org/en/4.7/engine_details/file_formats/tscn.html |
| CLI headless | `--headless`, `--export-release/--export-debug <preset> <path>`, `--import`, `--script`, `--check-only` 지원. CI에서 `--headless` 필수 **[확인]** | https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html |

**해석**
- 모바일 고품질은 Mobile 렌더러 전제이며, SSAO/SSR/volumetric fog 등이 없어 "Solar Walk급" 연출은 baked lighting, 셰이더 직접 작성으로 메워야 한다.
- 웹은 Compatibility(WebGL2) 고정이라 승인된 "웹은 한 단계 낮음"과는 맞지만, 실제로는 단계 차이가 크다(렌더러 자체가 다름).
- 승인 조건상 C#은 웹 불가 + 모바일 실험적이므로 사실상 **GDScript** 선택. 이 경우 기존 TS 공식 코어(oracle)를 GDScript로 **이중 구현**해야 하고, 두 구현의 일치 검증이 추가로 필요하다.

---

## 2. Three.js vs Babylon.js

| 항목 | Three.js (r186, npm 0.186.1, 2026-09-24) | Babylon.js (9.31.1, 2026-10-20) |
|---|---|---|
| WebGPU 상태 | WebGPURenderer는 "still in an experimental state although its maturity level has been greatly improved" **[확인]** | 5.0(2022-05)부터 WebGPU 지원, 2024년 코어 셰이더 WGSL 재작성, WebGL과 "side by side" 유지 **[확인]** |
| WebGL2 fallback | WebGPURenderer가 WebGPU 없으면 WebGL 2 backend로 자동 fallback, `forceWebGL` 옵션 **[확인]** | 자동 fallback 문서 없음, 엔진 선택을 앱이 결정 **[확인]** (자동 전환 코드 패턴은 **[미확인]**) |
| 셰이더/후처리 | TSL → WGSL/GLSL. `ShaderMaterial`/`onBeforeCompile`/`EffectComposer`는 WebGPURenderer 미지원, TSL로 이식 필요. SSGI/SSS/개선 DoF는 신 렌더러 전용 **[확인]** | Node Material, 9.0 Clustered Lighting(WebGPU/WebGL2), Volumetric Lighting(WebGPU compute, WebGL2 fallback), Frame Graph(GPU 메모리 40%+ 절감 사례) **[확인]** |
| WebGL 전용 경로 | `WebGLRenderer`는 유지되지만 "no plans to add larger new features" **[확인]** | 동일 엔진에서 WebGL 유지 |
| 번들 크기(실측, gzip -9) | `three.core.js` 286 KB + `three.module.js` 131 KB, `three.webgpu.js` 444 KB (tree-shaking 전 전체 빌드) **[확인: npm tarball 실측]** | UMD `babylon.js` 8.7 MB raw / 1.88 MB gzip (전체). ES 모듈 tree-shaking 후 크기 **[미확인]** |
| 라이선스 | MIT | Apache-2.0 |
| 물리 | 엔진 미내장, Rapier 등 외부 | Havok 플러그인 공식 통합 |
| 모바일 성능 기능 | 공식 모바일 가이드 **[미확인]**. InstancedMesh, BatchedMesh, render bundle(WebGPU) 등 기능 존재(r185 노트) | 9.0 공지에 모바일 벤치마크 없음 **[확인]** |

릴리스 근거: https://github.com/mrdoob/three.js/releases , https://threejs.org/manual/pages/webgpurenderer.html , https://doc.babylonjs.com/setup/support/webGPU , https://blogs.windows.com/windowsdeveloper/2026/03/26/announcing-babylon-js-9-0/

### 웹 후보 선택: **Three.js (WebGPURenderer + WebGL2 fallback) + Rapier**

이유:
1. 현재 제품이 zero runtime deps TS/Vite라 라이브러리형 Three.js가 기존 구조(TS 공식 코어, 자체 UI)에 끼워 넣기 쉽다. Babylon은 엔진 전체(입력·GUI·씬 관리)를 가져오는 구조라 기존 코드와 겹친다.
2. 실측 core 번들이 Babylon 전체 빌드보다 한 자릿수 작다(Babylon tree-shaking 후 수치는 spike에서 확인).
3. 한 렌더러 API로 WebGPU와 WebGL2를 자동 전환해 "앱은 WebGPU, 웹/구형 WebView는 WebGL2" 단계를 하나의 코드로 처리할 수 있다.
4. 물리 엔진을 렌더러와 분리해 고를 수 있고, 아래 3절대로 교과 실험에 필요한 rope/spring joint가 Rapier에 바로 있다.

대가(위험): WebGPURenderer가 공식적으로 아직 experimental이고, 커스텀 셰이더는 TSL로만 써야 한다. Babylon이 WebGPU 성숙도와 내장 고급 조명(clustered/volumetric)에서는 앞선다. spike에서 TSL 경로가 WebGL2 fallback에서도 같은 품질로 동작하는지 확인해야 한다.

---

## 3. Rapier (rapier3d WASM) vs Havok (Babylon)

| 항목 | Rapier JS 0.21.0 (2026-09-25) | Havok `@babylonjs/havok` 1.3.14 |
|---|---|---|
| 라이선스 | Apache-2.0 **[확인]** (npm, https://github.com/dimforge/rapier.js) | MIT, "available free to use under the MIT license" **[확인]** (패키지 LICENSE 실측, https://doc.babylonjs.com/features/featuresDeepDive/physics/havokPlugin) |
| 결정론 | 기본 빌드는 로컬 결정론. 크로스플랫폼은 `enhanced-determinism` + IEEE 754-2008 준수 대상(WASM 포함) 필요 **[확인]**. JS용 `@dimforge/rapier3d-deterministic(-compat)` 별도 패키지 존재 **[확인: npm]** | 공식 문서에 결정론 언급 없음 **[미확인]** |
| 성능 | 공식 수치 미확인 **[미확인]** | Babylon 6.0 공지 "up to 20x faster performance"(벤치마크 상세 없음, 비교 대상 불명) **[간접]** |
| WASM 크기(실측) | 3.08 MB raw / 1.17 MB gzip (deterministic 빌드 3.11 MB / 1.17 MB) | 2.09 MB raw / 0.66 MB gzip |
| 플랫폼 제약 | **[미확인]** (SIMD 비필수 빌드로 추정) | WebAssembly SIMD 필수, iOS < 16.4 미지원 **[확인]** |
| 관절 | fixed, spherical, revolute, prismatic, generic(축 마스크), **rope(length)**, **spring(rest_length, stiffness, damping)**, multibody joint. 모터는 PD controller(stiffness/damping), max impulse **[확인]** (https://rapier.rs/docs/user_guides/javascript/joints/, https://rapier.rs/javascript3d/classes/JointData.html, 패키지 .d.ts 실측) | Lock, Ball and socket, Distance, Hinge, Prismatic, Slider, 6DoF(축별 limit) **[확인]** (https://doc.babylonjs.com/features/featuresDeepDive/physics/constraints). 전용 spring 없음, 6DoF stiffness/damping으로 구현한다는 포럼 답변 **[간접]** (https://forum.babylonjs.com/t/havok-spring-joints/40997) |
| 도르래 | 전용 pulley 없음 → rope 2개 + 운동학 보정 또는 공식 코어로 구동 **[간접]** | 전용 pulley 없음 **[간접]** |
| 소프트바디 | 0.21 JS 바인딩에 `SoftBodyDesc.rope`, Volume/Corotational/NeoHookean 셀 모델 존재 **[확인: .d.ts 실측]**, 안정성·성능 **[미확인]** | **[미확인]** |
| 마찰 모델 | Coulomb, 정지/운동 마찰 계수 구분 없음("does not make any distinction"), combine rule Average/Min/Multiply/Max, contact modification으로 비균일 마찰 **[확인]** (https://rapier.rs/docs/user_guides/javascript/colliders/) | 정지/운동 마찰 구분 여부 **[미확인]** |
| 렌더러 결합 | 렌더러 독립 | Babylon 플러그인 전제. Three.js에서 단독 사용 가능성 **[미확인]** |
| 유지 상태 | rapier.js 저장소는 2026-07-12 archived, 본 저장소 `dimforge/rapier`의 `typescript` 디렉터리로 통합 **[확인]** | Babylon 팀 유지 |

**해석**: 교과 실험(진자=rope/revolute, 용수철=spring, 경사면 마찰, 충돌)에 필요한 요소가 Rapier에 1급 API로 있다. 정지/운동 마찰 구분이 없는 점은 "정지마찰 → 미끄러짐 전환" 실험에서 공식 코어 보정이 필요하다는 뜻이다(가이드 실험 보정 전제와 일치). 결정론 패키지가 있어 golden test(동일 입력 → 동일 궤적)를 CI에서 돌리기 쉽다.

---

## 4. Capacitor WebView

| 항목 | 내용 | 근거 |
|---|---|---|
| Capacitor 버전 | `@capacitor/core` 8.5.3 (2026-10-20) **[확인: npm]**. Capacitor 8은 Xcode 26.0+, Android Studio 2025.2.1+, Android API 24+ **[확인]** | https://capacitorjs.com/docs/getting-started/environment-setup |
| iOS 빌드 | "To build iOS apps, you will need macOS." **[확인]** → Godot와 동일하게 iOS 빌드는 macOS 필수 | 같은 문서 |
| Android WebView 최소 버전 | `minWebViewVersion` 기본 60, 최저 55 **[확인]** (v7/next 문서 기준, v8 동일 여부 **[미확인]**) | https://capacitorjs.com/docs/config |
| Chrome Android WebGPU | Chrome 121부터 Android 12+, Qualcomm/ARM GPU 기본 활성 **[확인]** | https://developer.chrome.com/blog/new-in-webgpu-121 |
| Android **System WebView** WebGPU | Intent-to-Ship 계열 문서는 "Android WebView ... where hardware support is available"라고 기술 **[간접]**, caniuse는 "Android Browser 155: Not supported" 표기 **[간접, 상충]**. 실제 기본 활성 여부 **[미확인]** | https://groups.google.com/a/chromium.org/g/blink-dev/c/YFWuDlCKTP4 , https://groups.google.com/a/chromium.org/g/blink-dev/c/N3RlLGCOTJ4 , https://caniuse.com/webgpu |
| Safari iOS WebGPU | Safari 26에서 macOS/iOS/iPadOS/visionOS 출시 **[확인]**, caniuse상 iOS Safari 26.0+ 지원 **[확인]** | https://webkit.org/blog/16993/news-from-wwdc25-web-technology-coming-this-fall-in-safari-26-beta/ , https://caniuse.com/webgpu |
| WKWebView WebGPU | Apple 포럼 답변: 플래그는 Safari만 영향, "For WKWebView, the feature will work when its enabled by default", iOS 26에서 기본 활성 **[간접]** (작성자가 Apple 직원인지 페이지상 불명) | https://developer.apple.com/forums/thread/770862 |
| WKWebView 메모리 | 한도는 고정값이 아니고 기기 RAM·부하에 따라 달라지며 늘릴 수 없음, WebContent 프로세스 종료 시 `webViewWebContentProcessDidTerminate`만 통지 **[간접: Apple 포럼]**. iOS 26.4 iPhone 15에서 WebContent/GPU 프로세스 종료 보고 | https://developer.apple.com/forums/thread/771787 , https://developer.apple.com/forums/thread/766309 , https://developer.apple.com/forums/thread/822200 |
| Android WebView 3D 성능 | 같은 기기에서 Chrome 40fps vs WebView 20fps 사례(오래된 기기 특정 보고), WebView 업데이트로 해소 권고 **[간접]** | https://forum.khadas.com/t/webview-webgl-performance-problem/1706 |

**해석**: iOS 26+는 WKWebView에서 WebGPU를 기대할 수 있지만 공식 문서 확인은 못 했다. Android WebView는 상충 정보라 **WebGL2 fallback을 기본 품질 기준으로 설계**하고 WebGPU는 가능 시 상위 tier로 취급해야 안전하다. WKWebView 메모리 kill 대비로 텍스처 예산과 `webContentProcessDidTerminate` 복구 경로가 필요하다.

---

## 5. 스토어 아동 정책

### Apple Kids Category (App Review Guidelines 1.3, 5.1.4) **[확인]**
출처: https://developer.apple.com/app-store/review/guidelines/
- 앱 밖 링크, 구매, 기타 방해 요소는 parental gate 뒤에만 둔다.
- 제3자에게 PII·기기 정보 전송 금지. 제3자 analytics/advertising 원칙적 금지(예외는 IDFA·식별정보 미수집 조건).
- 아동 개인정보를 수집·전송할 수 있으면 privacy policy 필수, COPPA/GDPR 준수.
- 한 번 Kids Category 요구를 따르면 이후 업데이트에서도 계속 지켜야 한다(카테고리 해제해도).
- "For Kids"/"For Children" 메타데이터 문구는 Kids Category 전용(2.3.8).

### Google Play Families **[확인]**
출처: https://support.google.com/googleplay/android-developer/answer/9893335
- Play Console에서 target audience 선언 필수, Google이 재판정 가능.
- 아동/연령 불명 사용자에게 광고 시 Families Self-Certified Ads SDK만(본 앱은 광고 없음 → 해당 없음).
- 아동만 대상인 앱은 AAID 전송 금지, 위치 권한 요청 금지, IMEI/IMSI/MAC 등 식별자 제한.
- SDK/API는 child-directed 서비스 승인 필요. privacy policy 필수.
- Teacher Approved 프로그램 opt-in 가능(포함 보장 없음).

### 스택별 시사점
- 두 후보 모두 광고·analytics SDK를 넣지 않으면 정책상 큰 차이는 없다.
- 확인 필요: Godot export 템플릿 기본 권한(INTERNET 등)과 Capacitor 기본 플러그인이 추가하는 권한/네트워크 호출을 spike에서 manifest/Info.plist로 점검 **[미확인]**. 외부 링크(GitHub, 라이선스 페이지)는 parental gate 뒤로.
- privacy policy는 "수집 없음" 내용이라도 준비 필요.

---

## 6. Solar-Walk급 모바일 3D 품질 공개 근거

| 스택 | 근거 | 평가 |
|---|---|---|
| Three.js | 2026-05 "Photorealistic real-time solar system in Three.js": 대기 산란, 8K 텍스처, eclipse shadow, origin-shift, "runs at 60 FPS in WebGL". MAX preset은 "workstation GPUs" 대상, 모바일 fps 언급 없음 | 그래픽 수준은 근접 가능 근거, **모바일 60fps 근거 없음** **[간접]** (https://discourse.threejs.org/t/photorealistic-real-time-solar-system-in-three-js-3dsolarsystem-online/91545) |
| Babylon.js | 9.0 공지에 고급 조명 기능, 모바일 벤치마크 없음 | **[미확인]** |
| Godot 4 | Foundation이 모바일 출시작(Kamaeru, Rift Riff: 2D 중심 추정) 크래시 수정. 모바일 3D 고품질 출시작 공식 사례 못 찾음. 포럼에 4.1 Mobile 렌더러 호환 문제로 Android 포기 사례(오래됨) | **[미확인]** (https://godotengine.org/article/godot-mobile-update-apr-2026/ , https://forum.godotengine.org/t/does-anyone-use-godot-4-for-mobile-games/43673) |
| Solar Walk 자체 | 엔진 공개 정보 없음 | **[미확인]** |

결론: 어느 스택도 "중급 폰 60fps 10분 + Solar Walk급"을 공개적으로 입증한 자료는 찾지 못했다. spike 실측이 유일한 근거가 된다.

---

## 비교표

| 기준 | (A) Three.js + Rapier + Capacitor | (B) Godot 4.7 + Jolt |
|---|---|---|
| 모바일 그래픽 상한 | WebGPU(TSL, SSGI 등) 또는 WebGL2. WebView에 따라 tier 갈림 | Mobile 렌더러(Vulkan/Metal). SSAO/SSR/volumetric fog 없음 |
| 모바일 성능 안정성 | WebView 오버헤드·메모리 kill 위험, JS GC | 네이티브, Android 드라이버 이슈는 4.5~4.6에서 개선 |
| 웹 버전 | 같은 코드, 거의 동일 품질 | Compatibility(WebGL2)로 강등, 단일 스레드 기본, 큰 wasm |
| 물리 엔진 | Rapier: rope/spring joint, deterministic 패키지, 단일 마찰 계수 | Jolt: pulley/gear/결정론은 엔진 자체 기능, Godot 관절 노드는 제한·soft limit 미지원 |
| 기존 TS 공식 코어(oracle) 재사용 | 그대로 import | GDScript로 이중 구현 필요(C#은 웹 불가·모바일 실험적) |
| AI 에이전트/Linux CLI | npm/vite/vitest/Playwright, 기존 파이프라인 유지 | headless export·.tscn 텍스트 가능, 단 에디터 저장 시 정규화, 셰이더/머티리얼 저작은 에디터 친화 |
| iOS 빌드 | macOS 필요 | macOS 필요 |
| 라이선스 | MIT / Apache-2.0 / MIT | MIT / MIT(Jolt) |
| 아동 정책 대응 | SDK 미포함 시 문제 없음 | 동일 |
| 공개 품질 근거 | 데스크톱급 사례 있음, 모바일 미입증 | 미입증 |

## 선택된 웹 후보

**Three.js (r186+, WebGPURenderer, WebGL2 자동 fallback, TSL) + Rapier (`@dimforge/rapier3d`, golden test용 `rapier3d-deterministic`) + Capacitor 8**

## Spike에서 측정할 핵심 위험

1. **WebView 지속 성능**: Galaxy A5x급 Android System WebView와 3년차 iPhone WKWebView에서 대표 실험 씬 60fps를 10분 유지하는지, 발열 후 frame time 분포(p95/p99). 같은 씬을 Godot Mobile 렌더러로도 측정해 비교.
2. **Android WebView WebGPU 실제 노출**: Capacitor 앱 안에서 `navigator.gpu` 존재와 adapter 획득 여부(기기·WebView 버전별). 불가 시 WebGL2 tier 품질이 목표에 맞는지.
3. **TSL 경로의 WebGL2 fallback 품질 동등성**: 같은 TSL 머티리얼/후처리가 두 backend에서 시각적으로 동일한지.
4. **WKWebView 메모리 한도**: 텍스처·지오메트리 예산을 올리며 WebContent 종료 지점 측정, 복구 경로 동작.
5. **Rapier 정확도와 보정 비용**: 진자·용수철·경사면 마찰을 TS 공식 코어와 비교한 오차, 보정(kinematic override 또는 상태 투영) 후 체감 품질. 정지/운동 마찰 단일 계수 처리.
6. **Rapier 결정론**: deterministic 빌드로 Android/iOS/데스크톱 간 동일 궤적 여부, 성능 차이.
7. **Godot 측(비교용)**: Mobile 렌더러 Android 기기 호환성, GDScript로 공식 코어 포팅 비용과 일치 테스트 체계, headless CI export 소요.
8. **번들/설치 크기**: Three.js tree-shaken + Rapier wasm(gzip 약 1.2 MB) 앱 크기, Godot APK/IPA 크기.

## Open items

- Android System WebView의 WebGPU 기본 활성 여부(상충 정보) — 실기기 확인 필요.
- WKWebView WebGPU 공식 문서 미확인(포럼 답변만).
- Havok 결정론, 정지/운동 마찰 구분, Three.js와의 단독 결합 가능성 미확인(현재 선택에서는 비채택이라 우선순위 낮음).
- Babylon.js ES 모듈 tree-shaking 후 실제 번들 크기 미측정.
- Rapier vs Havok vs Jolt 성능 공식 벤치마크 미확인.
- Godot Web export 실제 다운로드 크기, Godot에서 Jolt Pulley/Gear를 쓰려면 GDExtension이 필요한지 미확인.
- Godot/Capacitor 기본 권한·네트워크 동작의 아동 정책 적합성 점검.
- iOS 빌드용 macOS 환경(로컬 Mac 또는 CI macOS runner) 확보 방법 — 두 후보 공통.
- Solar Walk급 모바일 품질을 공개적으로 입증한 사례가 어느 스택에도 없음 → spike 결과로만 판정.
