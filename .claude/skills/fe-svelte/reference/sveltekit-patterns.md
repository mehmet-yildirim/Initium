# SvelteKit 2 patterns: hooks, load, actions

## `app.d.ts`

```ts
// src/app.d.ts
declare global {
  namespace App {
    interface Locals {
      user: { id: string; canCreateProjects: boolean } | null;
      requestId: string;
    }
    interface Error {
      message: string;
      errorId?: string;
    }
  }
}

export {};
```

## `hooks.server.ts`

```ts
// src/hooks.server.ts
import type { Handle, HandleServerError } from '@sveltejs/kit';
import { sessionService } from '$lib/server/composition';
import { logger } from '$lib/server/logger';

const SESSION_COOKIE = 'session';

export const handle: Handle = async ({ event, resolve }) => {
  event.locals.requestId = crypto.randomUUID();
  const token = event.cookies.get(SESSION_COOKIE);
  event.locals.user = token ? await sessionService.verify(token) : null; // null on invalid/expired

  const response = await resolve(event);
  response.headers.set('X-Content-Type-Options', 'nosniff');
  response.headers.set('Referrer-Policy', 'strict-origin-when-cross-origin');
  response.headers.set('X-Request-Id', event.locals.requestId);
  return response;
};

export const handleError: HandleServerError = ({ error, event, status, message }) => {
  const errorId = event.locals.requestId ?? crypto.randomUUID();
  logger.error({ err: error, errorId, status, route: event.route.id }, 'unhandled server error');
  return { message: status === 404 ? message : 'Something went wrong', errorId };
};
```

- `sessionService` is an application service behind a port; its adapter talks to the session
  store. The hook never touches the database driver directly.
- Log `event.route.id`, not the full URL — query strings can carry tokens or PII.

## Load + action in `+page.server.ts`

```ts
// src/routes/projects/new/+page.server.ts
import { fail, redirect } from '@sveltejs/kit';
import * as z from 'zod';
import { createProject } from '$lib/server/composition';
import type { Actions, PageServerLoad } from './$types';

const CreateProjectInput = z.object({
  name: z.string().trim().min(1, 'Name is required').max(100),
});

const MESSAGES = {
  FORBIDDEN: 'You do not have permission to create projects.',
  NAME_TAKEN: 'A project with this name already exists.',
} as const;

export const load: PageServerLoad = async ({ locals, url }) => {
  if (!locals.user) redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);
  return {};
};

export const actions = {
  default: async ({ request, locals }) => {
    if (!locals.user) return fail(401, { message: 'Please sign in again.' });

    const formData = await request.formData();
    const parsed = CreateProjectInput.safeParse({ name: formData.get('name') });
    if (!parsed.success) {
      return fail(400, { name: String(formData.get('name') ?? ''), fieldErrors: z.flattenError(parsed.error).fieldErrors });
    }

    const result = await createProject(locals.user, parsed.data); // authorizes internally
    if (!result.ok) {
      const status = result.error === 'FORBIDDEN' ? 403 : 409;
      return fail(status, { name: parsed.data.name, message: MESSAGES[result.error] });
    }

    redirect(303, `/projects/${result.value.id}`);
  },
} satisfies Actions;
```

- Validate `redirectTo` against an allowlist of internal paths before redirecting to it later
  (open-redirect risk).
- Never read `ownerId`/`role` from the form; derive from `locals.user`.

## Page component

```svelte
<!-- src/routes/projects/new/+page.svelte -->
<script lang="ts">
  import { enhance } from '$app/forms';
  import type { PageProps } from './$types';

  let { form }: PageProps = $props();
  let submitting = $state(false);
</script>

<form
  method="POST"
  use:enhance={() => {
    submitting = true;
    return async ({ update }) => {
      await update();
      submitting = false;
    };
  }}
>
  <label for="project-name">Name</label>
  <input
    id="project-name"
    name="name"
    value={form?.name ?? ''}
    aria-invalid={form?.fieldErrors?.name ? 'true' : undefined}
    aria-describedby={form?.fieldErrors?.name ? 'project-name-error' : undefined}
  />
  {#if form?.fieldErrors?.name}
    <p id="project-name-error">{form.fieldErrors.name[0]}</p>
  {/if}
  {#if form?.message}
    <p role="alert">{form.message}</p>
  {/if}
  <button type="submit" disabled={submitting}>Create project</button>
</form>
```

The form works without JavaScript; `use:enhance` upgrades it to a fetch submission and keeps
focus/scroll behavior consistent.

## Testing an action (Node project)

```ts
import { describe, expect, it, vi } from 'vitest';

vi.mock('$lib/server/composition', () => ({ createProject: vi.fn() }));

import { actions } from './+page.server';

describe('create project action', () => {
  it('rejects unauthenticated requests', async () => {
    const request = new Request('http://localhost/projects/new', { method: 'POST', body: new FormData() });
    const result = await actions.default({ request, locals: { user: null, requestId: 'test' } } as never);
    expect(result).toMatchObject({ status: 401 });
  });
});
```

The `as never` cast is limited to the test: a full `RequestEvent` is not needed for this path.
