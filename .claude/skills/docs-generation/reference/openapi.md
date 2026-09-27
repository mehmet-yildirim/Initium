# Documenting OpenAPI 3.1 / 3.2

Contract design rules (resource modeling, status codes, pagination, versioning, the canonical
RFC 9457 problem schema) live in `api-rest-openapi`. This file covers documentation quality.

## Version choice

- OpenAPI 3.1 is the safe default (full JSON Schema 2020-12 alignment).
- OpenAPI 3.2 (Sept 2025) adds hierarchical tags (`parent`, `kind`, `summary`), streaming media
  types with `itemSchema` (SSE, JSON Lines), the `query` method and `querystring` parameters, and
  OAuth 2.0 device flow. Adopt it only when your generator, linter and renderer all support it.

## Per-operation checklist

```yaml
paths:
  /users/{userId}:
    get:
      operationId: getUserById
      summary: Get a user
      description: Returns a single user. Soft-deleted users return 404.
      tags: [Users]
      security:
        - bearerAuth: []
      parameters:
        - name: userId
          in: path
          required: true
          schema: { type: string, format: uuid }
          examples:
            existing:
              value: 550e8400-e29b-41d4-a716-446655440000
      responses:
        '200':
          description: The user
          content:
            application/json:
              schema: { $ref: '#/components/schemas/User' }
              examples:
                active:
                  summary: Active user
                  value: { id: 550e8400-e29b-41d4-a716-446655440000, displayName: Ada }
        '401': { $ref: '#/components/responses/Unauthorized' }
        '404': { $ref: '#/components/responses/NotFound' }
```

## Shared error responses (RFC 9457)

```yaml
components:
  responses:
    Unauthorized:
      description: Missing or invalid credentials
      content:
        application/problem+json:
          schema: { $ref: '#/components/schemas/Problem' }
    NotFound:
      description: Resource not found
      content:
        application/problem+json:
          schema: { $ref: '#/components/schemas/Problem' }
  schemas:
    Problem:
      type: object
      properties:
        type: { type: string, format: uri-reference, default: about:blank }
        title: { type: string }
        status: { type: integer, minimum: 100, maximum: 599 }
        detail: { type: string }
        instance: { type: string, format: uri-reference }
      examples:
        - type: https://errors.example.com/user-not-found
          title: User not found
          status: 404
          instance: /users/550e8400-e29b-41d4-a716-446655440000
```

## Writing guidance

- `summary`: imperative, ≤ 8 words, no trailing period — shown in navigation.
- `description`: behavior, edge cases, idempotency, rate limits; Markdown (CommonMark) allowed.
- Describe every property (`description`), constraints (`minLength`, `pattern`, `enum`), and
  mark `readOnly`/`writeOnly`.
- Examples must validate against their schemas (Redocly `no-invalid-media-type-examples`).

## Tooling

- Lint: `redocly lint openapi.yaml` (or Spectral) with a committed ruleset.
- Breaking changes: `oasdiff breaking base.yaml head.yaml` in PRs.
- Render: Redoc, Scalar, or Swagger UI from the committed file; publish with the docs site.
