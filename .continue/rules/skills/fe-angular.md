---
name: fe-angular
description: Angular development standards — standalone components, signals, RxJS, NgRx, best practices. Use when writing or reviewing Angular components, services, or state management.
globs:
  - "**/*.component.ts"
  - "**/*.service.ts"
  - "**/*.module.ts"
  - "**/*.component.html"
  - "**/angular.json"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# Angular Development Standards

Visual design quality (typography, color, layout, avoiding templated UI): `frontend-design` and `impeccable`; tokens: `design-tokens`.

## Architecture
- Feature modules (or standalone components for Angular 17+) — one feature per module/directory
- Core module for singletons (auth, logging, HTTP interceptors); SharedModule for common components
- Prefer **Standalone Components** (Angular 17+ default) — no `NgModule` for new features
- Follow the Angular Style Guide naming conventions

```
src/app/
├── core/                   # Singletons: auth, interceptors, guards
├── shared/                 # Shared components, pipes, directives
├── features/
│   └── users/
│       ├── user-list/      # Feature components (standalone)
│       ├── user-detail/
│       ├── user.service.ts
│       ├── user.store.ts   # NgRx Signal Store or plain signals
│       └── user.routes.ts  # Lazy-loaded routes
└── app.routes.ts
```

## Components

### Standalone Components (preferred)
```typescript
@Component({
  selector: 'app-user-card',
  standalone: true,
  imports: [CommonModule, RouterLink, AsyncPipe],
  templateUrl: './user-card.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class UserCardComponent {
  @Input({ required: true }) userId!: string;
  @Output() deleted = new EventEmitter<string>();
}
```

- `ChangeDetectionStrategy.OnPush` on all components — default to immutable data flow
- `@Input({ required: true })` for mandatory inputs (Angular 16+)
- Use `input()` signal (Angular 17.1+) for reactive inputs without decorators
- Avoid `ElementRef` — use Angular CDK or template references instead

## Signals (Angular 17+)
- Prefer **Signals** over RxJS for local component state and simple reactive state
- `signal()` for writable state; `computed()` for derived state; `effect()` for side effects
- `toSignal()` to bridge RxJS Observables to Signals
- `toObservable()` to bridge Signals back to RxJS when needed

```typescript
export class UserListComponent {
  private userService = inject(UserService);
  searchQuery = signal('');
  users = toSignal(
    toObservable(this.searchQuery).pipe(
      debounceTime(300),
      switchMap(q => this.userService.search(q))
    ),
    { initialValue: [] }
  );
}
```

## Dependency Injection
- Use `inject()` function — not constructor injection for new code (Angular 14+)
- `providedIn: 'root'` for singleton services; `providedIn: 'any'` for per-lazy-module
- `InjectionToken<T>` for non-class dependencies (configs, factories)

## RxJS
- Unsubscribe from all subscriptions to prevent memory leaks:
  - Use `takeUntilDestroyed()` (Angular 16+) — preferred
  - `async` pipe in templates — auto-unsubscribes
  - `Subject` + `takeUntil` as fallback
- Use appropriate operators: `switchMap` (cancel previous), `concatMap` (queue), `mergeMap` (parallel), `exhaustMap` (ignore new while active)
- No nested subscriptions — use `switchMap`/`concatMap`/`mergeMap`
- Error handling: `catchError`, `retry`, `retryWhen` — always at the outer stream level
- `shareReplay({ bufferSize: 1, refCount: true })` for multicasted HTTP streams

## HTTP & Data Fetching
- `HttpClient` through a service layer — never directly in components
- Use `HttpInterceptorFn` (functional interceptors, Angular 15+) for auth headers, error handling, logging
- Return `Observable<T>` from service methods — not `Promise` (keeps RxJS composability)
- Handle errors in the service or a global interceptor — not in components

```typescript
@Injectable({ providedIn: 'root' })
export class UserService {
  private http = inject(HttpClient);
  private apiUrl = inject(API_URL);

  getUser(id: string): Observable<User> {
    return this.http.get<User>(`${this.apiUrl}/users/${id}`);
  }
}
```

## NgRx (for complex state)
- Use **NgRx Signal Store** (NgRx 17+) for new features — simpler than traditional NgRx
- Traditional NgRx (Actions + Reducers + Effects + Selectors) for complex cross-feature state
- Actions: verb + noun — `loadUsers`, `loadUsersSuccess`, `loadUsersFailure`
- Selectors: `selectUsers`, `selectUserById`, `selectUsersLoading`
- Effects: side effects only — never business logic; always handle errors with `catchError`
- `createActionGroup` for co-located action families

## Forms
- **Reactive Forms** for complex forms (not Template-Driven)
- `FormBuilder.nonNullable.group()` (Angular 14+) to avoid null type complications
- `Validators` composition for validation; custom validators return `ValidationErrors | null`
- Show errors only on `touched` or on form submit attempt

## Routing
- Lazy-loaded feature routes: `loadChildren` / `loadComponent`
- Route guards as functions (Angular 15+): `CanActivateFn`, `CanMatchFn`
- `ResolveFn<T>` for pre-loading route data
- `Router.navigate()` or `RouterLink` — never manual URL manipulation

## Templates
- Prefer `@if`, `@for`, `@switch` (Angular 17+ control flow) over `*ngIf`, `*ngFor`
- `@for (item of items; track item.id)` — always use `track`
- Avoid complex expressions in templates — move to computed signals or `get` accessors
- `| async` pipe for Observables in templates; signal values are unwrapped automatically

## Testing
- **Jest** (with `jest-preset-angular`) or **Karma + Jasmine** (default)
- `TestBed.configureTestingModule` with `imports: [ComponentUnderTest]` for standalone
- `SpectatorModule` or Angular Testing Library for cleaner test DX
- Mock services with `jasmine.createSpyObj` or Jest `vi.fn()`
- Test component behavior via DOM queries — not internal state

## Performance
- Lazy load all feature routes
- `OnPush` + Signals eliminates most zone.js overhead
- `defer` block (Angular 17+) for below-fold content: `@defer (on viewport) { <HeavyComponent /> }`
- `NgOptimizedImage` directive for all `<img>` tags
- Consider `provideExperimentalZonelessChangeDetection()` for fully signal-based apps
