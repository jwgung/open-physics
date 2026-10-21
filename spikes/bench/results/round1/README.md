# Phase 0 측정 결과 (1차)

- 기기: SM-P200 (Galaxy Tab A 8.0 with S Pen 2019, Exynos 7904 / Mali-G71, Android 11, WebView 155, 60Hz) — 하한 기기
- 일시: 2026-10-21 08:37–09:42, USB 연결 상태(충전 중) 측정, 밝기 128/255
- 빌드: web-threejs `5c1893b`(backend auto → WebGPU), godot `c814aa2`(Mobile renderer, Vulkan 1.1)
- 장면별 90초 × 3회(앞 30초 워밍업 제외), S2 10분 지속 1회, 콜드 스타트는 `am start -W` TotalTime 5회 중앙값(첫 프레임 아님)

| 후보 | 장면 | 평균 FPS | 1% low* | p95 ms | 10분 저하 | 최고 온도 °C | PSS MB | 콜드 스타트 ms |
|---|---|---|---|---|---|---|---|---|
| godot | S1 | 27.1 | 20.3 | 44.5 | — | 28.9 | 261 | 370 |
| godot | S2 | 11.6 | 11.4 | 86.4 | -0.8% | 28.9 | 310 | 370 |
| godot | S3 | 24.3 | 20.6 | 44.1 | — | 28.9 | 241 | 370 |
| web-threejs | S1 | 15.3 | 8.9 | 116.6 | — | 28.2 | 436 | 749 |
| web-threejs | S2 | 25.8 | 14.1 | 50.2 | 0.3% | 28.9 | 1127 | 749 |
| web-threejs | S3 | 22.1 | 16.8 | 50.1 | — | 28.6 | 353 | 749 |

\* 1% low는 초당 p99 프레임 시간(초당 30~60프레임에서는 사실상 그 초의 최악 프레임) 평균의 역수로 근사해, 전체 프레임의 하위 1%보다 보수적이다.

APK: web-threejs 5.1 MB, godot 93.7 MB. 10분 지속 중 thermal status는 두 후보 모두 0(스로틀링 없음), 배터리 온도 변화 ±0.1°C.

## 비교 시 주의: 렌더 설정이 같지 않다

| 항목 | web-threejs | godot |
|---|---|---|
| 안티에일리어싱 | `antialias: true`(MSAA 기본 4x 계열) | `msaa_3d=1`(2x) |
| 렌더 해상도 | `setPixelRatio(devicePixelRatio)` 네이티브 | 기준 720×1280 + `canvas_items` 스트레치, 3D 실제 해상도는 미확인 |
| S2 그림자 | PCF, 2048 맵 1장 | 방향광 `PARALLEL_2_SPLITS` |

S2의 FPS 역전(godot 11.6 / web 25.8)은 그림자 패스 차이 때문일 수 있다. 그렇다면 엔진 우열을 보여주는 결과가 아니다. S1에서는 web이 AA·해상도 면에서 더 무겁다. 같은 설정으로 다시 측정하는 것은 Phase 1 품질 단계 작업에 포함한다.
