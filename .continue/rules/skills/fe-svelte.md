---
name: fe-svelte
description: Svelte 5 and SvelteKit 2 standards — runes ($state, $derived, $effect, $props, $bindable), snippets, load functions, form actions with use:enhance, hooks (handle, handleError), CSRF and CSP config, $env/$lib/server boundaries, adapters, svelte-check, and Vitest browser mode + Playwright; tracks the SvelteKit 3 release candidate. Use when writing, reviewing, or configuring Svelte components, SvelteKit routes, hooks, or svelte.config.
globs:
  - "**/*.svelte"
  - "**/svelte.config.*"
  - "**/+page*.ts"
  - "**/+layout*.ts"
  - "**/+server.ts"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# Svelte 5 and SvelteKit Standards

Svelte/SvelteKit rules. Language rules are in `lang-typescript`; E2E in `testing-e2e`;
accessibility depth in `accessibility`; visual design in `frontend-design`, `impeccable`,
`design-tokens`.

## Baseline

- Svelte 5 (5.57+), runes mode only — no `export let`, `$:`, or `on:event` in new code.
- SvelteKit 2 (2.70+) for production. SvelteKit 3 is a release candidate (Aug 2026): config moves
  to `vite.config.ts`, `$lib` becomes `#lib`, Vite 8 is required, and errors always flow through
  `handleError`. Trial it on a branch with `npx sv@next migrate sveltekit-3`; do not ship RC builds.
- Scaffold and add tooling with the `sv` CLI (`npx sv create`, `npx sv add vitest playwright`).
- TypeScript everywhere (`<script lang="ts">`).

## Toolchain

- `svelte-check --fail-on-warnings` in CI (types + compiler warnings, including `a11y_*`).
- ESLint flat config with `eslint-plugin-svelte` and `typescript-eslint`; Prettier with
  `prettier-plugin-svelte`.
- `npm audit` / `pnpm audit` in CI; Renovate/Dependabot per `security-supply-chain`.

## Structure

```
src/
├── routes/                         # Routing only: +page.svelte, +page.server.ts, +server.ts
│   └── projects/[id]/
├── lib/
│   ├── features/projects/
│   │   ├── domain/                 # Types, pure rules
│   │   ├── application/            # Use cases + ports
│   │   └── components/             # Feature components
│   ├── server/                     # Server-only: adapters (DB, SDKs), composition root, logger
│   └── ui/                         # Shared primitives
├── hooks.server.ts                 # handle, handleError, handleFetch
└── app.d.ts                        # App.Locals, App.Error, App.PageData types
```

- Everything under `$lib/server` (and `*.server.ts`) is unimportable from client code — keep DB
  clients, secrets, and vendor SDKs there, behind ports wired in `$lib/server/composition.ts`.
- `+page.server.ts`/`+layout.server.ts` for anything needing secrets, the database, or cookies;
  universal `+page.ts` only for public API calls safe to run in the browser.
- Route files stay thin: authenticate, validate, call a use case, return data.

## Components and runes

```svelte
<script lang="ts">
  import type { Snippet } from 'svelte';

  let { label, value = $bindable(''), maxLength = 100, hint }: {
    label: string;
    value?: string;
    maxLength?: number;
    hint?: Snippet;
  } = $props();

  const id = $props.id();
  const remaining = $derived(maxLength - value.length);
</script>

<label for={id}>{label}</label>
<input {id} bind:value maxlength={maxLength} aria-describedby="{id}-hint" />
<p id="{id}-hint">{#if hint}{@render hint()}{:else}{remaining} characters left{/if}</p>
```

- `$state` for mutable state (deeply reactive proxies); `$state.raw` for large data you replace
  wholesale; `$derived`/`$derived.by` for computed values — never compute in `$effect`.
- `$effect` only to sync with external systems (DOM APIs, subscriptions); return a cleanup.
  `$effect.pre` for pre-DOM-update work. No state writes that could loop.
- `$bindable` only for genuine two-way props; prefer callback props (`onchange`) otherwise.
- Event attributes (`onclick={handler}`), snippets and `{@render}` instead of slots, callback props
  instead of `createEventDispatcher`.
- Shared reactive logic in `.svelte.ts` modules exporting functions/classes that use runes.
- Avoid module-level mutable state in anything that runs on the server — it leaks between
  requests; use `event.locals`, load data, or context (`createContext`/`setContext`).

## Data loading

- Server `load` returns only what the page renders (DTOs, no secrets); it runs on every request
  unless the page is prerendered. Stream slow data by returning un-awaited promises and rendering
  them with `{#await}`.
- Use `depends()`/`invalidate()` for targeted reloads; `invalidateAll()` sparingly.
- Read page state from `$app/state` (`page`, `navigating`); `$app/stores` is legacy.
- Remote functions (`query`, `form`, `command`) are still experimental — adopt only via an ADR.

## Form actions

- Mutations go through form actions in `+page.server.ts` (progressively enhanced with
  `use:enhance`). Each action: check `locals.user`, validate `request.formData()` with Zod,
  call a use case, `return fail(status, data)` for expected failures, `redirect(303, ...)` on
  success. In SvelteKit 2, `error()` and `redirect()` throw on their own — do not wrap them in
  `try/catch`.
- `+server.ts` endpoints for webhooks and non-HTML clients: validate body and signatures,
  authenticate, return `json()`.

Read `reference/sveltekit-patterns.md` for `hooks.server.ts`, a full load + action, and
`app.d.ts` typing.

## Hooks

- `handle` resolves the session once per request into `event.locals.user` and sets security
  headers; do not rely on a parent `+layout.server.ts` to protect child routes — layouts and pages
  load in parallel and actions/endpoints bypass layout loads. Check authorization in each server
  load, action, and endpoint (or centrally in `handle` by route id).
- `handleError` logs the error with an id and returns a safe `App.Error` (`{ message, errorId }`)
  — never the raw error.
- `handleFetch` to add credentials or rewrite URLs for server-side `fetch` to internal services.

## Security

- CSRF: SvelteKit checks `Origin` for form submissions; list exceptions in
  `kit.csrf.trustedOrigins` (full origins only). `checkOrigin` is deprecated — never disable it.
- CSP: `kit.csp` with `mode: 'auto'` (nonces for dynamic pages, hashes for prerendered) and strict
  `directives`; start with `reportOnly` plus `report-uri`/`report-to`. Svelte transitions need
  `style-src 'unsafe-inline'` or no `style-src` directive — prefer CSS animations.
- `{@html}` only with DOMPurify-sanitized content and a comment naming the source.
- Env: `$env/static/private` / `$env/dynamic/private` only in server modules; `PUBLIC_*` values
  are shipped to the browser.
- Cookies: `event.cookies.set(name, value, { path: '/', httpOnly: true, secure: true, sameSite: 'lax' })`;
  never put tokens in `localStorage`.

## Deployment

- Pick the adapter explicitly: `@sveltejs/adapter-node` (containers/VMs), `adapter-static`
  (fully prerendered), `adapter-vercel`, `adapter-netlify`, `adapter-cloudflare`. Avoid
  `adapter-auto` in production builds.
- adapter-node behind a proxy: set `ORIGIN` (or `PROTOCOL_HEADER`/`HOST_HEADER`) so CSRF and URLs
  are correct; set `BODY_SIZE_LIMIT` deliberately.

## Errors

- Expected failures: typed use-case results → `fail()` or `error(404)`.
- Unexpected failures: let them throw to `handleError` and `+error.svelte`; use
  `<svelte:boundary>` for client-side render errors in widgets.

## Observability

- Server: structured logger (pino) in `$lib/server/logger.ts`, request id added in `handle`; no
  `console.log`. SvelteKit's OpenTelemetry tracing (`instrumentation.server.ts`) is experimental —
  enable deliberately.
- Client: a logger module forwarding to your telemetry SDK; never log tokens or PII.

## Performance

- Prerender static routes (`export const prerender = true`); set `ssr`/`csr` per route only with a
  reason. Use `data-sveltekit-preload-data` defaults for links.
- Track Core Web Vitals (LCP ≤ 2.5 s, INP ≤ 200 ms, CLS ≤ 0.1 at p75).

## Accessibility

- Treat Svelte compiler `a11y_*` warnings as errors (via `svelte-check --fail-on-warnings`); do
  not silence them with `svelte-ignore` without a comment explaining why.
- Semantic elements, labelled inputs (`$props.id()` for ids), focus management after navigation
  and in dialogs; axe checks per `accessibility`.

## Testing

- Vitest with separate projects: browser mode (`vitest-browser-svelte`) for `*.svelte.test.ts`
  component tests, Node for server code (`load`, actions, use cases with fake ports).
- Mock `$app/*` modules with `vi.mock` in component tests; test actions by calling them with a
  constructed `RequestEvent`-like object including unauthenticated and invalid-input cases.
- Playwright E2E against `vite build && vite preview` (`testing-e2e`).

_Versions verified September 2026._
