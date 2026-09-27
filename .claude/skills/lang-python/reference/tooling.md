# Python tooling: pyproject, uv, ruff, mypy, pytest, CI

Versions verified on PyPI in September 2026. Lower bounds below are the current releases;
`uv.lock` pins the exact resolution.

| Tool | Version |
| --- | --- |
| Python | 3.14.x (3.15.0 due 1 Oct 2026) |
| uv / uv_build | 0.12.x |
| ruff | 0.16.x |
| mypy | 2.3.x (or pyright 1.1.41x) |
| pytest | 9.1.x |
| pip-audit | 2.10.x |
| FastAPI | 0.141.x |
| Pydantic | 2.13.x |
| SQLAlchemy | 2.1.x |

## pyproject.toml

```toml
[project]
name = "orders-service"
version = "0.1.0"
description = "Order placement API"
readme = "README.md"
requires-python = ">=3.14"
dependencies = [
    "fastapi>=0.141.1",
    "uvicorn[standard]>=0.54.0",
    "pydantic-settings>=2.15.0",
    "sqlalchemy[asyncio]>=2.1.1",
    "psycopg[binary]>=3.3.6",
    "alembic>=1.20.0",
    "httpx>=0.28.1",
    "pyjwt[crypto]>=2.15.0",
    "structlog>=26.1.0",
    "opentelemetry-distro>=0.66b0",
    "opentelemetry-exporter-otlp>=1.45.0",
    "opentelemetry-instrumentation-fastapi>=0.66b0",
]

[dependency-groups]
dev = [
    "ruff>=0.16.9",
    "mypy>=2.3.1",
    "pytest>=9.1.1",
    "pytest-cov>=7.1.0",
    "anyio>=4.15.1",
    "asgi-lifespan>=2.1.0",
    "testcontainers[postgres]>=4.15.0",
]

[build-system]
requires = ["uv_build>=0.12.19,<0.13"]
build-backend = "uv_build"

[tool.uv]
# Supply-chain cool-down; see security-supply-chain for the policy.
exclude-newer = "3 days"

[tool.ruff]
line-length = 88
src = ["src", "tests"]

[tool.ruff.lint]
# ruff 0.16 defaults stay on; these add security, no-print, async and blind-except checks.
extend-select = ["S", "T20", "ASYNC", "BLE", "B", "UP", "I", "PT"]

[tool.ruff.lint.per-file-ignores]
"tests/**" = ["S101", "S105", "S106"]

[tool.mypy]
strict = true
plugins = ["pydantic.mypy"]
files = ["src", "tests"]

[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = ["--strict-markers", "--cov=orders_service", "--cov-report=term-missing"]
markers = ["integration: needs Docker (Testcontainers)"]
```

Notes:

- `requires-python` also sets ruff's target version; no separate `target-version` needed.
- Do not enable ruff's `FA` (flake8-future-annotations) rules — they push the
  `from __future__ import annotations` import this skill forbids on 3.14.
- `S4xx` (suspicious imports) rules are preview-only in ruff; don't rely on them.
- Libraries: drop `exclude-newer` if it fights downstream resolvers, keep `requires-python`
  as low as you actually test (for example `>=3.13`) and add a CI matrix.

## Everyday commands

```bash
uv sync                      # create .venv from uv.lock (dev group included)
uv add httpx                 # add a runtime dependency and relock
uv add --dev pytest-xdist    # add to the dev group
uv run pytest -m "not integration"
uv run ruff format && uv run ruff check --fix
uv lock --upgrade-package fastapi
```

## CI job (shell steps)

```bash
uv sync --locked                               # fails if uv.lock is stale
uv run ruff format --check
uv run ruff check
uv run mypy
uv run pytest
# Vulnerability audit of the locked set (hashed export → no re-resolution).
uv export --locked --no-emit-project -o requirements-audit.txt
uvx pip-audit --require-hashes --disable-pip -r requirements-audit.txt
```

`uv audit` (preview in uv 0.12) audits the lockfile directly for vulnerabilities and
deprecated/quarantined packages; switch to it when it leaves preview.

## Dockerfile (multi-stage, non-root)

```dockerfile
FROM ghcr.io/astral-sh/uv:0.12-python3.14-trixie-slim AS build
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=0
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-dev --no-install-project
COPY src ./src
RUN uv sync --locked --no-dev --no-editable

FROM python:3.14-slim-trixie
RUN useradd --system --uid 10001 app
COPY --from=build --chown=app:app /app/.venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH"
USER app
EXPOSE 8000
CMD ["uvicorn", "orders_service.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000"]
```

Keep migrations out of `CMD`; run `alembic upgrade head` as a separate release job.
