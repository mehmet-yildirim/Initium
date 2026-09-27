---
name: lang-typescript
description: TypeScript/JavaScript advanced standards — strict mode, patterns, runtime tooling. Use when writing or reviewing TypeScript or JavaScript code.
globs:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.mjs"
  - "**/tsconfig*.json"
  - "**/package.json"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# TypeScript / JavaScript Standards

## TypeScript Configuration
- `"strict": true` in tsconfig — non-negotiable
- `"noUncheckedIndexedAccess": true` — catches array/object access bugs
- `"exactOptionalPropertyTypes": true` — prevents undefined/missing ambiguity
- `"moduleResolution": "bundler"` (or `"node16"` for Node-only)
- Path aliases configured: `"@/*": ["./src/*"]`
- Target: `ES2022` or newer

## Type System
- Prefer `interface` for object shapes that may be extended
- Prefer `type` for unions, intersections, and mapped types
- Use discriminated unions for state modeling — never boolean flags:

```typescript
// Preferred: discriminated union
type RequestState<T> =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'success'; data: T }
  | { status: 'error'; error: Error };

// Avoid: booleans for state
type RequestState = { loading: boolean; error: Error | null; data: T | null };
```

- `unknown` for untrusted external data — never `any`
- `as const` for literal type narrowing on arrays/objects
- Generic constraints: `T extends Record<string, unknown>` not bare `T`
- Template literal types for string pattern enforcement
- Zod (or `valibot`) for runtime validation of external data; infer TS types from schemas

## Functional Patterns
- Prefer immutability: `const`, `readonly`, `Readonly<T>`, `ReadonlyArray<T>`
- Array transformation: `.map()`, `.filter()`, `.reduce()` over loops
- Use `structuredClone()` for deep cloning — never manual recursive clone
- Option pattern via `null` + optional chaining (`?.`) rather than sentinel values
- Result pattern for operations that can fail:

```typescript
type Result<T, E = Error> = { ok: true; value: T } | { ok: false; error: E };
```

## Async
- `async/await` everywhere — no raw `.then()/.catch()` chains
- `Promise.all([...])` for parallel independent async operations
- `Promise.allSettled([...])` when individual failures should not abort the rest
- Handle all promise rejections — no floating promises
- Use `AbortController` / `AbortSignal` for cancellable operations

## Module System
- ESM (`import`/`export`) — never CommonJS `require()` in new code
- Named exports preferred over default exports (better refactoring support)
- Barrel files (`index.ts`) for public API only — never for internal organization
- Import order (enforced by ESLint): type imports → stdlib → third-party → internal → relative

## Error Handling
- Custom error classes extending `Error` with typed codes:

```typescript
class AppError extends Error {
  constructor(
    public readonly code: 'NOT_FOUND' | 'UNAUTHORIZED' | 'VALIDATION',
    message: string,
    public readonly cause?: unknown
  ) {
    super(message, { cause });
    this.name = 'AppError';
  }
}
```

- `try/catch` only at boundaries — never inside pure business logic
- Always log the original error as `cause` when re-throwing

## Runtime / Tooling
- **Bun** for new projects (runtime + package manager + test runner + bundler)
- **Node.js 22+** if Bun not viable; `--experimental-strip-types` for direct TS execution
- **esbuild** or **Vite** for bundling
- **ESLint** with `typescript-eslint` (strict config); **Prettier** or Biome for formatting
- **Vitest** for unit/integration tests (Bun test if using Bun)

## Naming
- Types/Interfaces/Classes/Enums: `PascalCase`
- Variables/functions/methods: `camelCase`
- Constants: `SCREAMING_SNAKE_CASE` for truly global constants; `camelCase` for module-level `const`
- Generic parameters: `T`, `TData`, `TError`, `TEntity`
- Event handlers: `on` prefix — `onSubmit`, `onClick`
- Boolean vars/props: `is`/`has`/`can` prefix — `isLoading`, `hasError`, `canDelete`
- Files: `kebab-case.ts`; React components: `PascalCase.tsx`

## Node.js Specific
- Use `node:` prefix for stdlib: `import { readFile } from 'node:fs/promises'`
- Environment variables: validate and type with `zod` at startup (fail fast on missing config)
- `AsyncLocalStorage` for request-scoped context (trace IDs, auth) — avoid globals
