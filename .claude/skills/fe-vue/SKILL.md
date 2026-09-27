---
name: fe-vue
description: Vue 3.5 standards (3.6 Vapor mode opt-in only) — <script setup lang="ts">, defineModel, reactive props destructure, useTemplateRef/useId, Pinia 4 setup stores, Vue Router 5 typed file-based routes, TanStack Query, Nuxt 4 (app/ directory, useFetch, server routes), v-html safety, vue-tsc, and Vitest + Vue Test Utils. Use when writing, reviewing, or configuring Vue components, composables, Pinia stores, Vue Router, or Nuxt apps.
paths:
  - "**/*.vue"
  - "**/nuxt.config.*"
---

# Vue 3 Standards

Vue and Nuxt rules. Language rules are in `lang-typescript`; E2E in `testing-e2e`; accessibility
depth in `accessibility`; visual design in `frontend-design`, `impeccable`, `design-tokens`.

## Baseline

- Vue 3.5 (latest 3.5.x). Vue 3.6 is a release candidate: Vapor mode (`<script setup vapor>`) is
  opt-in per component (mixed apps need `vaporInteropPlugin`), Composition API only, no `v-memo`
  or `getCurrentInstance()` — pilot it on a measured hot path behind a flag, not app-wide, until
  3.6 is stable and your component libraries support it.
- Pinia 4 (ESM-only; install `@vue/devtools-api` alongside), Vue Router 5, Nuxt 4 (Nuxt 3 reached
  end of life on 2026-07-31). Vite for SPAs; Vitest for tests.

## Toolchain

- "Vue – Official" editor extension (formerly Volar); `vue-tsc --noEmit` in CI.
- ESLint flat config with `eslint-plugin-vue` (`flat/recommended`), `typescript-eslint`, and
  `eslint-plugin-vuejs-accessibility`; Prettier or Biome for formatting.
- `npm audit` / `pnpm audit` in CI; Renovate/Dependabot per `security-supply-chain`.

## Structure

```
src/
├── app/                      # createApp, plugins, router, app.provide() of adapters
├── features/projects/
│   ├── domain/               # Types, pure rules — no Vue imports
│   ├── application/          # Use cases + ports (ProjectRepository)
│   ├── adapters/             # HTTP/SDK clients implementing ports; Zod-validated DTO mapping
│   ├── stores/               # Pinia stores (call use cases/ports, not fetch)
│   ├── composables/          # useProjectList, useProjectForm
│   └── components/           # SFCs
└── shared/                   # UI primitives, logger, env parsing
```

- `PascalCase.vue`, one component per file; SFC order `<script setup>` → `<template>` → `<style>`.
- Vendor SDKs only inside `adapters/`; components and stores depend on ports provided via
  `app.provide()` / `inject()` (or Nuxt plugins).

## Components

- `<script setup lang="ts">` only; no Options API in new code.
- Type-based `defineProps` with reactive destructure and defaults (3.5); named-tuple `defineEmits`;
  `defineModel()` for `v-model` instead of `modelValue` + `update:modelValue` boilerplate.

```vue
<script setup lang="ts">
const { label, maxLength = 100 } = defineProps<{ label: string; maxLength?: number }>();
const emit = defineEmits<{ submit: [value: string]; cancel: [] }>();
const value = defineModel<string>({ required: true });
const inputId = useId();
const input = useTemplateRef<HTMLInputElement>('input');

function focus() {
  input.value?.focus();
}
defineExpose({ focus });
</script>

<template>
  <label :for="inputId">{{ label }}</label>
  <input :id="inputId" ref="input" v-model="value" :maxlength="maxLength" @keydown.enter="emit('submit', value)" />
</template>
```

- `defineExpose` only when a parent must call an imperative method (focus, reset).
- `v-for` always with a stable `:key`; never `v-if` and `v-for` on the same element.
- Keep template expressions trivial — move logic to `computed`.

## Reactivity and composables

- `ref()` as the default for all state (Vue docs recommendation); `reactive()` only for a local
  object you never destructure or replace. `shallowRef()` for large external data.
- `computed()` for derived state; `watch()` for side effects with explicit sources; avoid
  `deep: true` — reshape state instead.
- Composables (`useX.ts`) return refs so consumers stay reactive; clean up in `onScopeDispose` /
  `onUnmounted` (timers, listeners, `AbortController`). Returning `readonly(ref)` from a composable
  is fine.

## Pinia (state)

- One setup store per domain concept; stores orchestrate use cases and hold client state. Server
  state (lists, details, caching, retries) belongs in TanStack Query (`@tanstack/vue-query`).
- **Return state refs directly** — wrapping them in `readonly()` hides them from Pinia's state,
  breaking SSR hydration, devtools, and `$patch`. Enforce "mutate only via actions" by convention
  and lint/review.

```ts
export const useSessionStore = defineStore('session', () => {
  const users = inject(USER_REPOSITORY); // port provided in app/ via app.provide()
  if (!users) throw new Error('USER_REPOSITORY not provided');
  const currentUser = ref<User | null>(null);
  const isAuthenticated = computed(() => currentUser.value !== null);

  async function loadCurrentUser(): Promise<Result<User, 'UNAUTHENTICATED' | 'NETWORK'>> {
    const result = await users.getCurrent();
    currentUser.value = result.ok ? result.value : null;
    return result;
  }

  return { currentUser, isAuthenticated, loadCurrentUser };
});
```

- Destructure with `storeToRefs()`; call actions directly on the store.
- Do not persist tokens or PII with `pinia-plugin-persistedstate`.

## Vue Router 5

- Typed file-based routing is built into Vue Router 5 (the former `unplugin-vue-router`): Vite
  plugin from `vue-router/vite`, routes from `vue-router/auto-routes`, generated `route-map.d.ts`.
  Migrating: remove `unplugin-vue-router` and update imports per the v4→v5 guide.
- `<RouterLink>` for navigation; lazy-load route components; `useRoute()`/`useRouter()`.
- Guards (`router.beforeEach`, route `meta`) are UX only — the API enforces authorization.

## Errors

- Adapters return typed results; UI maps error codes to messages. Never swallow.
- `app.config.errorHandler` forwards uncaught component errors to the logger; `onErrorCaptured`
  for local fallbacks (return `false` only after handling). Nuxt: `<NuxtErrorBoundary>`,
  `createError`, `error.vue`.

## Security

- Template interpolation escapes output. `v-html` only with DOMPurify-sanitized content and a
  comment naming the source; never on user or CMS input directly. Same for `innerHTML` in
  directives.
- Validate user-supplied URLs bound to `:href`/`:src` (allow `https:`/`http:`/`mailto:` only).
- Anything in `import.meta.env.VITE_*` or Nuxt `runtimeConfig.public` is public — secrets stay in
  private `runtimeConfig` read only in `server/`.
- No tokens in `localStorage`; prefer HttpOnly `Secure` cookies. CSP with nonces (Nuxt:
  `nuxt-security` module).

## Performance

- `defineAsyncComponent()` and lazy routes for code splitting; `v-memo`/`v-once` only where
  profiling shows benefit; `shallowRef` for big immutable payloads.
- Track Core Web Vitals (LCP ≤ 2.5 s, INP ≤ 200 ms, CLS ≤ 0.1 at p75) with `web-vitals`.

## Nuxt 4

- `app/` directory holds `pages/`, `components/`, `composables/`, `layouts/`, `app.vue`; `server/`
  and `shared/` sit at the root. Keep auto-imports but import ports/adapters explicitly.
- Data: `useFetch`/`useAsyncData` with a unique key; `$fetch` only in event handlers and server
  code. `useState` for SSR-safe shared state — never a module-level `ref` (leaks across requests).
- Server routes (`server/api/*.ts`): `defineEventHandler`, validate with
  `readValidatedBody(event, schema.parse)` / `getValidatedQuery`, authenticate every handler, call
  a use case, throw `createError({ statusCode })` for failures.
- `useRuntimeConfig()` with `NUXT_*` env overrides; validate config at startup.
- Nuxt 5 (Nitro 3, Vite 8) is scheduled; test early with `future.compatibilityVersion: 5` on a
  branch only.

## Observability

- A `logger` module (behind a port) forwards to your telemetry SDK (OpenTelemetry web SDK, Sentry);
  no `console.log` (`no-console` lint rule). Nuxt server logs structured JSON with request ids.
- Never log tokens or form values containing PII.

## Accessibility

- Semantic elements, labelled inputs (`useId()` for ids), focus management on dialogs and route
  changes, `eslint-plugin-vuejs-accessibility` in CI; axe checks per `accessibility`.

## Testing

- Vitest + Vue Test Utils or `@testing-library/vue`; query by role/label; `await` DOM updates
  (`await nextTick()` / `findBy*`). Vitest browser mode (`vitest-browser-vue`) for real-browser
  component tests.
- `createTestingPinia()` (`@pinia/testing`) for store-dependent components; unit-test stores with a
  fake port. Nuxt: `@nuxt/test-utils`.
- E2E and visual tests: `testing-e2e`.

```ts
it('emits submit with the typed value', async () => {
  const wrapper = mount(TextField, {
    props: { label: 'Name', modelValue: '', 'onUpdate:modelValue': (v: string) => wrapper.setProps({ modelValue: v }) },
  });
  await wrapper.get('input').setValue('Apollo');
  await wrapper.get('input').trigger('keydown.enter');
  expect(wrapper.emitted('submit')?.[0]).toEqual(['Apollo']);
});
```

_Versions verified September 2026._
