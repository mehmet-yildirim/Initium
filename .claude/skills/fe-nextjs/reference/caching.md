# Cache Components recipes (Next.js 16)

Requires `cacheComponents: true` in `next.config.ts`. Without it, `'use cache'` is unavailable and
the previous (implicit) caching model applies.

## Cached query with tags and a profile

```ts
// features/posts/queries.ts
import 'server-only';
import { cacheLife, cacheTag } from 'next/cache';
import { postRepository } from '@/composition';

export async function getPublishedPosts() {
  'use cache';
  cacheLife('hours');
  cacheTag('posts');
  return postRepository.listPublished(); // returns DTOs, not ORM records
}

export async function getPost(slug: string) {
  'use cache';
  cacheLife('days');
  cacheTag('posts', `post:${slug}`);
  return postRepository.findBySlug(slug);
}
```

- Arguments and captured variables are part of the cache key; they must be serializable.
- Built-in profiles include `'seconds'`, `'minutes'`, `'hours'`, `'days'`, `'weeks'`, `'max'`;
  define custom profiles under `cacheLife` in `next.config.ts` instead of inline magic numbers.
- Tags are case-sensitive and ≤ 256 characters. Use a consistent scheme: `entity`,
  `entity:id`, `entity:owner:userId`.

## Per-user data

Read request data outside the cached scope and pass it in:

```tsx
import { Suspense } from 'react';
import { getViewer } from '@/features/auth/server/get-viewer';
import { getProjectsForOwner } from '@/features/projects/queries';

async function ProjectList() {
  const viewer = await getViewer(); // dynamic: reads cookies
  if (!viewer) return <SignInPrompt />;
  const projects = await getProjectsForOwner(viewer.userId); // 'use cache' + cacheTag(`projects:${userId}`)
  return <ProjectTable projects={projects} />;
}

export default function Page() {
  return (
    <Suspense fallback={<ProjectTableSkeleton />}>
      <ProjectList />
    </Suspense>
  );
}
```

Authorization happens before the cached call; the cached function trusts its `userId` argument, so
never export it to Client Components.

## Invalidation matrix

| Situation | API |
|---|---|
| User just mutated data and must see it (Server Action) | `updateTag(tag)` |
| Content change where brief staleness is fine | `revalidateTag(tag, 'max')` |
| Webhook / Route Handler needs the entry gone now | `revalidateTag(tag, { expire: 0 })` |
| Uncached data elsewhere on the page changed (Server Action) | `refresh()` |
| A whole path must be re-rendered | `revalidatePath(path)` |

## Pitfalls

- `cookies()`, `headers()`, or `searchParams` inside `'use cache'` fail (even via a helper); on
  dynamic routes this can pass `next build` and fail at runtime — cover with an E2E test.
- A build that times out after ~50 s usually means a request-specific Promise was passed into a
  cached scope.
- The default cache is in-memory per instance; horizontally scaled or serverless deployments need
  `'use cache: remote'` with a platform/custom cache handler if hit rate matters.
- Nonce-based CSP forces dynamic rendering and cannot be combined with a prerendered static shell;
  choose SRI hashes for static routes or accept dynamic rendering.
