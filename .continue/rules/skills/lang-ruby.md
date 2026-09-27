---
name: lang-ruby
description: Ruby and Rails standards — Ruby 4.0 (3.4 supported), Rails 8.1, YJIT in production, RuboCop 1.9x or Standard, Sorbet or RBS/Steep, Brakeman and bundler-audit, Zeitwerk, service objects behind ports, RSpec/Minitest, Solid Queue, Rails.event structured logging, and OpenTelemetry Ruby. Use when writing, reviewing, or configuring Ruby code, Rails apps, gems, Gemfiles, gemspecs, or Rakefiles.
globs:
  - "**/*.rb"
  - "**/Gemfile"
  - "**/*.gemspec"
  - "**/Rakefile"
  - "**/config.ru"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# Ruby and Rails Standards

Covers Ruby code, Rails apps, and gems. Database migrations are in `db-migrations`; API
contracts in `api-rest-openapi`; CI in `devops-cicd`; containers in `devops-docker`.

## Baseline

- **Ruby 4.0** (4.0.7 current) for new apps; **3.4** still in normal maintenance; 3.3 is
  security-only until March 2027; 3.2 and older are EOL — upgrade.
- Pin the version in `.ruby-version` and `Gemfile` (`ruby file: ".ruby-version"`).
- **Rails 8.1** (8.1.4 current; requires Ruby 3.2+). Rails 8.0 security support ends
  7 November 2026 — upgrade before then; check rubyonrails.org/maintenance for newer minors.
- JIT: run **YJIT** in production (Rails enables it by default on supported Rubies, or set
  `RUBY_YJIT_ENABLE=1`). ZJIT (Ruby 4.0) is experimental — CI/staging experiments only.
- Ruby 4.0 `Ruby::Box` and Ractors are experimental; do not build production features on them.

## Toolchain

- Lint/format: **RuboCop** (1.90 current) with extensions loaded via `plugins:`
  (`rubocop-rails`, `rubocop-rspec`, `rubocop-performance`); new Rails apps ship
  `rubocop-rails-omakase` — extend it rather than replacing it. Alternative: **Standard**
  (`standard` + `standard-rails` plugin) with no per-rule config. One tool per repo.
- Types: **Sorbet** (`sorbet`, `sorbet-runtime`, `tapioca` for gem RBIs) for gradual typing
  with runtime checks, or **RBS + Steep** (inline RBS in Steep is experimental). Type at least
  domain objects, ports, and service entry points.
- Security: **Brakeman** 8.0.x and **bundler-audit** (`bin/brakeman --no-pager`,
  `bin/bundler-audit check --update`) block CI. Note bundler-audit is GPL-3.0 (dev-only
  tool); clear it with your license policy.
- `bin/rails zeitwerk:check` in CI; Rails 8.1 local CI (`config/ci.rb` + `bin/ci`) should
  mirror the remote pipeline.
- Commit `Gemfile.lock`; add `bundle lock --add-platform` for every deploy platform; no
  `git:` gems pointing at branches.

## Structure

- Zeitwerk rules: file path equals constant path; every directory under `app/` is a root, so
  namespace with a subfolder (`app/domain/orders/order.rb` → `Orders::Order`).
- Hexagonal layout for non-trivial features:
  - `app/domain/<feature>/` — POROs and `Data` value objects, domain errors, use cases
    (service objects with one public `call`).
  - Ports — duck-typed collaborators injected into use cases (`orders:`, `payments:`),
    documented with Sorbet interfaces or RBS and covered by shared contract specs.
  - `app/adapters/<feature>/` — Active Record repositories, HTTP clients, vendor SDKs
    (Stripe, AWS). Vendor gems are referenced **only** here.
  - Controllers, jobs, and channels are thin: parse/validate input → call a use case → map
    the result.
- Active Record models own persistence and simple validations; keep workflows, cross-aggregate
  rules, and external calls out of callbacks.
- Keep business logic out of views, helpers, and concerns-as-junk-drawers.

## Errors

- Expected outcomes (validation failure, not found, conflict) return a Result object with a
  symbolic error code; unexpected failures raise.
- Define a domain exception hierarchy (`Orders::Error < StandardError`) for failures callers
  may handle; never `rescue Exception`; never `rescue => e` without logging and re-raising or
  converting.
- Map domain errors to HTTP in one place (`rescue_from` in `ApplicationController` plus a
  code → status table); error bodies never include backtraces or SQL.
- Use `find_by` + explicit not-found handling in use cases; reserve `find`/`save!` for paths
  where the exception is the intended control boundary.

## Concurrency and Jobs

- Puma threads share the process: no mutable class-level state, memoized globals, or
  `@@class_vars`; use `ActiveSupport::CurrentAttributes` for request context.
- **Solid Queue** (1.6) is the Rails 8 default Active Job backend. Jobs are idempotent, take
  IDs not objects, set `retry_on`/`discard_on` explicitly, and are enqueued after the
  transaction commits.
- Solid Queue fiber workers (`fibers:` in `config/queue.yml`) suit I/O-bound jobs (LLM or
  HTTP calls); they require the `async` gem and `config.active_support.isolation_level = :fiber`.
- Every outbound HTTP call has open/read timeouts and a bounded retry policy.

## Security

- SQL: Active Record hash conditions or placeholders (`where("email = ?", email)`);
  `sanitize_sql_like` for `LIKE`; never interpolate input into SQL, `order`, or `pluck`.
- Input: `params.expect(order: [:quantity])` (Rails 8) or `permit`; validate types and ranges
  in the use case; never mass-assign from `params` directly.
- Auth: Rails 8 authentication generator or a vetted gem; `has_secure_password` (bcrypt);
  `rate_limit to:, within:` on login, signup, and password-reset actions.
- Keep CSRF protection on for session-authenticated endpoints; configure the CSP initializer;
  `config.force_ssl = true`; `HttpOnly`/`Secure`/`SameSite` cookies.
- Secrets in encrypted credentials or environment/secret manager; never commit
  `config/master.key`. Encrypt PII columns with `encrypts`.
- Never `Marshal.load`, `YAML.load`, `constantize`, `send`/`public_send`, or `Kernel#open` on
  untrusted input; use `YAML.safe_load`, allow-lists, `File.open`.
- Shell out only with argument arrays (`system("convert", path)`), never a single interpolated
  string.
- `config.filter_parameters` covers passwords, tokens, secrets, and PII fields.

## Observability

- Never `puts`/`p`/`pp` in application code. Use `Rails.logger` (JSON formatter in
  production) with `config.log_tags = [:request_id]`.
- Rails 8.1 `Rails.event.notify("order.quantity_changed", order_id:)` for structured business
  events; `Rails.event.set_context` for request-wide fields; a subscriber serializes to JSON.
  Keep PII out of payloads.
- OpenTelemetry: `opentelemetry-sdk`, `opentelemetry-exporter-otlp`,
  `opentelemetry-instrumentation-all`, configured in an initializer with `c.use_all`; set
  `OTEL_SERVICE_NAME` and `OTEL_EXPORTER_OTLP_ENDPOINT` via environment.

## Testing

- **RSpec** (`rspec-rails`) or **Minitest** (Rails default); one per app. Use
  `factory_bot` or fixtures consistently.
- Unit-test use cases with fake ports (no database); request specs for endpoints; system
  tests (Capybara) only for critical UI flows.
- Shared contract specs run against both the fake and the real adapter of each port.
- Block real HTTP in tests (WebMock); record third-party interactions deliberately (VCR).
- Parallelize (`parallelize(workers: :number_of_processors)`); track coverage with SimpleCov.

Read `reference/rails-patterns.md` when implementing a use case with a Result, a port and its
Active Record adapter, controller error mapping, specs with fakes, the OpenTelemetry
initializer, or a `Rails.event` subscriber.

_Versions verified September 2026._
