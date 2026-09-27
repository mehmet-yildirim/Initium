---
name: fe-react
description: React development standards — hooks, components, state management, performance, testing. Use when writing or reviewing React components, hooks, or client state.
paths:
  - "**/*.tsx"
  - "**/*.jsx"
  - "**/src/components/**"
  - "**/src/hooks/**"
  - "**/src/pages/**"
---

# React Development Standards

Visual design quality (typography, color, layout, avoiding templated UI): `frontend-design` and `impeccable`; tokens: `design-tokens`.

## Component Design Principles
- **One component, one concern** — if it needs "and" to describe it, split it
- Components should be small: aim for < 150 lines; split if larger
- Prefer functional components — never class components in new code
- Export components as named exports, not default exports
- Co-locate related files: `UserCard/UserCard.tsx`, `UserCard/UserCard.test.tsx`, `UserCard/index.ts`

## Component Patterns

### Prefer composition over configuration
```tsx
// Preferred: composable
<Card>
  <Card.Header>Title</Card.Header>
  <Card.Body>{children}</Card.Body>
</Card>

// Avoid: too many boolean props
<Card showHeader title="Title" compact bordered />
```

### Separate UI from logic with custom hooks
```tsx
// Hook handles all logic
function useUserProfile(userId: string) {
  const { data: user, isLoading, error } = useQuery({ queryKey: ['user', userId], queryFn: ... });
  const { mutate: updateUser } = useMutation({ ... });
  return { user, isLoading, error, updateUser };
}

// Component is pure UI
function UserProfile({ userId }: { userId: string }) {
  const { user, isLoading, error, updateUser } = useUserProfile(userId);
  if (isLoading) return <Skeleton />;
  if (error) return <ErrorMessage error={error} />;
  return <UserForm user={user} onSubmit={updateUser} />;
}
```

## Props
- Always define props as a TypeScript `interface` or `type`
- Required props first, optional after
- `children: React.ReactNode` (not `JSX.Element`)
- Event handlers typed as `React.MouseEventHandler<HTMLButtonElement>` etc., not bare `() => void`
- Never use `React.FC` — write `function Component(props: Props)` directly

## Hooks

### Rules
- Only call hooks at the top level — no conditionals, loops, early returns before hooks
- Custom hook names must start with `use`
- Extract complex hook logic into smaller hooks

### State
- `useState` for simple local UI state
- `useReducer` for complex state transitions with multiple sub-values
- No state duplication — derive values from existing state via `useMemo`
- Lift state to the nearest common ancestor — not higher

### Effects
- `useEffect` for synchronization with external systems only
- Not for: data fetching (use React Query/SWR), event handlers, computed values
- Always return cleanup function for subscriptions, timers, observers
- List all reactive values in the dependency array — no suppression comments

## Data Fetching
- **React Query (TanStack Query)** for all server state — not `useEffect` + `useState`
- **SWR** as alternative; **never** fetch in `useEffect` for data that lives on the server
- Separate server state (React Query) from UI state (`useState`)
- `useMutation` for all mutations; invalidate related queries on success

## State Management
- Local UI state: `useState` / `useReducer`
- Server state: React Query (not Redux for this)
- Global UI state (theme, auth): Zustand or React Context (for rarely-changing values only)
- URL state: `useSearchParams` for filterable/shareable UI state
- Avoid Redux unless the project already uses it and scope justifies it

## Performance
- Memoize expensive computations with `useMemo` — not as default, only when profiled
- `useCallback` for callbacks passed to memoized child components
- `React.memo` for components that re-render too often with unchanged props
- Code-split routes with `React.lazy` + `<Suspense>`
- Images: use `loading="lazy"` and appropriate `srcSet`
- Lists: use `key` prop correctly — never use array index as key for dynamic lists

## Accessibility (a11y)
- All interactive elements must be keyboard accessible
- Semantic HTML: `<button>` for actions, `<a>` for navigation
- `aria-label` on icon-only buttons
- Manage focus on modal open/close
- Color is never the sole differentiator
- Test with axe-core (via `jest-axe` or Storybook addon)

## Forms
- **React Hook Form** for all forms — not uncontrolled or manual state
- **Zod** for validation schema; integrate with RHF via `@hookform/resolvers/zod`
- Controlled inputs only when RHF doesn't cover the use case
- Show inline field errors; show form-level error for server errors

## Testing
- **Vitest** + **React Testing Library** — test behavior, not implementation
- Never test internal state or implementation details
- Query by role, label, or text — not by CSS class or component name
- `userEvent` (not `fireEvent`) for realistic user interaction simulation
- Mock network requests with **MSW (Mock Service Worker)**
- Snapshot tests only for stable, reviewed UI components — not for logic

```tsx
it('shows error message when login fails', async () => {
  server.use(http.post('/api/auth/login', () => HttpResponse.json({ error: 'Invalid credentials' }, { status: 401 })));
  render(<LoginForm />);
  await userEvent.type(screen.getByLabelText('Email'), 'user@test.com');
  await userEvent.type(screen.getByLabelText('Password'), 'wrong');
  await userEvent.click(screen.getByRole('button', { name: 'Sign in' }));
  expect(await screen.findByText('Invalid credentials')).toBeInTheDocument();
});
```

## File & Folder Conventions
```
src/
├── components/       # Shared/reusable components
├── features/         # Feature-scoped components, hooks, utils
│   └── auth/
│       ├── LoginForm.tsx
│       ├── LoginForm.test.tsx
│       ├── useLogin.ts
│       └── index.ts
├── hooks/            # Global custom hooks
├── pages/ or app/    # Route-level components
├── lib/              # Third-party integrations (queryClient, axios, etc.)
└── types/            # Shared TypeScript types
```
