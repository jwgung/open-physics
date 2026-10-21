# 웹 S2 메모리 증가 원인 조사

> 결론: **Android System WebView 155의 WebGPU(compatibility 모드)가 SM-P200(Mali-G71, Vulkan 1.1)에서 프레임마다 네이티브 메모리를 누수한다.** three.js나 Rapier, 스파이크 코드가 원인이 아니다.

조사일은 2026-10-21이다.

## 재현 루프

`device-probe.mjs`가 Capacitor WebView에 CDP(`adb forward … webview_devtools_remote_<pid>`)로 붙어 페이지를 연다. 그런 다음 10초마다 `dumpsys meminfo`의 항목별 값을 기록한다. 60초면 결과가 갈린다.

준비할 것:
- `spikes/web-threejs/capacitor.config.ts`에 `android: { webContentsDebuggingEnabled: true }`를 임시로 넣고 다시 빌드한다.
- `raw:`·`blank` 조건을 쓰려면 이 폴더의 `raw-webgpu.html`을 `spikes/web-threejs/public/debug-leak-raw.html`로 복사한다(빈 페이지는 `debug-leak-blank.html`).
- `playwright-core`가 필요하다. 별도 폴더에서 `npm i playwright-core`로 설치한다.

```bash
node device-probe.mjs "scene=S2&backend=webgpu" 60 s2-webgpu
node device-probe.mjs "raw:clear" 60 raw-clear
```

`probe.mjs`는 같은 측정을 PC 헤드리스 Chromium에서 한다.

## 결과 (60~90초, Native Heap 증가율)

| 조건 | 백엔드 | Native Heap | 비고 |
|---|---|---|---|
| 빈 페이지 + CDP 연결 | — | 0 MB/분 | 측정 오버헤드 없음 |
| S2 | WebGL2 | 0 MB/분 | 5~7 fps |
| S2 | WebGPU | 162 MB/분 | 48 fps |
| S1 (물리 없음) | WebGPU | 48 MB/분 | |
| S3 (상자 1개) | WebGPU | 76 MB/분 | |
| 최소 WebGPU 페이지: 화면 지우기만 | WebGPU | 168 MB/분 | three.js·Rapier 없음, 60 fps |
| 최소 페이지 + `writeBuffer` | WebGPU | 120 MB/분 | |
| 최소 페이지 + 삼각형 그리기 | WebGPU | 121 MB/분 | |
| PC 헤드리스 Chromium S2 | WebGL2·WebGPU | 평탄 | JS 힙 11 MB, 프로세스 RSS 평탄 |

- 계속 커지는 것은 앱 프로세스의 Native Heap뿐이다. JS 힙, Dalvik, GPU 메모리(EGL mtrack)는 평탄하다.
- `getCurrentTexture`→render pass→`submit`만 반복하는 30줄 페이지에서도 누수가 재현된다. 그래서 WebView의 WebGPU 표시 경로가 원인이다.
- 이 기기는 Vulkan 1.1이라 기본 `requestAdapter()`가 "No available adapters"를 돌려준다. `featureLevel: "compatibility"`로 요청해야 어댑터를 얻는다(three.js도 이렇게 요청한다).

## 기각한 가설

- **Rapier wasm 힙**: 물리가 없는 S1과 최소 페이지에서도 누수가 났다.
- **three.js WebGPURenderer**: three.js가 없는 최소 페이지에서도 누수가 났다.
- **스파이크의 객체 생성(재낙하 등)**: JS 힙이 평탄하고, PC에서는 재현되지 않았다.
- **CDP 측정 자체**: 빈 페이지에서 0 MB/분이었다.

## 남은 확인

- 다른 기기·GPU(Adreno, 최신 Mali)와 다른 WebView 버전에서도 재현되는지
- Chromium 이슈 트래커에 같은 보고가 있는지
- WebGL2 경로가 이 기기에서 느린 원인. 기존 `WebGLRenderer`(classic)로 바꿔 측정한 결과는 [실측 결과의 WebGL 대안 절](../results/README.md#webgpu-누수와-webgl-대안)에 있다(S2 대부분 약 8 fps).
