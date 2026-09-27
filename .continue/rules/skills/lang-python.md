---
name: lang-python
description: Python 3.14 standards for services and libraries — uv 0.12 project management with a committed uv.lock, ruff 0.16 lint/format including flake8-bandit (S) rules, strict type checking (mypy or pyright; ty beta optional), PEP 649 deferred annotations, FastAPI + Pydantic v2 + SQLAlchemy 2.1 in feature folders with hexagonal ports and adapters, typed domain errors, durable background jobs, structlog + OpenTelemetry, pip-audit, pytest 9. Use when writing, reviewing, or configuring Python code, pyproject.toml, or uv/ruff tooling.
globs:
  - "**/*.py"
  - "**/*.pyi"
  - "**/pyproject.toml"
  - "**/uv.lock"
  - "**/ruff.toml"
  - "**/.python-version"
  - "**/requirements*.txt"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# Python Standards

## Baseline

- New services target **Python 3.14** (`requires-python = ">=3.14"`, `.python-version` = `3.14`).
  Libraries support **3.13+** unless a consumer needs older.
- 3.13 moves to security-only fixes on 1 Oct 2026; plan upgrades off 3.12 and earlier now.
- Python 3.15.0 is due 1 Oct 2026 — adopt it once your dependencies publish 3.15 wheels.
- Annotations are evaluated lazily on 3.14 (PEP 649). **Do not add `from __future__ import
  annotations`** — forward references work unquoted, and the future import turns annotations
  into strings that break runtime introspection (Pydantic, FastAPI dependencies, dataclass tools)
  for locally scoped types. Use `annotationlib` when you must read annotations yourself.
- Libraries that still support 3.13 quote the few forward references they need instead of
  adding the future import.
- Free-threaded builds (`python3.14t`) are officially supported but opt-in. Use them for
  CPU-bound work only after confirming every C extension declares free-threading support.

## Toolchain

- **uv** is the package and project manager. Commit `uv.lock`; install with `uv sync --locked`
  in CI and images; add deps with `uv add` (never hand-edit the lock). `uv lock --check` fails
  CI when `pyproject.toml` and the lock drift apart.
- Use `[dependency-groups]` (PEP 735) for `dev`/`test` tooling, not optional extras.
- Build backend `uv_build` with the `src/` layout; metadata lives in the `[project]` table.
  No `setup.py`, `setup.cfg`, `Pipfile`, or unpinned `requirements.txt` for new work —
  export requirements from the lock only when a tool needs them.
- **ruff** is the only linter and formatter (replaces black, isort, flake8, bandit plugins).
  Keep the 0.16 defaults and add `S` (security), `T20` (no `print`), `ASYNC`, `BLE`
  (blind `except`). Run `ruff format --check` and `ruff check` in CI.
- Type checking is required: `mypy --strict` or pyright in strict mode. `ty` (Astral) is
  still beta — fine as an extra fast editor check, not as the CI gate yet.
- Vulnerability scanning: `pip-audit` against a hashed export of `uv.lock` in CI; `uv audit`
  (preview) may replace it once stable. Add a minimum release age (`exclude-newer`) per
  `security-supply-chain`.
- Pre-commit hooks: ruff format, ruff check, type checker. Keep slow tests out of hooks.
- `reference/tooling.md` — Read when writing `pyproject.toml`, ruff/mypy/pytest config, the
  Dockerfile, or the CI job.

## Style and naming

- PEP 8 via `ruff format`: 88 columns, double quotes. Imports stdlib → third-party → local
  (ruff `I`); absolute imports inside the package.
- `snake_case` functions/variables/modules, `PascalCase` classes, `SCREAMING_SNAKE_CASE`
  module constants, `_leading_underscore` for internals. Avoid `__name_mangling`.
- Annotate every public function, method, and attribute. Use `X | None`, `list[T]`,
  `dict[K, V]`, PEP 695 generics (`def first[T](xs: list[T]) -> T`, `type UserId = int`).
- Prefer `@dataclass(frozen=True, slots=True)` for domain value objects, Pydantic models only
  at boundaries (HTTP, messages, settings). `enum.StrEnum` for closed string sets.
- `pathlib.Path` over `os.path`; `match` for branching on shapes; `typing.assert_never` to make
  `match` over unions exhaustive.

## Structure

Feature folders, hexagonal inside each feature. Domain and application code never import
FastAPI, SQLAlchemy, httpx, boto3, or any vendor SDK — those live in adapters behind ports.

```
src/orders_service/
├── main.py                    # app factory: lifespan, routers, exception handlers
├── config.py                  # pydantic-settings Settings (env only, no secrets in code)
├── shared/                    # logging, telemetry, db engine/session, base DomainError
└── features/
    └── orders/
        ├── domain/            # entities, value objects, domain errors (stdlib only)
        ├── application/       # use cases + ports (typing.Protocol)
        └── adapters/
            ├── http.py        # APIRouter, request/response schemas, dependencies
            ├── persistence.py # SQLAlchemy repository implementing the port
            └── customers.py   # httpx client implementing an outbound port
tests/
├── unit/orders/               # use cases with in-memory fakes
└── integration/               # HTTP + real Postgres (Testcontainers)
```

- Ports are `typing.Protocol` classes owned by `application/`; adapters implement them.
- Wire concrete adapters in one composition root (`main.py` lifespan + FastAPI `Depends`
  providers). Use cases receive ports through `__init__`, never import adapters.
- Configuration via `pydantic-settings`; validate at startup and fail fast.
- `reference/fastapi-hexagonal.md` — Read when adding a feature end to end (domain, use case,
  router, repository, error mapping, tests).

## FastAPI

- Pydantic v2 models for every request and response; return type annotations drive the
  response model. Constrain inputs (`Field(gt=0, max_length=...)`, `EmailStr`, `UUID`).
- `Annotated[T, Depends(provider)]` for sessions, auth, and use cases; one `APIRouter` per
  feature, included with a prefix and tags.
- Use the `lifespan` context manager for startup/shutdown; `on_event` is deprecated.
- Code after `yield` in a dependency runs after the response is sent by default. Declare the
  session/transaction dependency with `Depends(get_session, scope="function")` (FastAPI
  ≥0.121) so commit or rollback finishes before the client sees a 2xx.
- Routers translate HTTP ↔ commands and call a use case — no business logic, no ORM queries.
- Derive the acting user from the verified token dependency, never from body or query params.
- `BackgroundTasks` runs in-process after the response and is lost on restart or crash. Use it
  only for best-effort work (a cache warm-up). Work that must happen (emails, payments,
  webhooks) goes to a durable queue — **arq**, **Celery**, or **Dramatiq** — ideally via a
  transactional outbox, with idempotent handlers and retries.
- Django: keep business logic in services/use cases, not views or models; `select_related` /
  `prefetch_related` against N+1; django-ninja (Pydantic-native) or DRF for APIs.

## Errors

- Define a typed hierarchy: `DomainError` base in `shared/`, specific subclasses per feature
  (`OrderNotFound`, `CustomerBlocked`) carrying structured fields, not formatted strings.
- Raise domain errors from domain/application code; map them to HTTP **once** with
  `app.add_exception_handler(DomainError, ...)` returning RFC 9457 problem JSON.
- `HTTPException` belongs only in the HTTP adapter (for example, auth failures). Never raise it
  from use cases.
- When the caller must branch on outcomes, return a union of result dataclasses and handle it
  with an exhaustive `match` + `assert_never` instead of exceptions for control flow.
- Never `except Exception: pass`. Catch the narrowest type, log with context, then re-raise or
  translate (`raise OrderStoreUnavailable() from exc`). Use `except*` with `ExceptionGroup`
  from `TaskGroup`.
- The unhandled-exception handler logs the traceback and returns a generic 500 — no stack traces
  or internal messages in responses.

## Concurrency and runtime

- Never block the event loop in `async def`: no `requests`, `time.sleep`, sync DB drivers, or
  heavy CPU work. Use async clients (httpx, psycopg/asyncpg), `asyncio.to_thread` for
  unavoidable blocking I/O, or a plain `def` endpoint (FastAPI runs it in a threadpool).
- Structured concurrency with `asyncio.TaskGroup`; no orphaned `create_task` without a stored
  reference and error handling. Bound every external call with `asyncio.timeout(...)` and
  client-level timeouts.
- CPU-bound parallelism: `ProcessPoolExecutor`, `InterpreterPoolExecutor` (3.14, PEP 734), or
  the free-threaded build once dependencies support it.
- One `httpx.AsyncClient` and one SQLAlchemy `AsyncEngine` per process, created in `lifespan`
  and closed on shutdown. One `AsyncSession` per request/unit of work.
- SQLAlchemy 2.x `select()` style only; explicit `async with session.begin()` boundaries in
  use cases or a unit-of-work adapter. Alembic migrations run as a separate deploy step, never
  on app startup (`db-migrations`).
- Run with `uvicorn` (or `fastapi run`) behind the platform's process manager; expose liveness
  and readiness endpoints; handle SIGTERM gracefully.

## Security

- SQL only through SQLAlchemy expressions or bound parameters (`text("... :id").bindparams`).
  Never f-strings or `%` formatting into SQL, shell commands, or file paths.
- `subprocess.run([...], shell=False)` with an argument list; validate anything user-derived.
- Never `pickle`, `marshal`, `shelve`, or `yaml.load` on untrusted data — use
  `yaml.safe_load` and Pydantic validation. No `eval`/`exec`.
- Passwords: Argon2 via `pwdlib` or `argon2-cffi` (`passlib` is unmaintained). Tokens from
  `secrets`, never `random`.
- Settings read secrets from the environment / secret manager via `pydantic-settings`
  (`SecretStr`); never log them. Keep `.env` out of git; ship `.env.example`.
- Outbound HTTP: verify TLS (httpx default), set timeouts, allow-list hosts for any
  user-supplied URL (SSRF). Deeper review: `security-sast` → `reference/python.md`.

## Observability

- Use `logging` or `structlog` configured once at startup; JSON output in production,
  console renderer locally. **Never `print`** (ruff `T20` enforces it).
- Log with key/value context (`log.info("order_placed", order_id=...)`), not f-string
  messages; bind request/trace IDs per request. Never log tokens, passwords, or PII.
- OpenTelemetry: `opentelemetry-distro` + `opentelemetry-exporter-otlp`, and
  `opentelemetry-instrumentation-fastapi` (plus SQLAlchemy/httpx instrumentations) or run under
  `opentelemetry-instrument`. Configure via `OTEL_*` env vars; correlate logs with trace IDs.
- Metrics for queue depth, job failures, and external-call latency; health endpoints excluded
  from tracing noise.

## Testing

- pytest 9 with `pytest-cov`; target ≥ 85 % on domain/application code. Names:
  `tests/.../test_<module>.py`, `test_<does_x>_when_<y>()`. `pytest.mark.parametrize` for tables.
- Unit-test use cases with in-memory fakes implementing the ports — no mocks of your own
  domain, no database.
- FastAPI `TestClient` works for sync **and** async endpoints — use it by default, as
  `with TestClient(app) as client:` so lifespan runs. Use
  `httpx.AsyncClient(transport=ASGITransport(app=app), base_url="http://test")` only when the
  test itself is `async` (mark with `@pytest.mark.anyio`); wrap the app in
  `asgi_lifespan.LifespanManager` when that test needs lifespan.
- Swap adapters with `app.dependency_overrides`, and clear them after each test.
- Integration tests hit real Postgres via `testcontainers[postgres]` with Alembic migrations
  applied; isolate with a transaction rolled back per test or a truncate fixture.
- Test the security paths: 401 without a token, 403/404 for another user's resource,
  422 for invalid payloads.

_Versions verified September 2026._
