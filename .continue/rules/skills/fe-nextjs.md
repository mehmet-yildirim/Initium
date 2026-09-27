---
name: fe-nextjs
description: Next.js 16 App Router standards — Server/Client Components, async params and request APIs, Cache Components ('use cache', cacheLife, cacheTag, updateTag, revalidateTag(tag, profile)), Server Actions as authenticated public endpoints calling use cases, proxy.ts with CSP nonces, Turbopack, React Compiler, Zod 4 validation, and self-hosting. Use when writing, reviewing, upgrading, or configuring a Next.js App Router app, next.config, proxy.ts, route handlers, or Server Actions.
globs:
  - "**/next.config.*"
  - "**/proxy.ts"
  - "**/app/**/page.tsx"
  - "**/app/**/layout.tsx"
  - "**/app/**/route.ts"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# Next.js (App Router) Standards

Next.js-specific rules. Component, hook, and React 19 rules are in `fe-react`; language rules in
`lang-typescript`; E2E in `testing-e2e`; accessibility in `accessibility`.

## Baseline

- Next.js 16.3 (Active LTS; 15.5 is Maintenance LTS). Pin a patched release (≥ 16.3.6) and apply
  the monthly security releases announced on nextjs.org/blog.
- React 19.x as bundled by Next; Node.js ≥ 20.9 (prefer the current Node LTS); TypeScript ≥ 5.1.
- App Router only for new work. Turbopack is the default for `next dev` and `next build`; use
  `--webpack` only for an unported custom webpack config (with an issue to remove it).

```ts
// next.config.ts
import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  cacheComponents: true,
  reactCompiler: true, // requires babel-plugin-react-compiler as a devDependency
  output: 'standalone',
  images: { remotePatterns: [new URL('https://cdn.example.com/**')] },
};

export default nextConfig;
```

## Toolchain

- `next lint` was removed in 16: run ESLint (flat config with `@next/eslint-plugin-next`,
  `eslint-plugin-react-hooks`) or Biome directly; `next build` no longer lints.
- `tsc --noEmit` in CI; `npx @next/codemod@canary upgrade latest` for version upgrades.
- Turbopack config lives under top-level `turbopack` (not `experimental.turbopack`).
- Dependency audit in CI; Next.js security advisories are frequent — automate patch bumps.

## Structure

```
src/
├── app/                        # Routing only: page/layout/loading/error/route files, thin
│   └── (dashboard)/projects/[id]/page.tsx
├── features/projects/
│   ├── domain/                 # Entities, invariants — framework-free
│   ├── application/            # Use cases + ports (ProjectRepository, Clock, Mailer)
│   ├── adapters/               # DB/ORM repositories, HTTP clients, SDK wrappers ('server-only')
│   ├── actions.ts              # 'use server' — authn, validate, call use case, revalidate
│   ├── queries.ts              # Cached/authorized reads used by Server Components
│   └── ui/                     # Client and Server components for this feature
└── composition.ts              # Wires adapters to ports ('server-only')
```

- `page.tsx`, `layout.tsx`, `route.ts`, `error.tsx` etc. use **default exports** (framework-
  mandated) and stay thin: parse params, call a query/use case, render.
- Server-only modules start with `import 'server-only'` so a client import fails the build.
- Never call the ORM or a vendor SDK from a page, action, or component — go through a use case or
  query that depends on a port.

## Server and Client Components

- Server Components by default. Add `'use client'` only for state, effects, event handlers, or
  browser APIs, and push it to leaf components.
- Pass only serializable props to Client Components; slot server content via `children`.
- Do not pass full records to the client; select the fields the UI needs (DTOs). React's taint APIs
  (`experimental.taint`) can back this up for secrets.

## Routing and request APIs

- `params` and `searchParams` are Promises; `cookies()`, `headers()`, `draftMode()` are async.

```tsx
// app/(dashboard)/projects/[id]/page.tsx
import { notFound } from 'next/navigation';
import { getProjectForViewer } from '@/features/projects/queries';

export default async function ProjectPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const project = await getProjectForViewer(id); // verifies session + ownership internally
  if (!project) notFound();
  return <ProjectDetail project={project} />;
}
```

- Validate `params`/`searchParams` with Zod before use; they are user input.
- Parallel route slots require an explicit `default.tsx`.
- `<Link>` for internal navigation; `redirect()`/`notFound()` from `next/navigation` on the server.

## Caching (Cache Components)

- With `cacheComponents: true`, everything is dynamic by default; opt in to caching with
  `'use cache'` on a function, component, or file, plus `cacheLife(profile)` and `cacheTag(tag)`
  from `next/cache`. Partial Prerendering is part of this model (no per-route PPR flag).
- Never read `cookies()`, `headers()`, or `searchParams` inside a cached scope — read them outside
  and pass values as arguments (they become part of the cache key). Per-user data uses
  `'use cache: private'` only when refactoring is impossible.
- Wrap dynamic regions in `<Suspense>` so the static shell streams immediately.
- After mutations: `updateTag(tag)` in Server Actions for read-your-writes;
  `revalidateTag(tag, 'max')` for stale-while-revalidate (Route Handlers/webhooks use
  `revalidateTag(tag, { expire: 0 })` when data must expire now). The single-argument
  `revalidateTag(tag)` is deprecated. `refresh()` re-renders uncached data only.
- Route segment `dynamic`, `revalidate`, and `fetchCache` exports are removed under Cache
  Components; `unstable_cache` is legacy — migrate to `'use cache'`.

Read `reference/caching.md` when designing cache keys, tags, or profiles.

## Server Actions

- **Every Server Action is a public HTTP endpoint.** Inside each action: authenticate, validate
  input with Zod, authorize (in the use case), call the use case, then update tags. Do not rely on
  `proxy.ts`, layouts, or hidden UI for protection.
- `'use server'` files export only async functions (types are fine); keep schemas unexported.
- Return a typed result for expected failures; map Zod errors with `z.flattenError(error)`
  (Zod 4 — `error.flatten()` is deprecated). Let unexpected errors throw to `error.tsx`.
- Use Server Actions for UI mutations; Route Handlers for webhooks, external consumers, and
  non-React clients (validate signatures and bodies there too).

Read `reference/server-actions.md` for the full action + use case + `useActionState` pattern.

## Proxy (formerly Middleware)

- `middleware.ts` is deprecated: use `proxy.ts` exporting `proxy` (codemod:
  `npx @next/codemod@canary middleware-to-proxy .`). Proxy runs on Node.js; `runtime` cannot be
  configured there.
- Use it for redirects, rewrites, locale detection, and CSP nonces. Keep it fast: no database
  calls; read cookies/headers only. Scope it with a static `matcher`.
- It is an optimization, not an authorization layer — a matcher change can silently drop coverage.

Read `reference/proxy-csp.md` when adding CSP nonces or security headers.

## Runtime and deployment

- Node.js runtime everywhere. `export const runtime = 'edge'` is deprecated — do not add it; remove
  it when touching a route.
- Self-hosting: `output: 'standalone'` in a multi-stage Docker image (`devops-docker`); set
  `deploymentId` when running multiple instances; configure a shared cache handler if you scale
  horizontally.
- `images.remotePatterns` (not the deprecated `images.domains`); local images with query strings
  need `images.localPatterns`.

## Environment and auth

- Parse `process.env` once in a `server-only` `env.ts` with Zod; fail startup on invalid config.
- `NEXT_PUBLIC_*` values are inlined into the client bundle — never put secrets there.
- Auth.js v5 uses `AUTH_*` variables (`AUTH_SECRET`, `AUTH_URL` only when the host cannot be
  inferred, `AUTH_TRUST_HOST` behind a proxy); `NEXTAUTH_*` is legacy. Auth.js is now maintained by
  the Better Auth team, which recommends Better Auth for new projects — follow the team's ADR.
- Verify the session in a data-access layer used by every query and action, not only in layouts.

## Errors

- Expected failures: typed results from use cases → action state or `notFound()`.
- Unexpected failures: `error.tsx` per segment (Client Component, offers retry) and
  `global-error.tsx` for the root layout. Never render raw error messages in production.
- Report server errors with `onRequestError` in `instrumentation.ts`.

## Security

- CSP with per-request nonces from `proxy.ts` (forces dynamic rendering) or the experimental SRI
  hash mode for static pages; plus `X-Content-Type-Options`, `Referrer-Policy`,
  `Strict-Transport-Security`, and `frame-ancestors`.
- Server Action and Route Handler inputs validated with Zod; outputs are DTOs without secrets.
- Server Actions reject cross-origin `Origin` hosts; add entries to
  `experimental.serverActions.allowedOrigins` only for a proxy that rewrites the host, and keep
  `bodySizeLimit` at the 1 MB default unless an upload needs more.
- Watch the Next.js security advisories and patch within your SLA.

## Performance

- `next/image` with explicit sizes; `next/font` for fonts; `next/script` with a strategy.
- Stream with `<Suspense>`; keep Client Component bundles small; measure Core Web Vitals
  (LCP ≤ 2.5 s, INP ≤ 200 ms, CLS ≤ 0.1 at p75) via `useReportWebVitals` or `web-vitals`.

## Observability

- `instrumentation.ts` registers OpenTelemetry (`@vercel/otel` or the Node SDK) and
  `onRequestError`; `instrumentation-client.ts` initializes client telemetry.
- Structured server logs via a logger (pino) with request/trace ids; no `console.log`.

## Testing

- Unit-test use cases and queries without Next.js; test Client Components per `fe-react`.
- Test Server Actions as functions with the session and ports faked — include the unauthenticated
  and forbidden cases.
- Playwright against `next build && next start` for routing, caching, and auth flows
  (`testing-e2e`); axe checks per `accessibility`.

_Versions verified September 2026._
