---
name: lang-php
description: PHP and Laravel standards — PHP 8.3+, strict types, Laravel 11+ application structure, Eloquent without N+1, form requests, queues, Pest testing, PHPStan/Larastan, and Pint. Use when writing or reviewing PHP code, Laravel applications, or Composer configuration.
globs:
  - "**/*.php"
  - "**/composer.json"
  - "**/composer.lock"
  - "**/phpstan.neon*"
  - "**/pint.json"
  - "**/artisan"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# PHP & Laravel Standards

## Language

- `declare(strict_types=1);` at the top of every PHP file.
- Type every parameter, return, and property; use `readonly` properties and classes for value
  objects and DTOs; backed `enum`s instead of string constants.
- Constructor property promotion for dependencies; no `new` for services inside business code.
- Static analysis: PHPStan (Larastan for Laravel) at level 8 or higher, enforced in CI.
- Formatting with Pint (Laravel preset) or PHP-CS-Fixer; never hand-format.

## Laravel structure

- Controllers are thin: validate via a Form Request, call an action/service, return a resource.
- Business logic lives in action or service classes (`app/Actions`, `app/Services`) — not in
  controllers, models, or Blade views.
- API responses go through Eloquent API Resources; never return models directly.
- Configuration via `config/*.php` reading `env()`; call `env()` only inside config files.
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

- Authorization with policies and gates, checked in controllers or actions (`$this->authorize`).
- CSRF protection stays enabled for web routes; APIs use Sanctum or Passport tokens.
- Blade `{{ }}` escaping only; `{!! !!}` requires a documented reason and sanitized input.
- Rate limit auth routes with `RateLimiter`; hash passwords with the framework hasher only.

## Testing

- Pest (or PHPUnit) with feature tests for every endpoint and unit tests for actions.
- `RefreshDatabase` or transactions per test; factories for fixtures.
- Fake external systems: `Http::fake()`, `Queue::fake()`, `Mail::fake()`, `Storage::fake()`.
- Arch tests (`pest-plugin-arch`) to enforce layer rules, e.g. controllers never use `DB`.
