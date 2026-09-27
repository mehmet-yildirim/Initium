---
name: lang-php
description: PHP and Laravel standards — PHP 8.4+ (8.5 current), strict types, Laravel 12–13 application structure, Gate-based authorization, Eloquent without N+1, form requests, queues, PHPStan 2/Larastan 3 at level 9+, Pint, Rector, composer audit, Monolog JSON logging with OpenTelemetry, and Pest with arch presets. Use when writing, reviewing, or configuring PHP code, Laravel applications, or Composer configuration.
paths:
  - "**/*.php"
  - "**/composer.json"
  - "**/composer.lock"
  - "**/phpstan.neon*"
  - "**/pint.json"
  - "**/artisan"
---

# PHP & Laravel Standards

PHP language rules and Laravel application structure. Database migration rules are in
`db-migrations`; container builds in `devops-docker`.

## Baseline

- PHP 8.5 for new projects; 8.4 minimum (active support until 2026-12-31). PHP 8.3 is
  security-only — plan upgrades off it.
- Laravel 13 (March 2026, PHP 8.3–8.5) for new apps and upgrades. Laravel 12 receives security
  fixes only (bug fixes ended 2026-08-13; security until 2027-02-24) — schedule the move to 13.
  Laravel 11 and older are unsupported.
- Pin the platform in `composer.json` (`"require": {"php": "^8.4"}` and `config.platform.php`)
  so dependency resolution matches production.

## Toolchain

- Static analysis: PHPStan 2 with Larastan 3 at level 9 or higher (level 10 is the maximum);
  new code never adds baseline entries.
- Formatting with Pint (Laravel preset) or PHP-CS-Fixer; never hand-format.
- Rector (`rector/rector` + `driftingly/rector-laravel` with `withComposerBased(laravel: true)`)
  for PHP and Laravel upgrades; review Rector changes in their own PR.
- `composer audit` in CI (fails on known advisories); commit `composer.lock`; install with
  `composer install --no-dev --prefer-dist` in production builds.
- CI: `pint --test`, `phpstan analyse`, `rector --dry-run`, `composer audit`, `pest --parallel`.

## Language

- `declare(strict_types=1);` at the top of every PHP file.
- Type every parameter, return, and property; use `readonly` properties and classes for value
  objects and DTOs; backed `enum`s instead of string constants.
- Constructor property promotion for dependencies; no `new` for services inside business code.
- Class constants in `SCREAMING_SNAKE_CASE` with typed constants (`const int MAX_ATTEMPTS = 5;`).

## Laravel structure

- Controllers are thin: validate via a Form Request, authorize, call an action/service, return a
  resource.
- Business logic lives in action or service classes (`app/Actions`, `app/Services`) — not in
  controllers, models, or Blade views.
- API responses go through Eloquent API Resources; never return models directly.
- Configuration via `config/*.php` reading `env()`; call `env()` only inside config files
  (Larastan enforces this).
- Bind interfaces to implementations in service providers to keep external integrations behind
  adapters.

## Eloquent and data

- Prevent N+1: eager load with `with()` and enable `Model::preventLazyLoading()` outside production.
- Guard mass assignment with explicit `$fillable`; never `$guarded = []` on user-facing models.
- Wrap multi-step writes in `DB::transaction()`.
- Use the query builder or Eloquent bindings — never interpolate input into `DB::raw` or `whereRaw`.
- Migrations are forward-only in shared environments; see `db-migrations`.

## Queues and events

- Slow or external work (mail, webhooks, reports) runs in queued jobs.
- Jobs are idempotent, declare `$tries`, `$backoff`, and `$timeout`, and implement `failed()`.
- Use `ShouldBeUnique` or locks for jobs that must not run concurrently.

## Security

- Authorization with policies, checked with `Gate::authorize('update', $post)` in controllers or
  actions, or the `can:` middleware on routes. The default base controller no longer includes
  `AuthorizesRequests`, so `$this->authorize()` fails unless the trait is added deliberately.
- Scope queries to the authenticated user or tenant; never trust IDs from the request body.
- CSRF protection stays enabled for web routes; APIs use Sanctum or Passport tokens.
- Blade `{{ }}` escaping only; `{!! !!}` requires a documented reason and sanitized input.
- Rate limit auth routes with `RateLimiter`; hash passwords with the framework hasher only.
- `APP_DEBUG=false` in production; secrets only in the environment or a secret manager, never in
  committed config.

## Observability

- Log through the `Log` facade / PSR-3 logger — never `echo`, `var_dump`, `dd`, or `dump` in
  application code.
- Production channel emits JSON (Monolog `JsonFormatter`, e.g. `'formatter' => JsonFormatter::class`
  on a `stderr` channel) with request id in the log context (`Log::withContext`); never log tokens,
  passwords, or PII.
- OpenTelemetry: the `opentelemetry` PHP extension plus `open-telemetry/sdk` and
  `open-telemetry/opentelemetry-auto-laravel` for auto-instrumented requests, queries, and jobs;
  configure OTLP export through `OTEL_*` environment variables.

## Testing

- Pest 4 (or PHPUnit) with feature tests for every endpoint and unit tests for actions.
- `RefreshDatabase` or transactions per test; factories for fixtures.
- Fake external systems: `Http::fake()`, `Queue::fake()`, `Mail::fake()`, `Storage::fake()`;
  `Http::preventStrayRequests()` so no test reaches the network.
- Arch tests with Pest's built-in presets — `arch()->preset()->php()`, `->security()`,
  `->laravel()` — plus project rules (e.g. `expect('App\Http\Controllers')->not->toUse('Illuminate\Support\Facades\DB')`).
- Test authorization: each policy-protected endpoint has a test proving another user gets 403/404.

_Versions verified September 2026._
