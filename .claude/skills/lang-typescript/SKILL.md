---
name: lang-typescript
description: TypeScript language standards — TypeScript 7 native compiler (with the 6.0 API for typescript-eslint), strict tsconfig with nodenext, Node.js 24 LTS type stripping (erasableSyntaxOnly, verbatimModuleSyntax), ESM packages with exports, discriminated unions, typed errors, Zod at boundaries, pino logging, typescript-eslint type-checked rules, and Vitest. Use when writing, reviewing, or configuring TypeScript source, tsconfig files, or TypeScript package setup.
paths:
  - "**/*.ts"
  - "**/*.mts"
  - "**/*.cts"
  - "**/tsconfig*.json"
---

# TypeScript Standards

Language-level rules for all TypeScript. Service structure and HTTP frameworks are in `be-node`;
React components (`*.tsx`) are in `fe-react`.

## Baseline

- **Compiler:** TypeScript 7.0 (native Go port, GA July 2026) provides `tsc`. 7.0 ships no
  programmatic API, so tools that `import 'typescript'` (typescript-eslint, ts-morph, ts-jest) need
  the 6.0 API from `@typescript/typescript6` installed under the `typescript` name. Drop the alias
  once 7.1 ships its new API and your tools support it. Setup: `reference/toolchain.md`.
- **Runtime:** Node.js 24 (Active LTS). Node 26 enters LTS on 2026-10-28; move to it after that date.
  Bun is optional, per project, with an explicit decision recorded — never assumed.
- **Module format:** ESM only. `"type": "module"` in `package.json`; no `require()` in new code.
- Code that compiles cleanly on 6.0 without `ignoreDeprecations` compiles identically on 7.0 — fix
  6.0 deprecation warnings first when upgrading.

## tsconfig

- Required: `strict` (the default since 6.0 — keep it explicit), `noUncheckedIndexedAccess`,
  `exactOptionalPropertyTypes`, `noImplicitOverride`, `verbatimModuleSyntax`.
- Node code: `"module": "nodenext"` (implies `moduleResolution: nodenext`). Bundled front-end code:
  `"module": "preserve"` with `"moduleResolution": "bundler"`.
- `"target": "es2024"` or newer for Node 24.
- Set `rootDir` explicitly (defaults to `./` since 6.0) and `types` explicitly (defaults to `[]`
  since 6.0), e.g. `"types": ["node"]`.
- Removed in 7.0 (hard errors): `baseUrl`, `moduleResolution: node`/`node10`/`classic`,
  `target: es5`, `downlevelIteration`, `module: amd`/`umd`/`systemjs`/`none`, `esModuleInterop:
  false`, `alwaysStrict: false`, import `asserts` (use `with`). Do not add them.
- Aliases: `paths` relative to the tsconfig (no `baseUrl`). For code Node runs directly, prefer
  `package.json` `"imports"` (`#app/*`) — Node does not read tsconfig `paths`.
- Full app and library tsconfigs: `reference/toolchain.md`.

## Type stripping (Node runs `.ts` directly)

- Node 24 strips types by default (stable since 24.12); it does not type-check. Run `tsc --noEmit`
  in CI.
- Enable `erasableSyntaxOnly` so the compiler rejects syntax Node cannot strip:
  - no `enum` / `const enum` — use a union or an `as const` object;
  - no constructor parameter properties (`constructor(private repo: Repo)`) — declare fields;
  - no `namespace` with runtime code, no `import x = require()`.
- `verbatimModuleSyntax` requires `import type` / `export type` for type-only symbols, so stripping
  never leaves a dangling runtime import.
- Relative imports carry the `.ts` extension; `rewriteRelativeImportExtensions` rewrites them when
  emitting.

## Type system

- `unknown` for untrusted data — never `any`. Narrow with a schema, not with `as`.
- Discriminated unions for state; exhaustive `switch` with a `never` check:

```typescript
type Payment =
  | { status: 'pending' }
  | { status: 'settled'; settledAt: Date }
  | { status: 'failed'; reason: string };

function describe(payment: Payment): string {
  switch (payment.status) {
    case 'pending': return 'Awaiting settlement';
    case 'settled': return `Settled ${payment.settledAt.toISOString()}`;
    case 'failed': return `Failed: ${payment.reason}`;
    default: {
      const unreachable: never = payment;
      return unreachable;
    }
  }
}
```

- `interface` for extendable object shapes; `type` for unions, intersections, mapped types.
- `satisfies` to check a literal against a type without widening it; `as const` for literal tuples
  and lookup objects.
- Branded types for identifiers (`type UserId = string & { readonly __brand: 'UserId' }`).
- Generic constraints are explicit (`T extends Record<string, unknown>`); name type parameters
  `T`, `TData`, `TError`.
- `readonly` fields and `ReadonlyArray<T>` by default; `structuredClone()` for deep copies.

## Structure

- Feature folders (`src/orders/`) with `domain/` (entities, errors, pure logic), `ports/`
  (interfaces), `adapters/` (DB, HTTP clients, vendor SDKs), and `application/` (use cases).
- Vendor SDKs are imported only inside `adapters/`; domain and application code depend on ports.
- Named exports only; `index.ts` re-exports a feature's public API and contains no logic.
- Import order (enforced by lint): `node:` builtins → third-party → internal aliases (`#app/…`) →
  relative. Always use the `node:` prefix for builtins.

## Naming

- Types, interfaces, classes: `PascalCase`. Variables, functions: `camelCase`.
- Module-level constants holding fixed values: `SCREAMING_SNAKE_CASE` (`MAX_RETRY_COUNT`).
- Booleans: `is`/`has`/`can`/`should` prefix. Files: `kebab-case.ts`.

## Errors

- Expected failures are values: `type Result<T, E> = { ok: true; value: T } | { ok: false; error: E }`.
- Unexpected failures throw typed errors. Declare fields explicitly (parameter properties are not
  erasable) and pass `cause` through `ErrorOptions`:

```typescript
export type AppErrorCode = 'NOT_FOUND' | 'UNAUTHORIZED' | 'VALIDATION' | 'CONFLICT';

export class AppError extends Error {
  readonly code: AppErrorCode;

  constructor(code: AppErrorCode, message: string, options?: ErrorOptions) {
    super(message, options);
    this.name = 'AppError';
    this.code = code;
  }
}

// throw new AppError('NOT_FOUND', `Order ${orderId} not found`, { cause: dbError });
```

- `try/catch` at boundaries (handlers, adapters, jobs); map error codes to transport status in one
  place. Always keep the original error as `cause`. Never catch and ignore.
- `catch (error: unknown)` — narrow with `instanceof AppError` / `instanceof Error` before use.

## Async and resources

- `async/await` only; `Promise.all` for independent work, `Promise.allSettled` when partial failure
  is acceptable.
- No floating promises: every promise is awaited, returned, or explicitly handed to a supervisor
  (`@typescript-eslint/no-floating-promises` and `no-misused-promises` are errors).
- Every outbound call takes an `AbortSignal` and has a timeout (`AbortSignal.timeout(ms)`).
- `using` / `await using` with `Symbol.dispose` / `Symbol.asyncDispose` for handles, locks, and
  connections (supported in Node 24; add `"esnext.disposable"` to `lib`).
- `AsyncLocalStorage` for request-scoped context (request id, trace id) — no module-level mutable
  state.

## Security

- Validate every external input (HTTP, queue messages, files, env) with Zod (or Valibot) and infer
  types from the schema: `type CreateOrder = z.infer<typeof createOrderSchema>`.
- Parse `process.env` once at startup with a schema; exit on invalid config. No secrets in code.
- Never build SQL, shell commands, or HTML by string concatenation with input — use parameterized
  queries, `execFile` with an argument array, and framework escaping.
- Avoid prototype pollution: no recursive merges of untrusted objects; use `Object.create(null)` or
  `Map` for user-keyed data.
- Commit the lockfile; install with `npm ci` (or `pnpm install --frozen-lockfile`); run
  `npm audit --audit-level=high` in CI.

## Observability

- Log with pino (structured JSON), never `console.log`. Use child loggers carrying request and trace
  ids; configure `redact` for auth headers, tokens, and PII.
- OpenTelemetry setup for Node services is in `be-node`.

## Toolchain

- `tsc --noEmit` (TypeScript 7) for type checking in CI.
- ESLint flat config with `typescript-eslint` `strictTypeChecked` + `stylisticTypeChecked` and
  `projectService: true`; Prettier or Biome for formatting — pick one per repo.
- Config samples (tsconfig, ESLint, `package.json` `exports`): `reference/toolchain.md` — read when
  creating or changing project configuration.

## Testing

- Vitest (or `node:test`) with co-located `*.test.ts`; mock ports, not modules deep inside adapters.
- Type-level assertions with `expectTypeOf` for public generic APIs.
- Adapters get integration tests against real dependencies (Testcontainers).
- Run tests on the same Node major as production.

_Versions verified September 2026._
