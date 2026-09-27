---
name: fe-vue
description: Vue 3 development standards — Composition API, TypeScript, Pinia, Nuxt compatibility. Use when writing or reviewing Vue 3 or Nuxt code.
paths:
  - "**/*.vue"
  - "**/src/components/**/*.ts"
  - "**/src/composables/**"
  - "**/src/stores/**"
---

# Vue 3 Development Standards

## Composition API (Required)
- Always use Composition API with `<script setup>` — never Options API in new code
- `<script setup lang="ts">` for TypeScript support
- `defineProps` and `defineEmits` with TypeScript generics (not runtime declarations)
- `defineExpose` only when a parent truly needs to call child methods

```vue
<script setup lang="ts">
interface Props {
  userId: string;
  initialData?: User;
}
interface Emits {
  (e: 'update', user: User): void;
  (e: 'delete', id: string): void;
}
const props = defineProps<Props>();
const emit = defineEmits<Emits>();
</script>
```

## Component Design
- Single File Components (`.vue`) with order: `<script setup>` → `<template>` → `<style>`
- One component per file
- `PascalCase.vue` file naming; use as `<PascalCase />` in templates
- Base/UI components prefix: `Base` or `App` (e.g., `BaseButton.vue`, `AppModal.vue`)
- Feature components in `features/` subdirectories

## Reactivity
- `ref()` for primitives; `reactive()` for objects (be aware of destructuring reactivity loss)
- `computed()` for derived state — never recompute in template expressions
- `watch()` for side effects triggered by state changes; `watchEffect()` for automatic dependency tracking
- Avoid deep watchers (`deep: true`) — redesign state shape instead
- `readonly()` to expose reactive state without allowing mutation

```ts
// Composable pattern
export function useCounter(initial = 0) {
  const count = ref(initial);
  const doubled = computed(() => count.value * 2);
  function increment() { count.value++ }
  return { count: readonly(count), doubled, increment };
}
```

## Composables
- File naming: `use<FeatureName>.ts` in `src/composables/`
- Composables encapsulate: reactive state + computed + watchers + lifecycle hooks
- Always return refs (not raw values) so consumers stay reactive
- Clean up resources in `onUnmounted()`: clear timers, remove listeners, abort requests

## Pinia (State Management)
- One store per feature domain: `useUserStore`, `useCartStore`
- Prefer **Setup Stores** (Composition API style) for consistency with `<script setup>`
- Never mutate state outside the store — use actions
- Use `storeToRefs()` to destructure reactive state without losing reactivity
- Pinia persists: `pinia-plugin-persistedstate` for local storage

```ts
export const useUserStore = defineStore('user', () => {
  const currentUser = ref<User | null>(null);
  const isAuthenticated = computed(() => currentUser.value !== null);
  async function fetchUser(id: string) {
    currentUser.value = await api.getUser(id);
  }
  return { currentUser: readonly(currentUser), isAuthenticated, fetchUser };
});
```

## Vue Router
- Always use `<RouterLink>` for navigation — never `<a href>` for internal routes
- Navigation guards for auth: `router.beforeEach()` or route-level `meta`
- Lazy-load route components: `component: () => import('./views/UserView.vue')`
- Typed routes with `unplugin-typed-router` or `vue-router/auto`
- Use `useRouter()` and `useRoute()` from Composition API — not `this.$router`

## Template Best Practices
- `v-for` always paired with `:key` — never use array index as key for dynamic lists
- `v-if` and `v-for` never on the same element — use `<template>` wrapper
- `v-model` with custom components: define `modelValue` prop + `update:modelValue` emit
- Avoid complex expressions in templates — extract to computed properties
- Event modifiers: `.prevent`, `.stop`, `.once` for cleaner event handling

## TypeScript Integration
- Enable Volar (Vue Language Features) in VS Code / Cursor
- `vue-tsc` for type checking in CI: `vue-tsc --noEmit`
- `defineProps<Props>()` provides full type safety
- Use `PropType<T>` only for runtime prop declarations (not recommended — use TypeScript generics)

## Performance
- `v-memo` for expensive list items with stable dependencies
- `defineAsyncComponent()` for code-split heavy components
- `<Suspense>` with async setup components
- `v-once` for static content that never changes
- Avoid large reactive objects — use `shallowRef()` / `shallowReactive()` for external data

## Testing (Vitest + Vue Test Utils)
```ts
import { mount } from '@vue/test-utils';
import { createTestingPinia } from '@pinia/testing';

it('displays user name', () => {
  const wrapper = mount(UserCard, {
    props: { userId: '1' },
    global: { plugins: [createTestingPinia({ initialState: { user: { name: 'Alice' } } })] }
  });
  expect(wrapper.text()).toContain('Alice');
});
```
- Test component behavior via rendered output — not internal implementation
- Mock Pinia stores with `createTestingPinia`
- Use `await nextTick()` after state changes before asserting DOM

## Nuxt 3 (if applicable)
- Auto-imported components, composables, and utils — no manual imports needed
- Use `useFetch()` / `useAsyncData()` for data fetching (SSR-aware)
- Server routes in `server/api/` — `defineEventHandler` with H3
- `useState()` for SSR-safe shared state (replaces `ref()` for cross-request state)
