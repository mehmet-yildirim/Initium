# FastAPI feature, end to end (hexagonal)

A "place order" feature for the layout in SKILL.md: Python 3.14, FastAPI ≥0.121 (for
`Depends(scope="function")`), Pydantic v2, SQLAlchemy 2.1 async with psycopg 3, httpx,
PyJWT 2.x (`pyjwt[crypto]`), structlog. Forward references are unquoted — PEP 649 makes that
safe without `from __future__ import annotations`.

## Shared kernel

```python
# src/orders_service/shared/errors.py
from typing import ClassVar


class DomainError(Exception):
    """Expected business failure. Subclass a category; main.py maps categories to HTTP."""

    code: ClassVar[str] = "domain_error"


class NotFoundError(DomainError): ...


class RuleViolation(DomainError): ...


class ConflictError(DomainError): ...


class UnavailableError(DomainError): ...
```

```python
# src/orders_service/shared/db.py
from collections.abc import AsyncIterator
from typing import Annotated

from fastapi import Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase): ...


async def get_session(request: Request) -> AsyncIterator[AsyncSession]:
    session_factory: async_sessionmaker[AsyncSession] = request.app.state.session_factory
    # Commits on success, rolls back if the endpoint raises.
    async with session_factory() as session, session.begin():
        yield session


# scope="function": the transaction ends before the response is sent, so a failed commit
# can never follow a 2xx already delivered to the client.
SessionDep = Annotated[AsyncSession, Depends(get_session, scope="function")]
```

```python
# src/orders_service/shared/auth.py
from typing import Annotated, Protocol

import jwt
import structlog
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

logger = structlog.get_logger()
bearer = HTTPBearer(auto_error=False)


class TokenVerifier(Protocol):
    def customer_id_from(self, token: str) -> str | None: ...


class JwtTokenVerifier:
    def __init__(self, jwks_url: str, audience: str, issuer: str) -> None:
        self._jwks = jwt.PyJWKClient(jwks_url)
        self._audience = audience
        self._issuer = issuer

    def customer_id_from(self, token: str) -> str | None:
        try:
            signing_key = self._jwks.get_signing_key_from_jwt(token)
            claims = jwt.decode(
                token,
                signing_key.key,
                algorithms=["RS256"],
                audience=self._audience,
                issuer=self._issuer,
                options={"require": ["exp", "sub"]},
            )
        except jwt.PyJWTError as exc:
            logger.info("token_rejected", reason=type(exc).__name__)
            return None
        subject = claims.get("sub")
        return subject if isinstance(subject, str) else None


def get_token_verifier(request: Request) -> TokenVerifier:
    verifier: TokenVerifier = request.app.state.token_verifier
    return verifier


# Sync on purpose: PyJWKClient may fetch keys over the network, so FastAPI runs this in a
# threadpool instead of blocking the event loop.
def current_customer_id(
    verifier: Annotated[TokenVerifier, Depends(get_token_verifier)],
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> str:
    customer_id = verifier.customer_id_from(credentials.credentials) if credentials else None
    if customer_id is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return customer_id


CurrentCustomer = Annotated[str, Depends(current_customer_id)]
```

## Domain (stdlib only)

```python
# src/orders_service/features/orders/domain/errors.py
from uuid import UUID

from orders_service.shared.errors import NotFoundError, RuleViolation, UnavailableError


class InvalidOrderTotal(RuleViolation):
    code = "invalid_order_total"

    def __init__(self, total_cents: int) -> None:
        super().__init__(f"Order total must be positive, got {total_cents}.")
        self.total_cents = total_cents


class CustomerBlocked(RuleViolation):
    code = "customer_blocked"

    def __init__(self) -> None:
        super().__init__("This customer cannot place orders.")


class OrderNotFound(NotFoundError):
    code = "order_not_found"

    def __init__(self, order_id: UUID) -> None:
        super().__init__(f"Order {order_id} was not found.")
        self.order_id = order_id


class CustomerDirectoryUnavailable(UnavailableError):
    code = "customer_directory_unavailable"

    def __init__(self) -> None:
        super().__init__("Customer checks are temporarily unavailable.")
```

```python
# src/orders_service/features/orders/domain/order.py
import uuid
from dataclasses import dataclass

from orders_service.features.orders.domain.errors import InvalidOrderTotal


@dataclass(frozen=True, slots=True)
class Order:
    id: uuid.UUID
    customer_id: str
    total_cents: int

    @classmethod
    def place(cls, customer_id: str, total_cents: int) -> Order:
        if total_cents <= 0:
            raise InvalidOrderTotal(total_cents)
        return cls(id=uuid.uuid7(), customer_id=customer_id, total_cents=total_cents)
```

## Application (use cases + ports)

```python
# src/orders_service/features/orders/application/ports.py
from typing import Protocol
from uuid import UUID

from orders_service.features.orders.domain.order import Order


class OrderRepository(Protocol):
    async def add(self, order: Order) -> None: ...

    async def get_for_customer(self, order_id: UUID, customer_id: str) -> Order | None: ...


class CustomerDirectory(Protocol):
    async def is_blocked(self, customer_id: str) -> bool: ...
```

```python
# src/orders_service/features/orders/application/use_cases.py
from dataclasses import dataclass
from uuid import UUID

from orders_service.features.orders.application.ports import CustomerDirectory, OrderRepository
from orders_service.features.orders.domain.errors import CustomerBlocked, OrderNotFound
from orders_service.features.orders.domain.order import Order


@dataclass(frozen=True, slots=True)
class PlaceOrder:
    customer_id: str
    total_cents: int


class PlaceOrderHandler:
    def __init__(self, orders: OrderRepository, customers: CustomerDirectory) -> None:
        self._orders = orders
        self._customers = customers

    async def __call__(self, command: PlaceOrder) -> Order:
        if await self._customers.is_blocked(command.customer_id):
            raise CustomerBlocked()
        order = Order.place(command.customer_id, command.total_cents)
        await self._orders.add(order)
        return order


class GetOrderHandler:
    def __init__(self, orders: OrderRepository) -> None:
        self._orders = orders

    async def __call__(self, order_id: UUID, customer_id: str) -> Order:
        # Scoped to the caller: another customer's id is indistinguishable from a missing one.
        order = await self._orders.get_for_customer(order_id, customer_id)
        if order is None:
            raise OrderNotFound(order_id)
        return order
```

## Adapters

```python
# src/orders_service/features/orders/adapters/persistence.py
from uuid import UUID

from sqlalchemy import String, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Mapped, mapped_column

from orders_service.features.orders.domain.order import Order
from orders_service.shared.db import Base


class OrderRow(Base):
    __tablename__ = "orders"

    id: Mapped[UUID] = mapped_column(primary_key=True)
    customer_id: Mapped[str] = mapped_column(String(64), index=True)
    total_cents: Mapped[int]


class SqlAlchemyOrderRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def add(self, order: Order) -> None:
        self._session.add(
            OrderRow(id=order.id, customer_id=order.customer_id, total_cents=order.total_cents)
        )
        await self._session.flush()

    async def get_for_customer(self, order_id: UUID, customer_id: str) -> Order | None:
        statement = select(OrderRow).where(
            OrderRow.id == order_id, OrderRow.customer_id == customer_id
        )
        row = await self._session.scalar(statement)
        if row is None:
            return None
        return Order(id=row.id, customer_id=row.customer_id, total_cents=row.total_cents)
```

```python
# src/orders_service/features/orders/adapters/customers.py
from urllib.parse import quote

import httpx
from pydantic import BaseModel, ValidationError

from orders_service.features.orders.domain.errors import CustomerDirectoryUnavailable


class _CustomerStatus(BaseModel):
    blocked: bool


class HttpCustomerDirectory:
    def __init__(self, client: httpx.AsyncClient) -> None:
        self._client = client

    async def is_blocked(self, customer_id: str) -> bool:
        try:
            path = f"/customers/{quote(customer_id, safe='')}/status"
            response = await self._client.get(path)
            response.raise_for_status()
            return _CustomerStatus.model_validate_json(response.content).blocked
        except (httpx.HTTPError, ValidationError) as exc:
            # Fail closed: an unknown status must not let a blocked customer order.
            raise CustomerDirectoryUnavailable() from exc
```

```python
# src/orders_service/features/orders/adapters/http.py
from typing import Annotated
from uuid import UUID

import httpx
from fastapi import APIRouter, Depends, Request, status
from pydantic import BaseModel, ConfigDict, Field

from orders_service.features.orders.adapters.customers import HttpCustomerDirectory
from orders_service.features.orders.adapters.persistence import SqlAlchemyOrderRepository
from orders_service.features.orders.application.ports import CustomerDirectory
from orders_service.features.orders.application.use_cases import (
    GetOrderHandler,
    PlaceOrder,
    PlaceOrderHandler,
)
from orders_service.features.orders.domain.order import Order
from orders_service.shared.auth import CurrentCustomer
from orders_service.shared.db import SessionDep

router = APIRouter(prefix="/orders", tags=["orders"])


class PlaceOrderRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    total_cents: int = Field(gt=0, le=10_000_000)


class OrderResponse(BaseModel):
    id: UUID
    total_cents: int

    @classmethod
    def from_domain(cls, order: Order) -> OrderResponse:
        return cls(id=order.id, total_cents=order.total_cents)


def get_customer_directory(request: Request) -> CustomerDirectory:
    client: httpx.AsyncClient = request.app.state.customers_client
    return HttpCustomerDirectory(client)


def get_place_order(
    session: SessionDep,
    customers: Annotated[CustomerDirectory, Depends(get_customer_directory)],
) -> PlaceOrderHandler:
    return PlaceOrderHandler(SqlAlchemyOrderRepository(session), customers)


def get_get_order(session: SessionDep) -> GetOrderHandler:
    return GetOrderHandler(SqlAlchemyOrderRepository(session))


@router.post("", status_code=status.HTTP_201_CREATED)
async def place_order(
    body: PlaceOrderRequest,
    customer_id: CurrentCustomer,
    handler: Annotated[PlaceOrderHandler, Depends(get_place_order)],
) -> OrderResponse:
    order = await handler(PlaceOrder(customer_id=customer_id, total_cents=body.total_cents))
    return OrderResponse.from_domain(order)


@router.get("/{order_id}")
async def get_order(
    order_id: UUID,
    customer_id: CurrentCustomer,
    handler: Annotated[GetOrderHandler, Depends(get_get_order)],
) -> OrderResponse:
    return OrderResponse.from_domain(await handler(order_id, customer_id))
```

## Composition root

```python
# src/orders_service/config.py
from pydantic import HttpUrl, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="ORDERS_", extra="ignore")

    database_url: SecretStr
    customers_base_url: HttpUrl
    jwks_url: HttpUrl
    jwt_audience: str
    jwt_issuer: str
    json_logs: bool = True
```

```python
# src/orders_service/main.py
import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import httpx
import structlog
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from orders_service.config import Settings
from orders_service.features.orders.adapters.http import router as orders_router
from orders_service.shared.auth import JwtTokenVerifier
from orders_service.shared.errors import (
    ConflictError,
    DomainError,
    NotFoundError,
    RuleViolation,
    UnavailableError,
)

logger = structlog.get_logger()

HTTP_STATUS_BY_CATEGORY: dict[type[DomainError], int] = {
    NotFoundError: 404,
    ConflictError: 409,
    RuleViolation: 422,
    UnavailableError: 503,
}
EXTERNAL_CALL_TIMEOUT_SECONDS = 2.0


def configure_logging(*, json_logs: bool) -> None:
    renderer = (
        structlog.processors.JSONRenderer() if json_logs else structlog.dev.ConsoleRenderer()
    )
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.dict_tracebacks,
            renderer,
        ],
        wrapper_class=structlog.make_filtering_bound_logger(logging.INFO),
    )


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(DomainError)
    async def handle_domain_error(_: Request, exc: DomainError) -> JSONResponse:
        status_code = next(
            (
                code
                for category, code in HTTP_STATUS_BY_CATEGORY.items()
                if isinstance(exc, category)
            ),
            400,
        )
        return JSONResponse(
            status_code=status_code,
            media_type="application/problem+json",
            content={"title": str(exc), "status": status_code, "code": exc.code},
        )

    @app.exception_handler(Exception)
    async def handle_unexpected(request: Request, exc: Exception) -> JSONResponse:
        logger.exception("unhandled_error", path=request.url.path, error_type=type(exc).__name__)
        return JSONResponse(
            status_code=500,
            media_type="application/problem+json",
            content={"title": "Internal Server Error", "status": 500},
        )


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings()
    configure_logging(json_logs=settings.json_logs)

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        engine = create_async_engine(settings.database_url.get_secret_value(), pool_pre_ping=True)
        try:
            async with httpx.AsyncClient(
                base_url=str(settings.customers_base_url),
                timeout=httpx.Timeout(EXTERNAL_CALL_TIMEOUT_SECONDS),
            ) as customers_client:
                app.state.session_factory = async_sessionmaker(engine, expire_on_commit=False)
                app.state.customers_client = customers_client
                app.state.token_verifier = JwtTokenVerifier(
                    str(settings.jwks_url), settings.jwt_audience, settings.jwt_issuer
                )
                yield
        finally:
            await engine.dispose()

    app = FastAPI(title="Orders", lifespan=lifespan)
    app.include_router(orders_router)
    register_error_handlers(app)
    FastAPIInstrumentor.instrument_app(app, excluded_urls="healthz,readyz")
    return app
```

Run with `uvicorn orders_service.main:create_app --factory`. Export `OTEL_SERVICE_NAME` and
`OTEL_EXPORTER_OTLP_ENDPOINT`, or launch under `opentelemetry-instrument` to also configure the
SDK and exporters from env vars. Health endpoints (`/healthz`, `/readyz`) are omitted here.

## Tests

`tests/` and its subfolders contain `__init__.py` so `tests.fakes` imports resolve.

```python
# tests/fakes.py
from uuid import UUID

from orders_service.features.orders.domain.order import Order


class InMemoryOrders:
    def __init__(self) -> None:
        self.saved: dict[UUID, Order] = {}

    async def add(self, order: Order) -> None:
        self.saved[order.id] = order

    async def get_for_customer(self, order_id: UUID, customer_id: str) -> Order | None:
        order = self.saved.get(order_id)
        return order if order is not None and order.customer_id == customer_id else None


class StubCustomers:
    def __init__(self, *, blocked: bool) -> None:
        self._blocked = blocked

    async def is_blocked(self, customer_id: str) -> bool:
        return self._blocked


class FakeTokenVerifier:
    def __init__(self, customers_by_token: dict[str, str]) -> None:
        self._customers_by_token = customers_by_token

    def customer_id_from(self, token: str) -> str | None:
        return self._customers_by_token.get(token)
```

```python
# tests/unit/orders/test_place_order.py
import pytest

from orders_service.features.orders.application.use_cases import PlaceOrder, PlaceOrderHandler
from orders_service.features.orders.domain.errors import CustomerBlocked, InvalidOrderTotal
from tests.fakes import InMemoryOrders, StubCustomers


@pytest.mark.anyio
async def test_place_order_saves_order_when_customer_is_allowed() -> None:
    orders = InMemoryOrders()
    handler = PlaceOrderHandler(orders, StubCustomers(blocked=False))

    order = await handler(PlaceOrder(customer_id="c-1", total_cents=1_500))

    assert orders.saved[order.id] == order


@pytest.mark.anyio
async def test_place_order_raises_when_customer_is_blocked() -> None:
    handler = PlaceOrderHandler(InMemoryOrders(), StubCustomers(blocked=True))

    with pytest.raises(CustomerBlocked):
        await handler(PlaceOrder(customer_id="c-1", total_cents=1_500))


@pytest.mark.anyio
async def test_place_order_raises_when_total_is_not_positive() -> None:
    handler = PlaceOrderHandler(InMemoryOrders(), StubCustomers(blocked=False))

    with pytest.raises(InvalidOrderTotal):
        await handler(PlaceOrder(customer_id="c-1", total_cents=0))
```

The integration tests use the sync `TestClient` (it drives async endpoints fine) with
lifespan enabled, real Postgres from Testcontainers, and Alembic migrations. They assume
`alembic/env.py` reads `sqlalchemy.url` from the Alembic config.

```python
# tests/integration/test_orders_api.py
from collections.abc import Iterator

import pytest
from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from pydantic import SecretStr
from testcontainers.postgres import PostgresContainer

from orders_service.config import Settings
from orders_service.features.orders.adapters.http import get_customer_directory
from orders_service.main import create_app
from orders_service.shared.auth import get_token_verifier
from tests.fakes import FakeTokenVerifier, StubCustomers

pytestmark = pytest.mark.integration

TOKENS = {"token-a": "customer-a", "token-b": "customer-b"}


@pytest.fixture(scope="session")
def database_url() -> Iterator[str]:
    with PostgresContainer("postgres:18-alpine", driver="psycopg") as postgres:
        url = postgres.get_connection_url()
        alembic_config = Config("alembic.ini")
        alembic_config.set_main_option("sqlalchemy.url", url)
        command.upgrade(alembic_config, "head")
        yield url


@pytest.fixture
def client(database_url: str) -> Iterator[TestClient]:
    settings = Settings(
        database_url=SecretStr(database_url),
        customers_base_url="http://customers.invalid",
        jwks_url="http://jwks.invalid/.well-known/jwks.json",
        jwt_audience="orders",
        jwt_issuer="https://issuer.invalid",
        json_logs=False,
    )
    app = create_app(settings)
    app.dependency_overrides[get_token_verifier] = lambda: FakeTokenVerifier(TOKENS)
    app.dependency_overrides[get_customer_directory] = lambda: StubCustomers(blocked=False)
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_place_order_returns_401_without_token(client: TestClient) -> None:
    response = client.post("/orders", json={"total_cents": 1_500})

    assert response.status_code == 401


def test_place_order_returns_422_for_non_positive_total(client: TestClient) -> None:
    response = client.post("/orders", json={"total_cents": 0}, headers=auth("token-a"))

    assert response.status_code == 422


def test_get_order_returns_404_for_another_customers_order(client: TestClient) -> None:
    created = client.post("/orders", json={"total_cents": 1_500}, headers=auth("token-a"))
    assert created.status_code == 201

    response = client.get(f"/orders/{created.json()['id']}", headers=auth("token-b"))

    assert response.status_code == 404
```

For a test that must itself be `async` (for example, awaiting a queue consumer alongside the
request), use `httpx.AsyncClient(transport=httpx.ASGITransport(app=app),
base_url="http://test")` inside `asgi_lifespan.LifespanManager(app)` and mark it
`@pytest.mark.anyio`.
