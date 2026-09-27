---
name: fe-react
description: React 19.3 standards — function components, React Compiler 1.0 (no manual memoization), Actions with useActionState/useOptimistic/use(), ref as a prop, TanStack Query for server state, React Hook Form + Zod 4, error boundaries, XSS-safe rendering, Core Web Vitals, and Vitest + Testing Library. Use when writing, reviewing, or refactoring React components, hooks, forms, or client state in any React codebase.
paths:
  - "**/*.tsx"
  - "**/*.jsx"
---

# React Standards

Framework-agnostic React rules. Next.js specifics are in `fe-nextjs`, React Native in
`mobile-reactnative`, language rules in `lang-typescript`. Visual design: `frontend-design`,
`impeccable`, `design-tokens`. E2E: `testing-e2e`. Accessibility depth: `accessibility`.

## Baseline

- React 19.3 (`react`, `react-dom`); TypeScript strict; function components only — no class
  components except an error boundary you cannot get from a library.
- React Compiler 1.0 enabled (Next.js `reactCompiler: true`; Vite/other bundlers via
  `babel-plugin-react-compiler` per react.dev installation docs).
- Vitest + React Testing Library for unit/component tests; Playwright for E2E.

## Toolchain

- ESLint flat config: `typescript-eslint`, `eslint-plugin-react-hooks`
  (`reactHooks.configs.flat.recommended` — includes the React Compiler rules),
  `eslint-plugin-jsx-a11y`. Treat hooks and compiler diagnostics as errors in CI.
- Format with Prettier or Biome; type-check with `tsc --noEmit` in CI.
- `npm audit` / `pnpm audit` in CI; dependency updates via Renovate/Dependabot
  (`security-supply-chain`).

## Structure

```
src/
├── app/                     # Composition root: providers, router, adapter wiring
├── features/
│   └── projects/
│       ├── domain/          # Types, invariants, pure functions — no React, no fetch
│       ├── application/     # Use cases + ports (ProjectRepository interface)
│       ├── adapters/        # HTTP/SDK clients implementing ports; DTO ↔ domain mapping
│       └── ui/              # Components + hooks (useProjects) — call ports, never fetch()
├── shared/ui/               # Design-system primitives
└── shared/lib/              # Logger, query client, env parsing
```

- One component per file; file named after the component (`ProjectCard.tsx`). Aim < 150 lines.
- Named exports only, **except framework-mandated default exports** (Next.js `page`/`layout`/
  `error`, `React.lazy` targets, Storybook meta).
- Vendor SDKs (analytics, auth, payments) live behind an adapter in `adapters/`; components import
  the port or a hook, never the SDK.
- Validate every API response at the adapter boundary with Zod before it reaches domain code.

## Components and props

- Props as `type`/`interface`; required first. `children: React.ReactNode`. No `React.FC`.
- Composition over boolean-prop configuration (`<Card><Card.Header/></Card>`, not
  `<Card showHeader compact bordered/>`).
- `ref` is a regular prop in React 19 — do not use `forwardRef` in new code:

```tsx
type InputProps = React.ComponentProps<'input'> & { label: string };

export function TextInput({ label, id, ref, ...rest }: InputProps) {
  const fallbackId = useId();
  const inputId = id ?? fallbackId;
  return (
    <>
      <label htmlFor={inputId}>{label}</label>
      <input id={inputId} ref={ref} {...rest} />
    </>
  );
}
```

- Render `<Context value={...}>` directly (React 19); `Context.Provider` is legacy.
- Stable `key` from data identity; never array index for reorderable/dynamic lists.

## State, effects, and memoization

- `useState` for local UI state, `useReducer` for multi-field transitions. Derive values during
  render — do not mirror props/state into state or compute them in effects.
- **React Compiler handles memoization.** Do not add `useMemo`, `useCallback`, or `memo` by
  default. Use them only as documented escape hatches (e.g., a value used as an effect dependency
  the compiler cannot stabilize), with a comment explaining why. `"use no memo"` only as a
  temporary opt-out with a linked issue.
- `useEffect` only to synchronize with external systems (subscriptions, DOM APIs, timers); always
  return cleanup. No data fetching, no event-handler logic, no derived state in effects.
- `useEffectEvent` (19.2) for non-reactive logic read inside an effect instead of suppressing
  `exhaustive-deps`.
- Never suppress `react-hooks/*` lint rules; fix the code.

## React 19 Actions and async

- Form mutations: `<form action={fn}>` + `useActionState` for result/pending state; `useFormStatus`
  inside child submit buttons; `useOptimistic` for instant feedback that reverts on failure.
- `use(promise)` reads a promise created outside render (by a loader, Server Component, or cache) —
  never create the promise during render. `use(Context)` may be called conditionally.
- `startTransition`/`useTransition` for non-urgent updates; `<Suspense>` boundaries around
  independently loading regions.
- React 19.2/19.3 additions: `<Activity mode="hidden">` to keep hidden UI state without effects
  running; `<ViewTransition>` (stable in 19.3) for animated transitions; Fragment refs; and
  `use(browser())` from `react-dom` to opt a component out of SSR instead of `typeof window` or
  "mounted" state hacks.

Read `reference/actions-and-forms.md` when implementing a form, optimistic update, or `use()`.

## Server state and global state

- TanStack Query for server state (queries call a port/use case, not `fetch` inline); invalidate
  affected keys on mutation success. No `useEffect` + `useState` fetching.
- Global UI state: Zustand, or Context for rarely changing values. Redux Toolkit only where already
  adopted. URL state (filters, pagination) in search params.

## Forms

- Simple forms: native `<form action>` + Actions + Zod validation (server- or client-side).
- Complex client forms (dynamic field arrays, heavy cross-field validation): React Hook Form +
  `@hookform/resolvers/zod`.
- Always validate again on the server; client validation is UX only. Show inline field errors and a
  form-level error; link errors with `aria-describedby`.

## Errors

- Adapters return typed results (`{ ok: true, value } | { ok: false, error }`) with domain error
  codes; UI maps codes to messages. Never swallow — log unexpected errors via the logger.
- Wrap route-level and widget-level regions in error boundaries (`react-error-boundary`) with a
  retry action; boundaries do not catch event-handler or async errors — handle those explicitly.
- Wire `createRoot(el, { onUncaughtError, onCaughtError, onRecoverableError })` to the logger.

## Security

- Rely on JSX escaping. `dangerouslySetInnerHTML` only with sanitized HTML (DOMPurify) and a code
  comment naming the source; never with raw user or CMS input.
- Validate user-supplied URLs before rendering `href`/`src`: allow `https:`/`http:`/`mailto:` only;
  never render `javascript:` URLs.
- Do not store access/refresh tokens in `localStorage`/`sessionStorage`; prefer HttpOnly `Secure`
  `SameSite` cookies via a backend-for-frontend.
- No secrets in client bundles — anything in `import.meta.env.VITE_*` / `NEXT_PUBLIC_*` is public.
- Ship a strict CSP (nonces or hashes); React 19.3 supports Trusted Types.

## Performance

- Targets (p75, field data): LCP ≤ 2.5 s, INP ≤ 200 ms, CLS ≤ 0.1. Measure with the `web-vitals`
  library and report to your RUM/telemetry backend.
- Code-split routes and heavy widgets with `React.lazy` + `<Suspense>`.
- Images: explicit `width`/`height`, `loading="lazy"` below the fold, responsive `srcSet`.
- Virtualize long lists (TanStack Virtual). Profile with React Performance Tracks (Chrome DevTools)
  and the React DevTools Profiler before optimizing by hand.

## Internationalization

- No hard-coded user-facing strings in components; use an ICU-message library (`react-intl` or
  `react-i18next`). Format dates, numbers, and currency with `Intl`. Support RTL via logical CSS
  properties.

## Observability

- A `logger` module in `shared/lib` wraps the telemetry SDK (OpenTelemetry web SDK, Sentry, etc.)
  behind a port. No `console.log` in committed code (`no-console` lint rule).
- Attach a session/trace id to API requests so frontend errors correlate with backend traces. Never
  log tokens, form values containing PII, or full URLs with sensitive query params.

## Accessibility

- Semantic elements first (`<button>` for actions, `<a>` for navigation); every input labelled;
  icon-only buttons get `aria-label`; manage focus on dialog open/close and route change.
- `eslint-plugin-jsx-a11y` in CI; automated axe checks per the `accessibility` skill (WCAG 2.2 AA).

## Testing

- Vitest + React Testing Library: test behavior through roles/labels, `userEvent` over
  `fireEvent`, MSW for network mocks. No snapshot tests for logic.
- Unit-test domain and application layers without React; test hooks through a component or
  `renderHook`.
- Component-level axe checks and Playwright E2E/visual tests: see `accessibility` and
  `testing-e2e`.

```tsx
it('shows the server error when sign-in fails', async () => {
  server.use(http.post('/api/session', () => HttpResponse.json({ code: 'INVALID_CREDENTIALS' }, { status: 401 })));
  render(<SignInForm />);
  await userEvent.type(screen.getByLabelText('Email'), 'user@example.com');
  await userEvent.type(screen.getByLabelText('Password'), 'wrong-password');
  await userEvent.click(screen.getByRole('button', { name: 'Sign in' }));
  expect(await screen.findByRole('alert')).toHaveTextContent('Email or password is incorrect');
});
```

_Versions verified September 2026._
