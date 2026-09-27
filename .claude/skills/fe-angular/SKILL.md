---
name: fe-angular
description: Angular 22 standards — standalone components with OnPush and zoneless defaults, signal input()/output()/model(), inject(), stable Signal Forms, resource()/httpResource(), NgRx Signal Store 22, functional guards/interceptors, SSR with incremental hydration, Angular Aria, DomSanitizer/CSP, angular-eslint, and Vitest as the default test runner. Use when writing, reviewing, upgrading, or configuring Angular components, services, forms, routing, or angular.json.
paths:
  - "**/angular.json"
  - "**/*.component.ts"
  - "**/*.component.html"
---

# Angular Standards

Angular-specific rules. Since v20 the CLI generates suffix-less files (`user-card.ts`,
`user-card.html`), so this skill is also triggered by task description, not only by path. Language
rules: `lang-typescript`. E2E: `testing-e2e`. Accessibility depth: `accessibility`.

## Baseline

- Angular 22 (released mid-2026), TypeScript 6.0, RxJS 7. Stay within the supported majors and run
  `ng update` each release.
- New apps are zoneless (default since v21) and components default to `OnPush` (v22; the old
  default is now `ChangeDetectionStrategy.Eager`). Do not re-add `zone.js` or
  `provideZoneChangeDetection` without a written reason.
- Vitest is the default unit test runner (since v21); Karma is legacy.

## Toolchain

- `angular-eslint` (`ng add angular-eslint`) with the recommended and template accessibility
  configs; Prettier for formatting; `ng build` with strict templates (`strictTemplates: true`).
- `npm audit` / `pnpm audit` in CI; update Angular packages together with `ng update`.
- Angular CLI MCP server and the official `angular-developer` agent skill are available for
  AI-assisted migrations (e.g., `onpush_zoneless_migration`).

## Structure

```
src/app/
├── app.config.ts                 # provideRouter, provideHttpClient, adapter providers
├── app.routes.ts
├── core/                         # Cross-cutting: auth session, interceptors, logger, error handler
├── shared/ui/                    # Presentational components, pipes, directives
└── features/projects/
    ├── domain/                   # Types, pure rules — no Angular imports
    ├── application/              # Use cases + ports (abstract class or InjectionToken)
    ├── data-access/              # Adapters: HTTP/SDK implementations of ports, DTO validation
    ├── state/                    # Signal Store or signal-based services
    ├── ui/                       # project-list.ts / project-list.html (suffix-less, v20+ style)
    └── projects.routes.ts        # Lazy-loaded routes
```

- Standalone everything; no `NgModule`s in new code and no `standalone: true` (default since v19).
  No CoreModule/SharedModule.
- Ports are abstract classes or `InjectionToken<T>`; adapters are bound in `app.config.ts` or route
  `providers`. Components never call `HttpClient` or vendor SDKs directly.
- `@Service()` (v22) for root singletons; `@Injectable` when you need custom provider
  configuration. `inject()` instead of constructor injection. `providedIn: 'any'` is deprecated.

## Components

```ts
@Component({
  selector: 'app-project-card',
  imports: [RouterLink, DatePipe],
  templateUrl: './project-card.html',
  host: { class: 'project-card', '[class.archived]': 'project().archived' },
})
export class ProjectCard {
  readonly project = input.required<Project>();
  readonly compact = input(false);
  readonly selected = model(false);
  readonly deleted = output<string>();

  protected readonly title = computed(() => this.project().name.trim());
}
```

- `input()`, `input.required()`, `output()`, `model()` — not `@Input`/`@Output`/`EventEmitter`.
- `host` metadata instead of `@HostBinding`/`@HostListener`.
- Built-in control flow (`@if`, `@for (x of xs; track x.id)`, `@switch`, `@defer`); no
  `*ngIf`/`*ngFor` in new templates.
- Avoid `ElementRef` DOM manipulation; use template refs, `viewChild()`, CDK, or Angular Aria.
- Keep templates simple: derive with `computed()`, not method calls or getters.

## Signals and async data

- `signal()` for writable state, `computed()` for derived state, `linkedSignal()` for state reset by
  a source, `effect()` only for syncing to non-signal APIs (DOM, storage, logging).
- Reads: `httpResource()` / `resource()` / `rxResource()` (stable in v22). Guard reads with
  `hasValue()` — `value()` throws in the error state — and render `isLoading()`/`error()`.
- Writes (mutations): a port method returning `Observable`/`Promise`, called from a store or event
  handler; then `reload()` the affected resource.
- RxJS where streams fit (websockets, complex event composition): `takeUntilDestroyed()`, the
  `async` pipe, `toSignal()`/`toObservable()` for bridging. `retry({ count, delay })` —
  `retryWhen` is deprecated. No nested subscribes.

Read `reference/signal-forms-and-resources.md` for Signal Forms, `httpResource`, and store examples.

## Forms

- **Signal Forms** (`@angular/forms/signals`, stable in v22) for new forms: model `signal`,
  `form(model, schema)`, validators (`required`, `email`, `minLength`, `validateHttp`, …),
  `[formField]` bindings, and `submit()`.
- Keep existing Reactive Forms (`FormBuilder.nonNullable`) until you touch them substantially;
  do not mix both APIs in one form.
- Server validation is authoritative; map server errors back onto fields.

## State

- Component-local: signals. Feature-level: a signal-based service or NgRx Signal Store
  (`@ngrx/signals` 22). Classic NgRx Store/Effects only where already adopted for cross-feature
  event flows.
- `@ngrx/signals/resource` extensions are experimental — gate usage behind an ADR.

## Routing

- Lazy `loadComponent`/`loadChildren`; functional guards (`CanActivateFn`, `CanMatchFn`) and
  resolvers (`ResolveFn`); `withComponentInputBinding()` to bind route params to `input()`s.
- Guards are UX only; the API authorizes every request.

## HTTP

- `provideHttpClient(withInterceptors([...]))` with functional `HttpInterceptorFn` for auth headers,
  correlation ids, and error mapping. Fetch is the default backend in v22 (`withFetch()` is
  deprecated); use `reportUploadProgress`/`reportDownloadProgress` instead of `reportProgress`.
- Validate response bodies at the adapter (Zod or hand-written guards) before they reach domain
  code.

## Errors

- Adapters map `HttpErrorResponse` to typed domain errors; UI renders error states from them.
- Provide a custom `ErrorHandler` that forwards to the logger; never swallow in `catchError` —
  rethrow or map to a typed error value.

## Security

- Angular escapes interpolation and sanitizes `[innerHTML]`/URLs. `DomSanitizer.bypassSecurityTrust*`
  only with reviewed, sanitized input and a comment naming the source.
- Enable a strict CSP: `security.autoCsp` in `angular.json` (hash-based, client-only apps), or a
  per-request nonce via `ngCspNonce` / the `CSP_NONCE` token for SSR apps. Consider Trusted Types
  (`require-trusted-types-for 'script'`).
- XSRF protection via `HttpClient` defaults/`withXsrfConfiguration` for cookie-based sessions; no
  tokens in `localStorage`.
- Never put secrets in `environment.ts` — it ships to the browser.

## SSR and performance

- `@angular/ssr` with `provideClientHydration()`; incremental hydration is the default in v22
  (`withIncrementalHydration()` deprecated). Use `@defer (hydrate on viewport)` for below-the-fold
  islands and event replay for early interactions.
- `NgOptimizedImage` for images; lazy routes; `injectAsync()` (v22) to code-split heavy services.
- Track Core Web Vitals (LCP ≤ 2.5 s, INP ≤ 200 ms, CLS ≤ 0.1 at p75).

## Accessibility

- Angular Aria (`@angular/aria`, stable in v22) or CDK a11y for headless accessible patterns
  (menus, tabs, listbox, tree) instead of hand-rolled ARIA.
- angular-eslint template accessibility rules in CI; axe checks per `accessibility`.

## Observability

- A logger service behind an `InjectionToken` forwarding to your telemetry SDK (OpenTelemetry web
  SDK, Sentry); no `console.log`. Propagate a correlation/trace header from an interceptor.
- Never log tokens or form values containing PII.

## Testing

- Vitest via the `@angular/build:unit-test` builder (`ng test`). Migrate legacy suites with the
  v22 `migrate-karma-to-vitest` migration (test setup), then
  `ng g refactor-jasmine-vitest --fake-async --include <path>` file by file; mocks use `vi.fn()`.
- `TestBed` with `imports: [ComponentUnderTest]`; prefer `await fixture.whenStable()` over
  `detectChanges()`; set signal inputs with `fixture.componentRef.setInput()`.
- Angular Testing Library or Vitest browser mode for DOM-level tests; `provideHttpClientTesting()`
  with `HttpTestingController` for adapters.
- E2E: `testing-e2e` (Playwright).

_Versions verified September 2026._
