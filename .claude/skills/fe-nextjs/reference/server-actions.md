# Server Action pattern (Next.js 16)

A Server Action is a POST endpoint anyone can call with any payload. The action is the transport
edge: authenticate → validate → call a use case (which authorizes) → update cache tags → return a
typed state. Business rules and data access live in the use case and its ports.

## Use case (application layer, framework-free)

```ts
// features/projects/application/create-project.ts
import type { ProjectRepository } from './ports';

export type CreateProjectError = 'FORBIDDEN' | 'NAME_TAKEN';
export type Result<T, E> = { ok: true; value: T } | { ok: false; error: E };

export interface Viewer {
  userId: string;
  canCreateProjects: boolean;
}

export function makeCreateProject(projects: ProjectRepository) {
  return async function createProject(
    viewer: Viewer,
    input: { name: string },
  ): Promise<Result<{ id: string }, CreateProjectError>> {
    if (!viewer.canCreateProjects) return { ok: false, error: 'FORBIDDEN' };
    if (await projects.existsByName(viewer.userId, input.name)) return { ok: false, error: 'NAME_TAKEN' };
    const project = await projects.create({ ownerId: viewer.userId, name: input.name });
    return { ok: true, value: { id: project.id } };
  };
}
```

## Composition root (server-only)

```ts
// src/composition.ts
import 'server-only';
import { makeCreateProject } from '@/features/projects/application/create-project';
import { PrismaProjectRepository } from '@/features/projects/adapters/prisma-project-repository';
import { db } from '@/shared/server/db';

export const createProject = makeCreateProject(new PrismaProjectRepository(db));
```

## Action (transport edge)

```ts
// features/projects/actions.ts
'use server';

import { updateTag } from 'next/cache';
import * as z from 'zod';
import { createProject } from '@/composition';
import { getViewer } from '@/features/auth/server/get-viewer';

const CreateProjectInput = z.object({
  name: z.string().trim().min(1, 'Name is required').max(100),
});

export type CreateProjectState =
  | { status: 'idle' }
  | { status: 'error'; message?: string; fieldErrors?: { name?: string[] } }
  | { status: 'success'; projectId: string };

const ERROR_MESSAGES = {
  FORBIDDEN: 'You do not have permission to create projects.',
  NAME_TAKEN: 'A project with this name already exists.',
} as const;

export async function createProjectAction(
  _previous: CreateProjectState,
  formData: FormData,
): Promise<CreateProjectState> {
  const viewer = await getViewer(); // reads the session cookie and verifies it; null if absent/invalid
  if (!viewer) return { status: 'error', message: 'Please sign in again.' };

  const parsed = CreateProjectInput.safeParse({ name: formData.get('name') });
  if (!parsed.success) {
    return { status: 'error', fieldErrors: z.flattenError(parsed.error).fieldErrors };
  }

  const result = await createProject(viewer, parsed.data);
  if (!result.ok) return { status: 'error', message: ERROR_MESSAGES[result.error] };

  updateTag(`projects:${viewer.userId}`);
  return { status: 'success', projectId: result.value.id };
}
```

Notes:

- Never accept `ownerId`, `role`, or prices from `formData`; derive them from the session and the
  database.
- Bound arguments (`action.bind(null, projectId)`) are also client-controlled — re-authorize them.
- Log unexpected failures in the adapter or `onRequestError`; do not return stack traces.
- For an immediate navigation after success, call `redirect()` after `updateTag()` (it throws, so
  put it last and outside `try`).

## Client form

```tsx
// features/projects/ui/create-project-form.tsx
'use client';

import { useActionState } from 'react';
import { createProjectAction, type CreateProjectState } from '../actions';

const INITIAL_STATE: CreateProjectState = { status: 'idle' };

export function CreateProjectForm() {
  const [state, formAction, isPending] = useActionState(createProjectAction, INITIAL_STATE);
  const nameError = state.status === 'error' ? state.fieldErrors?.name?.[0] : undefined;

  return (
    <form action={formAction}>
      <label htmlFor="project-name">Name</label>
      <input
        id="project-name"
        name="name"
        required
        aria-invalid={nameError ? true : undefined}
        aria-describedby={nameError ? 'project-name-error' : undefined}
      />
      {nameError && <p id="project-name-error">{nameError}</p>}
      {state.status === 'error' && state.message && <p role="alert">{state.message}</p>}
      <button type="submit" disabled={isPending}>Create project</button>
    </form>
  );
}
```

The form works before hydration (progressive enhancement) because the action is passed to
`<form action>`.

## Testing the action

```ts
import { beforeEach, expect, it, vi } from 'vitest';

vi.mock('next/cache', () => ({ updateTag: vi.fn() }));
vi.mock('@/features/auth/server/get-viewer', () => ({ getViewer: vi.fn() }));
vi.mock('@/composition', () => ({ createProject: vi.fn() }));

import { getViewer } from '@/features/auth/server/get-viewer';
import { createProjectAction } from './actions';

beforeEach(() => vi.clearAllMocks());

it('rejects unauthenticated callers', async () => {
  vi.mocked(getViewer).mockResolvedValue(null);
  const formData = new FormData();
  formData.set('name', 'Apollo');
  const state = await createProjectAction({ status: 'idle' }, formData);
  expect(state).toEqual({ status: 'error', message: 'Please sign in again.' });
});
```
