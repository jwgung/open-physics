# ADR 0002: 웹 2D 화면을 지우고 TS 공식은 정답 기준으로만 남긴다

> **Status:** 채택됨
> **Date:** 2026-10-30
> **Supersedes (일부):** [ADR 0001](0001-3d-app-stack.md)의 "웹 버전도 같은 콘텐츠로 유지" 전제

## 맥락

- ADR 0001은 3D 앱을 Godot으로 만들면서 웹 버전도 같은 콘텐츠로 유지한다고 전제했다. 그래서 실험 문구를 웹과 앱이 함께 읽는 `apps/lab3d/content/mechanics-labs.json`에 두고, 앱의 `ExperimentRegistry.resolve()`가 실험 파일과 합쳤다. 앱 동작이 웹과 달라진 실험은 `app.steps`·`app.observe` 같은 덮어쓰기를 더했다.
- 2026-10-30 웹 2D 물리 실험(`src/app`, Vite 사이트)을 deprecated로 정하고 Pages 자동 배포를 멈췄다. 공유 문구를 읽는 곳은 앱 하나만 남았다.
- 다만 TS 공식 코어는 3D 앱의 GDScript 공식이 맞는지 보는 정답 기준(oracle)이다. `apps/lab3d/tools/*-vectors.test.ts`가 TS로 기대값 표를 만들고 Godot 시험이 그 표와 비교한다. 이 시험들은 `src/physics`뿐 아니라 `src/app`의 세 파일(`mechanics-challenges.ts`, `mechanics-scenes.ts`, `physics-playground.ts`의 `MATERIALS`)에도 기대고 있었다.

## 결정

1. 웹 2D 화면을 지운다: `src/app`, `index.html`, `public/`, `vite.config.ts`, `.github/workflows/pages.yml`, Vite 의존성과 빌드 스크립트, 웹 화면 전용 문서(`docs/DEVELOPMENT.md`, `docs/LAB_IMPLEMENTATION_GUIDELINES.md`, `docs/index.html`). CI의 웹 빌드는 TS 타입 검사로 바꾼다(`tsconfig.json`은 브라우저 타입 `DOM`을 빼고 `src/**`·`vitest.config.ts`만 본다).
2. 정답 기준은 남기고 `src/physics` 한곳에 모은다. `mechanics-challenges.ts`, `mechanics-scenes.ts`와 그 시험을 옮기고, 4,031줄의 웹 놀이터(`physics-playground.ts`)에서는 정답 표가 쓰는 재질 표만 `src/physics/materials.ts`로 빼낸다.
3. 실험 문구는 각 `content/experiments/<id>.json`에 둔다. `resolve()`가 합친 결과(앱 덮어쓰기 반영)를 그대로 옮기고, `mechanics-labs.json`, `resolve()`, `SHARED_KEYS`, `APP_OVERRIDES`를 지운다.

## 결과

- 실험 하나의 문구와 3D 필드를 파일 하나에서 본다. 병합 규칙과 그 시험이 사라진다.
- 레지스트리가 읽는 정의는 옮기기 전과 같다(`content` 키만 없어짐). 정답 표는 출처 경로 문자열(`source`)만 바뀌었다.
- 웹 놀이터 소스에서 상수를 읽어 시험 상수와 맞춰 보던 감시 시험(충돌·궤도·용수철·부력·진자·지렛대·도르래)은 소스가 없어져 지웠다. 그 상수는 각 벡터 시험에 지운 시점의 값으로 남는다.
- 웹 버전은 이제 없다. 웹으로 다시 내야 하면 Godot의 웹 내보내기(ADR 0001의 Compatibility 렌더러)를 쓴다. 지운 파일은 git 기록에 남는다.
- 남긴 웹 시절 문서: `docs/PHYSICS_MODELS.md`(공식 설명), `docs/PRODUCT_GUIDELINES.md`·`docs/CURRICULUM_CONTENT_PLAN.md`(제품 방향, 웹 시절 문서로 표시).
