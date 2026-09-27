---
name: lang-python
description: Python development standards — FastAPI/Django, type hints, pytest, modern Python patterns. Use when writing or reviewing Python code.
paths:
  - "**/*.py"
  - "**/pyproject.toml"
  - "**/requirements*.txt"
  - "**/Pipfile"
  - "**/setup.py"
---

# Python Development Standards

## Code Style
- Follow PEP 8; enforced by Ruff (linter + formatter)
- Line length: 88 characters (Black/Ruff default)
- Double quotes for strings (Ruff default)
- Two blank lines between top-level definitions; one between methods
- Imports: stdlib → third-party → internal, each group separated by blank line
- Absolute imports preferred over relative imports

## Type Hints (Required)
- Type hints on ALL public functions, methods, and class attributes
- Use `from __future__ import annotations` for forward references (Python 3.10+)
- Use `X | Y` union syntax (not `Union[X, Y]`)
- Use `X | None` (not `Optional[X]`)
- Use `list[T]`, `dict[K, V]`, `tuple[T, ...]` (not `List`, `Dict`, `Tuple`)
- Strict mypy configuration: `strict = true` in `pyproject.toml`

```python
# Preferred
def get_user(user_id: int, include_deleted: bool = False) -> User | None:
    ...

# Avoid
def get_user(user_id, include_deleted=False):
    ...
```

## Naming Conventions
- Variables / functions / methods: `snake_case`
- Classes: `PascalCase`
- Constants: `SCREAMING_SNAKE_CASE` at module level
- Private: `_single_underscore` prefix
- "Truly private" (name mangling): `__double_underscore` — rarely needed
- Type variables: `T`, `UserT`, `EntityT`

## Project Structure
```
src/
├── package_name/
│   ├── __init__.py
│   ├── api/            # FastAPI routers / Django views
│   ├── core/           # Business logic (no framework deps)
│   ├── models/         # Domain models / ORM models
│   ├── repositories/   # Data access
│   ├── services/       # Application services
│   ├── schemas/        # Pydantic models (request/response DTOs)
│   └── config.py       # Settings via pydantic-settings
tests/
├── unit/
├── integration/
└── conftest.py
```

## FastAPI Conventions
- Use Pydantic v2 models for all request/response schemas
- Annotate path operations with response models: `response_model=UserResponse`
- Dependency injection via `Depends()` for services, auth, DB sessions
- Use `APIRouter` grouped by feature; include in main `app` with prefix
- Lifespan context manager for startup/shutdown (not deprecated events)
- Background tasks for fire-and-forget work: `BackgroundTasks`
- Structured error handling: `HTTPException` for HTTP errors; custom exception handlers

```python
@router.get("/users/{user_id}", response_model=UserResponse)
async def get_user(
    user_id: UUID,
    service: Annotated[UserService, Depends(get_user_service)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> UserResponse:
    user = await service.get_by_id(user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")
    return UserResponse.model_validate(user)
```

## Django Conventions (if applicable)
- Fat models / thin views is outdated — use service layer for business logic
- No raw SQL in views; use ORM queryset methods
- `select_related` / `prefetch_related` to prevent N+1 queries
- Class-based views for standard CRUD; function views for complex custom logic
- Use `django-ninja` or DRF for APIs; prefer `django-ninja` for new projects (Pydantic-native)

## SQLAlchemy / Databases
- Use SQLAlchemy 2.x with `async` session
- Alembic for migrations — never auto-migrate in production
- Use `select()` syntax (not legacy `session.query()`)
- Explicit `async with session.begin()` transaction boundaries in services
- No ORM calls in domain/core layer — use repository pattern

## Error Handling
- Use custom exception classes for domain errors
- Never catch `Exception` without logging and re-raising or handling
- Use `contextlib.suppress()` only for truly ignorable errors
- Structured logging with `structlog` or `logging` (JSON format for production)

## Testing (pytest)
- pytest with `pytest-asyncio` for async tests
- `httpx.AsyncClient` for FastAPI integration tests (not TestClient for async routes)
- Fixtures for database sessions with transaction rollback
- `factory_boy` for test data factories
- `pytest-cov` for coverage; target ≥ 85% for business logic
- Test file naming: `test_<module>.py`; test functions: `test_does_x_when_y()`
- Use `pytest.mark.parametrize` for data-driven tests

## Modern Python Features (Python 3.12+)
- `dataclasses` with `frozen=True` for value objects
- `@dataclass(slots=True)` for memory efficiency
- `tomllib` for TOML parsing (stdlib in 3.11+)
- `asyncio.TaskGroup` for structured concurrency
- Match/case (structural pattern matching) for complex conditionals
- `pathlib.Path` everywhere — never `os.path`
- `pydantic-settings` for environment variable configuration

## Tooling
- Package manager: `uv` (preferred) or `poetry`
- Linter + formatter: `ruff` (replaces flake8, isort, black)
- Type checker: `mypy` in strict mode or `pyright`
- Pre-commit hooks: ruff + mypy + pytest (fast tests only)
