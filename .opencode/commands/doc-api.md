Generate a complete OpenAPI 3.x specification for this project's API, validate it, and produce
interactive documentation (Swagger UI / ReDoc). Works for both initial generation and updating
an existing spec after code changes.

Read `AGENTS.md`, the source files in scope, and any existing `openapi.json` / `openapi.yaml`
before generating.

---

## Step 1: Detect Stack and Generation Strategy

Read `AGENTS.md` → `docs/context/tech-stack.md` to identify the framework(s) in use.
Determine whether to use **code-first** (annotate source, then generate) or **spec-first**
(write the spec, then validate against code):

| Framework | Strategy | Tool |
|-----------|----------|------|
| Spring Boot / Kotlin | Code-first | `springdoc-openapi-starter-webmvc-ui` |
| FastAPI (Python) | Code-first (automatic) | Built-in — just expose `/openapi.json` |
| Django REST | Code-first | `drf-spectacular` |
| ASP.NET Core | Code-first | `Swashbuckle.AspNetCore` |
| TypeScript / Node.js | Code-first | `tsoa` or `zod-to-openapi` |
| TypeScript / NestJS | Code-first | `@nestjs/swagger` |
| Go | Code-first | `swaggo/swag` |
| Any (existing spec) | Spec-first | Validate + enrich |

---

## Step 2: Scan Existing API Surface

Read all handler / controller / router files to map the current API surface:
- All HTTP endpoints: method, path, request body type, response type, status codes
- Authentication requirements (Bearer JWT, API key, OAuth scopes)
- Path parameters, query parameters, headers
- Error response shapes

Report any endpoints that have:
- Missing request body schema
- Missing response schema
- No documented error cases
- No authentication declaration

---

## Step 3: Generate or Update the OpenAPI Spec

### For Spring Boot (Java / Kotlin)
Add dependency to `pom.xml` / `build.gradle.kts`:
```xml
<!-- Maven -->
<dependency>
  <groupId>org.springdoc</groupId>
  <artifactId>springdoc-openapi-starter-webmvc-ui</artifactId>
  <version>2.5.0</version>
</dependency>
```

Access at: `GET /api-docs` (JSON), `GET /swagger-ui.html` (interactive)

Generate static file:
```bash
mvn springdoc-openapi:generate -Dspringdoc.output-dir=. -Dspringdoc.output-filename=openapi
```

### For FastAPI (Python)
```python
# Already automatic — validate it's exposed:
app = FastAPI(
    title="My API",
    description="API description",
    version="1.0.0",
    openapi_url="/openapi.json",
    docs_url="/docs",
    redoc_url="/redoc",
)

# Generate static file:
# python -c "from app.main import app; import json; open('openapi.json','w').write(json.dumps(app.openapi(), indent=2))"
```

### For TypeScript / tsoa
```bash
npm install tsoa swagger-ui-express
# Generate spec:
npx tsoa spec
# Output: build/swagger.json
```

For **NestJS**:
```typescript
// main.ts
const config = new DocumentBuilder()
  .setTitle('My API')
  .setDescription('API description')
  .setVersion('1.0')
  .addBearerAuth()
  .build();
const document = SwaggerModule.createDocument(app, config);
SwaggerModule.setup('api-docs', app, document);
// Export: SwaggerModule.createDocument(app, config) → write to openapi.json
```

### For Go / swag
```bash
go install github.com/swaggo/swag/cmd/swag@latest
swag init -g cmd/server/main.go --output docs/swagger
```

### For ASP.NET Core
```csharp
// Program.cs
builder.Services.AddSwaggerGen(c => {
    c.SwaggerDoc("v1", new OpenApiInfo { Title = "My API", Version = "v1" });
    // Include XML docs:
    var xmlFile = $"{Assembly.GetExecutingAssembly().GetName().Name}.xml";
    c.IncludeXmlComments(Path.Combine(AppContext.BaseDirectory, xmlFile));
});
app.UseSwagger();
app.UseSwaggerUI();
```

---

## Step 4: Validate the Spec

```bash
# Install Redocly CLI
npm install -g @redocly/cli

# Lint for common issues
redocly lint openapi.json

# Check for breaking changes (if a previous spec exists)
redocly diff openapi-previous.json openapi.json

# Bundle (resolve $ref references into a single file)
redocly bundle openapi.json -o openapi-bundled.json
```

Report all `errors` and `warnings` from the linter. Fix errors before proceeding.

**Common issues to look for and fix:**
- Missing `description` on operations and parameters
- Missing `example` values on schemas
- Inconsistent error response shapes across endpoints
- Missing 401/403 responses on authenticated endpoints
- Deprecated operations not marked with `deprecated: true`

---

## Step 5: Enrich Missing Documentation

For each endpoint missing documentation, generate or suggest:

```yaml
# Example: well-documented endpoint
/users/{id}:
  get:
    operationId: getUserById
    summary: Get a user by ID
    description: |
      Returns the full user profile for the specified ID.
      Requires authentication. The authenticated user can only
      access their own profile unless they have the `admin` role.
    tags: [Users]
    security:
      - bearerAuth: []
    parameters:
      - name: id
        in: path
        required: true
        description: The user's unique identifier
        schema:
          type: string
          format: uuid
          example: "550e8400-e29b-41d4-a716-446655440000"
    responses:
      '200':
        description: User found
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/UserResponse'
            example:
              id: "550e8400-e29b-41d4-a716-446655440000"
              email: "user@example.com"
              name: "Jane Smith"
              role: "user"
              createdAt: "2024-01-15T10:00:00Z"
      '401':
        $ref: '#/components/responses/Unauthorized'
      '403':
        $ref: '#/components/responses/Forbidden'
      '404':
        $ref: '#/components/responses/NotFound'
```

---

## Step 6: Generate Interactive Documentation

### Swagger UI (local development)
```bash
# Serve locally with Docker
docker run -p 8080:8080 \
  -e SWAGGER_JSON=/openapi.json \
  -v $(pwd):/usr/share/nginx/html/openapi.json \
  swaggerapi/swagger-ui
# → Open http://localhost:8080
```

### ReDoc (cleaner, read-only)
```bash
# Static HTML generation
npx @redocly/cli build-docs openapi.json -o docs/api/index.html

# Serve locally
npx @redocly/cli preview-docs openapi.json
# → Open http://localhost:8080
```

### For Docusaurus docs site
```bash
# Place bundled spec in static dir
cp openapi-bundled.json docs-site/static/
# Embed ReDoc as MDX component in docs-site/docs/api/reference.mdx
```

---

## Step 7: Generate SDK Clients (Optional)

If the project provides a public or internal SDK, generate clients from the spec:

**TypeScript (Hey API)**
```bash
npm install -D @hey-api/openapi-ts
npx openapi-ts -i openapi.json -o src/generated -c axios
```

**Multiple languages (Speakeasy)**
```bash
# Install: curl https://raw.githubusercontent.com/speakeasy-api/speakeasy/main/scripts/install.sh | sh
speakeasy generate sdk -s openapi.json -l typescript -o sdks/typescript
speakeasy generate sdk -s openapi.json -l python -o sdks/python
speakeasy generate sdk -s openapi.json -l go -o sdks/go
```

---

## Step 8: Output Summary

Produce a report:

```
API Documentation Generated
═══════════════════════════════════════════════════════

Spec Output :  openapi.json  (OpenAPI 3.x)
Bundled     :  openapi-bundled.json
Interactive :  docs/api/index.html  (ReDoc)

Endpoints documented : N
  GET    : N
  POST   : N
  PUT    : N
  PATCH  : N
  DELETE : N

Validation Results:
  Errors   : 0  (must be 0 before publishing)
  Warnings : N  (review and address)

Coverage Gaps (endpoints missing full documentation):
  - POST /orders — missing request body example
  - GET  /users  — missing 429 rate-limit response

Breaking Changes Since Last Spec:
  - [BREAKING] DELETE /users/{id} — removed (was deprecated in v1.2)
  - [BREAKING] POST /orders — `customerId` field renamed to `userId`

SDK clients generated:
  TypeScript : src/generated/
  Python     : sdks/python/

Next steps:
  1. Fix the N warnings with redocly lint openapi.json
  2. Add missing examples for coverage gaps
  3. Add breaking change entries to CHANGELOG.md
  4. Commit: git add openapi.json docs/api/ && git commit -m "docs(api): regenerate OpenAPI spec"
```

---

Target (optional — path, service name, or "all"): $ARGUMENTS
