---
name: fe-nextjs
description: Next.js App Router standards — server/client components, data fetching, routing, deployment. Use when working in a Next.js App Router codebase.
globs:
  - "**/app/**"
  - "**/src/app/**"
  - "next.config.*"
  - "**/middleware.ts"
  - "**/layout.tsx"
  - "**/page.tsx"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# Next.js (App Router) Standards

Visual design quality (typography, color, layout, avoiding templated UI): `frontend-design` and `impeccable`; tokens: `design-tokens`.

## Server vs. Client Components

### Default to Server Components
- Every component in the `app/` directory is a Server Component by default
- Server Components: no interactivity, no browser APIs, no hooks — but can be async, fetch data directly
- Add `'use client'` only when you need: hooks, event handlers, browser APIs, real-time state

### Push `'use client'` to the leaves
```
Layout (Server) → Page (Server) → DataTable (Server) → SortButton ('use client')
```
- Never add `'use client'` to layout or page unless absolutely necessary
- Create small client "islands" for interactive parts; surround with server components

### Passing data from Server to Client
- Server → Client: pass serializable data as props (no functions, classes, or complex objects)
- Use `children` prop to "slot" server-rendered content into client components

## Data Fetching

### Server Components
```tsx
// Direct async/await — no useEffect, no React Query
async function UserPage({ params }: { params: { id: string } }) {
  const user = await db.user.findUnique({ where: { id: params.id } });
  if (!user) notFound();
  return <UserProfile user={user} />;
}
```

### Caching Strategy
- `fetch()` is extended with caching: `cache: 'force-cache'` (default, static), `cache: 'no-store'` (dynamic), `next: { revalidate: 60 }` (ISR)
- Use `unstable_cache()` for non-fetch data sources (DB queries, external SDKs)
- Tag caches for targeted revalidation: `unstable_cache(fn, ['users'], { tags: ['users'] })`
- `revalidatePath()` and `revalidateTag()` in Server Actions after mutations

### Client-Side Fetching (when required)
- TanStack Query for client-side server state — not raw `useEffect`
- Hydrate with server data using React Query's `dehydrate` / `HydrationBoundary`

## Routing

### File conventions
- `page.tsx` — route UI (publicly routable)
- `layout.tsx` — shared UI that wraps children; persists across navigations
- `loading.tsx` — Suspense fallback shown during page load
- `error.tsx` — error boundary (`'use client'`)
- `not-found.tsx` — 404 UI
- `route.ts` — API route handler
- `(group)/` — route group (no URL segment)
- `_private/` — private folder (not routable)
- `[param]/` — dynamic segment; `[[...param]]/` — optional catch-all

### Navigation
- `<Link href="...">` for all navigation — never `<a href>` for internal routes
- `useRouter().push()` only for programmatic navigation after events
- `redirect()` (from `next/navigation`) in Server Components and Server Actions

## Server Actions
- Preferred for all mutations — eliminates API route boilerplate
- Always validate input with Zod inside the action
- Use `'use server'` directive at function or file level
- Return structured response: `{ success: true, data } | { success: false, error }`
- Revalidate affected cache after mutations

```tsx
'use server';
export async function createUser(formData: FormData) {
  const input = createUserSchema.safeParse(Object.fromEntries(formData));
  if (!input.success) return { success: false, error: input.error.flatten() };
  const user = await db.user.create({ data: input.data });
  revalidateTag('users');
  return { success: true, data: user };
}
```

## Metadata & SEO
- Export `metadata` object or `generateMetadata` function from page/layout
- Always set `title`, `description`, and Open Graph tags on public pages
- Use `robots`, `sitemap`, `manifest` file conventions

## Middleware
- `middleware.ts` at project root — runs on Edge Runtime
- Use for: auth redirects, locale detection, A/B test assignment
- Keep middleware fast — no DB queries; read only from cookies/headers/tokens
- Specify `matcher` config to limit which routes trigger middleware

## Performance
- `next/image` for all images — handles optimization, lazy loading, `srcSet`
- `next/font` for all fonts — eliminates layout shift, self-hosts Google Fonts
- Streaming: use `<Suspense>` boundaries to stream slow parts independently
- Route Handlers vs. Server Actions: use Server Actions for form mutations; Route Handlers for webhooks and external consumers
- Partial Prerendering (PPR): opt-in per route for static shell + dynamic content

## Environment Variables
- `NEXT_PUBLIC_` prefix exposes vars to the browser — use sparingly
- Server-only vars: access in Server Components, Route Handlers, Server Actions only
- Validate all env vars at startup with Zod (`env.ts` pattern)
- Never access `process.env` in client components

## Error Handling
- `error.tsx`: catches rendering errors in a segment; must be `'use client'`
- `notFound()`: throws not-found error — caught by `not-found.tsx`
- Server Action errors: return error shape instead of throwing
- `global-error.tsx`: catches errors in root layout

## Deployment
- Vercel: zero-config for most features
- Self-hosted: `next build` → `next start`; Docker with `output: 'standalone'` in next.config
- Edge Runtime for latency-sensitive routes; Node.js runtime for DB-connected routes
- Set `NEXTAUTH_URL`, `NEXT_PUBLIC_APP_URL` for absolute URL requirements
