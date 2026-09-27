# OpenAPI 3.1 Template and Lint Setup

A starting skeleton that encodes the rules in `SKILL.md`: problem details, cursor pagination,
`Idempotency-Key`, ETags with `If-Match`, `429` + `Retry-After`, and a global security requirement.
Rename the `Order` resource; keep the shared components.

## `openapi.yaml`

```yaml
openapi: 3.1.1
info:
  title: Orders API
  version: 1.0.0
  description: Create and track customer orders.
servers:
  - url: https://api.example.com/v1
security:
  - bearerAuth: []
tags:
  - name: orders
    description: Customer orders.

paths:
  /orders:
    get:
      operationId: listOrders
      summary: List orders
      tags: [orders]
      parameters:
        - $ref: '#/components/parameters/Limit'
        - $ref: '#/components/parameters/Cursor'
        - name: status
          in: query
          schema:
            $ref: '#/components/schemas/OrderStatus'
      responses:
        '200':
          description: A page of orders.
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/OrderPage'
        '400': { $ref: '#/components/responses/BadRequest' }
        '401': { $ref: '#/components/responses/Unauthorized' }
        '429': { $ref: '#/components/responses/TooManyRequests' }
    post:
      operationId: createOrder
      summary: Create an order
      tags: [orders]
      parameters:
        - $ref: '#/components/parameters/IdempotencyKey'
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/OrderCreate'
      responses:
        '201':
          description: Order created.
          headers:
            Location: { $ref: '#/components/headers/Location' }
            ETag: { $ref: '#/components/headers/ETag' }
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Order'
        '400': { $ref: '#/components/responses/BadRequest' }
        '401': { $ref: '#/components/responses/Unauthorized' }
        '409': { $ref: '#/components/responses/Conflict' }
        '422': { $ref: '#/components/responses/UnprocessableContent' }
        '429': { $ref: '#/components/responses/TooManyRequests' }

  /orders/{orderId}:
    parameters:
      - name: orderId
        in: path
        required: true
        schema: { type: string, format: uuid }
    get:
      operationId: getOrder
      summary: Get an order
      tags: [orders]
      parameters:
        - name: If-None-Match
          in: header
          schema: { type: string }
      responses:
        '200':
          description: The order.
          headers:
            ETag: { $ref: '#/components/headers/ETag' }
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Order'
        '304':
          description: Not modified.
        '401': { $ref: '#/components/responses/Unauthorized' }
        '404': { $ref: '#/components/responses/NotFound' }
    patch:
      operationId: updateOrder
      summary: Update an order
      tags: [orders]
      parameters:
        - name: If-Match
          in: header
          required: true
          schema: { type: string }
      requestBody:
        required: true
        content:
          application/merge-patch+json:
            schema:
              $ref: '#/components/schemas/OrderUpdate'
      responses:
        '200':
          description: Updated order.
          headers:
            ETag: { $ref: '#/components/headers/ETag' }
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Order'
        '401': { $ref: '#/components/responses/Unauthorized' }
        '404': { $ref: '#/components/responses/NotFound' }
        '412': { $ref: '#/components/responses/PreconditionFailed' }
        '422': { $ref: '#/components/responses/UnprocessableContent' }
        '428': { $ref: '#/components/responses/PreconditionRequired' }

components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT

  parameters:
    Limit:
      name: limit
      in: query
      schema: { type: integer, minimum: 1, maximum: 100, default: 20 }
    Cursor:
      name: cursor
      in: query
      description: Opaque cursor from `page.nextCursor`.
      schema: { type: string, maxLength: 512 }
    IdempotencyKey:
      name: Idempotency-Key
      in: header
      required: true
      description: Client-generated UUID; retries with the same key replay the first response.
      schema: { type: string, format: uuid }

  headers:
    ETag:
      schema: { type: string }
    Location:
      schema: { type: string, format: uri-reference }
    RetryAfter:
      description: Seconds to wait before retrying.
      schema: { type: integer, minimum: 0 }

  schemas:
    OrderStatus:
      type: string
      enum: [pending, paid, shipped, cancelled]
    Money:
      type: object
      additionalProperties: false
      required: [amountMinor, currency]
      properties:
        amountMinor: { type: integer, minimum: 0 }
        currency: { type: string, pattern: '^[A-Z]{3}$' }
    OrderCreate:
      type: object
      additionalProperties: false
      required: [customerId, lines]
      properties:
        customerId: { type: string, format: uuid }
        lines:
          type: array
          minItems: 1
          maxItems: 100
          items:
            type: object
            additionalProperties: false
            required: [sku, quantity]
            properties:
              sku: { type: string, maxLength: 64 }
              quantity: { type: integer, minimum: 1, maximum: 1000 }
    OrderUpdate:
      type: object
      additionalProperties: false
      properties:
        shippingNote: { type: [string, 'null'], maxLength: 500 }
    Order:
      type: object
      required: [id, status, total, createdAt]
      properties:
        id: { type: string, format: uuid }
        status: { $ref: '#/components/schemas/OrderStatus' }
        total: { $ref: '#/components/schemas/Money' }
        shippingNote: { type: [string, 'null'] }
        createdAt: { type: string, format: date-time }
    OrderPage:
      type: object
      required: [data, page]
      properties:
        data:
          type: array
          items: { $ref: '#/components/schemas/Order' }
        page:
          type: object
          required: [nextCursor]
          properties:
            nextCursor: { type: [string, 'null'] }
    Problem:
      type: object
      required: [type, title, status]
      properties:
        type: { type: string, format: uri-reference, default: 'about:blank' }
        title: { type: string }
        status: { type: integer, minimum: 100, maximum: 599 }
        detail: { type: string }
        instance: { type: string, format: uri-reference }
        code: { type: string, description: Stable machine-readable error code. }
        requestId: { type: string }
        errors:
          type: array
          items:
            type: object
            required: [pointer, detail]
            properties:
              pointer: { type: string, description: JSON Pointer into the request. }
              detail: { type: string }

  responses:
    BadRequest:
      description: Malformed request.
      content:
        application/problem+json:
          schema: { $ref: '#/components/schemas/Problem' }
    Unauthorized:
      description: Missing or invalid credentials.
      headers:
        WWW-Authenticate:
          schema: { type: string }
      content:
        application/problem+json:
          schema: { $ref: '#/components/schemas/Problem' }
    NotFound:
      description: Resource not found or not visible to the caller.
      content:
        application/problem+json:
          schema: { $ref: '#/components/schemas/Problem' }
    Conflict:
      description: Conflicting state or idempotent request still in progress.
      content:
        application/problem+json:
          schema: { $ref: '#/components/schemas/Problem' }
    PreconditionFailed:
      description: The `If-Match` ETag does not match the current representation.
      content:
        application/problem+json:
          schema: { $ref: '#/components/schemas/Problem' }
    PreconditionRequired:
      description: '`If-Match` is required for this operation.'
      content:
        application/problem+json:
          schema: { $ref: '#/components/schemas/Problem' }
    UnprocessableContent:
      description: Validation failed, or an idempotency key was reused with a different payload.
      content:
        application/problem+json:
          schema: { $ref: '#/components/schemas/Problem' }
    TooManyRequests:
      description: Rate limit exceeded.
      headers:
        Retry-After: { $ref: '#/components/headers/RetryAfter' }
      content:
        application/problem+json:
          schema: { $ref: '#/components/schemas/Problem' }
```

## Lint configuration

Redocly CLI v2 (`redocly.yaml`):

```yaml
extends:
  - recommended
rules:
  operation-operationId: error
  operation-4xx-response: error
  security-defined: error
```

Spectral (`.spectral.yaml`) — for OpenAPI 3.0/3.1 until Spectral ships 3.2 support:

```yaml
extends: ["spectral:oas"]
rules:
  error-responses-use-problem-json:
    description: 4xx and 5xx responses must use application/problem+json.
    severity: error
    given: "$.paths[*][*].responses[?(@property.match(/^[45]/))].content"
    then:
      field: application/problem+json
      function: truthy
```

## CI steps

Pin the tools as dev dependencies, then run:

```bash
redocly lint openapi.yaml
oasdiff breaking --fail-on ERR -- "origin/main:openapi.yaml" "openapi.yaml"
schemathesis run "$API_BASE_URL/openapi.json" --checks all -H "Authorization: Bearer $TEST_TOKEN"
```

`TEST_TOKEN` comes from the CI secret store and belongs to a least-privilege test principal.
