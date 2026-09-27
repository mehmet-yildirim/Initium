# React 19 Actions, optimistic updates, and `use()`

Framework-agnostic examples (Vite SPA or any React 19.3 app). For Next.js Server Actions, see
`fe-nextjs/reference/server-actions.md`.

## Form with `useActionState` calling a use case

The action calls an application-layer use case through its port; it never calls `fetch` itself.

```tsx
// features/projects/ui/CreateProjectForm.tsx
import { useActionState } from 'react';
import * as z from 'zod';
import { useProjectService } from './useProjectService';

const CreateProjectInput = z.object({ name: z.string().trim().min(1, 'Name is required').max(100) });

type FormState =
  | { status: 'idle' }
  | { status: 'error'; fieldErrors?: { name?: string[] }; message?: string }
  | { status: 'success'; projectId: string };

const INITIAL_STATE: FormState = { status: 'idle' };

export function CreateProjectForm() {
  const projects = useProjectService();

  const [state, formAction, isPending] = useActionState(
    async (_previous: FormState, formData: FormData): Promise<FormState> => {
      const parsed = CreateProjectInput.safeParse({ name: formData.get('name') });
      if (!parsed.success) {
        return { status: 'error', fieldErrors: z.flattenError(parsed.error).fieldErrors };
      }
      const result = await projects.create(parsed.data);
      if (!result.ok) return { status: 'error', message: messageFor(result.error) };
      return { status: 'success', projectId: result.value.id };
    },
    INITIAL_STATE,
  );

  const nameError = state.status === 'error' ? state.fieldErrors?.name?.[0] : undefined;

  return (
    <form action={formAction} noValidate>
      <label htmlFor="project-name">Name</label>
      <input
        id="project-name"
        name="name"
        aria-invalid={nameError ? true : undefined}
        aria-describedby={nameError ? 'project-name-error' : undefined}
      />
      {nameError && <p id="project-name-error">{nameError}</p>}
      {state.status === 'error' && state.message && <p role="alert">{state.message}</p>}
      <button type="submit" disabled={isPending}>
        {isPending ? 'Creating…' : 'Create project'}
      </button>
    </form>
  );
}
```

- `messageFor` maps domain error codes (`'NAME_TAKEN'`, `'FORBIDDEN'`) to user-facing strings.
- React resets uncontrolled fields when a `<form action>` function completes; return the submitted
  values in the error state and feed them back as `defaultValue` so input survives a validation
  error.

## Pending state in a nested button

```tsx
import { useFormStatus } from 'react-dom';

export function SubmitButton({ children }: { children: React.ReactNode }) {
  const { pending } = useFormStatus();
  return <button type="submit" disabled={pending}>{children}</button>;
}
```

`useFormStatus` only reads the status of the parent `<form>`; it must render inside it.

## Optimistic update

```tsx
import { useOptimistic, startTransition } from 'react';

export function TodoList({ todos, onToggle }: { todos: Todo[]; onToggle: (id: string) => Promise<void> }) {
  const [optimisticTodos, setOptimistic] = useOptimistic(
    todos,
    (current, toggledId: string) =>
      current.map((todo) => (todo.id === toggledId ? { ...todo, done: !todo.done } : todo)),
  );

  function toggle(id: string) {
    startTransition(async () => {
      setOptimistic(id);
      await onToggle(id); // on rejection the optimistic state reverts to `todos`
    });
  }

  return (
    <ul>
      {optimisticTodos.map((todo) => (
        <li key={todo.id}>
          <label>
            <input type="checkbox" checked={todo.done} onChange={() => toggle(todo.id)} />
            {todo.title}
          </label>
        </li>
      ))}
    </ul>
  );
}
```

Surface the failure (toast/inline error) in `onToggle`'s caller; the revert alone is not feedback.

## Reading a promise with `use()`

Create the promise outside render (router loader, parent Server Component, or a cache) and pass it
down. Creating it in the component body refetches on every render.

```tsx
import { Suspense, use } from 'react';

function ProjectHeader({ projectPromise }: { projectPromise: Promise<Project> }) {
  const project = use(projectPromise);
  return <h1>{project.name}</h1>;
}

export function ProjectPage({ projectPromise }: { projectPromise: Promise<Project> }) {
  return (
    <ErrorBoundary FallbackComponent={ProjectLoadError}>
      <Suspense fallback={<HeaderSkeleton />}>
        <ProjectHeader projectPromise={projectPromise} />
      </Suspense>
    </ErrorBoundary>
  );
}
```

`ErrorBoundary` is from `react-error-boundary`; a rejected promise surfaces there.
