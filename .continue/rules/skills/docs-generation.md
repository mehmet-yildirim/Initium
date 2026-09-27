---
name: docs-generation
description: Documentation generation standards — code-level docs per language, OpenAPI patterns, architecture diagrams, documentation-as-code principles. Use when writing doc comments, OpenAPI annotations, or architecture diagrams.
globs:
  - "**/*.ts"
  - "**/*.js"
  - "**/*.py"
  - "**/*.java"
  - "**/*.kt"
  - "**/*.cs"
  - "**/*.go"
  - "**/*.swift"
  - "**/*.dart"
  - "openapi*.json"
  - "openapi*.yaml"
  - "**/docs/**/*.md"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# Documentation Generation Standards

## Documentation-as-Code Principles

1. **Docs live next to code** — place module-level `.md` files alongside source files
2. **Every public API surface must be documented** — no undocumented public functions
3. **Examples must be runnable** — code in docs is tested in CI
4. **Docs are reviewed like code** — PRs require doc updates for API/behavior changes
5. **Audience-targeted** — choose language and depth appropriate for the reader

## Code-Level Documentation Standards

### TypeScript / JavaScript (TSDoc)

```typescript
/**
 * Retrieves a user by their unique ID.
 *
 * @param userId - The UUID of the user to retrieve.
 * @param options - Optional configuration for the query.
 * @param options.includeDeleted - Whether to include soft-deleted users. Defaults to `false`.
 * @returns The user object, or `null` if not found.
 * @throws {@link DatabaseError} If the database connection fails.
 * @throws {@link ValidationError} If `userId` is not a valid UUID.
 *
 * @example
 * ```ts
 * const user = await userService.getById('550e8400-e29b-41d4-a716-446655440000');
 * if (user) {
 *   console.log(user.email);
 * }
 * ```
 *
 * @see {@link createUser} for creating new users.
 * @see {@link updateUser} for modifying existing users.
 */
export async function getUserById(
  userId: string,
  options?: { includeDeleted?: boolean }
): Promise<User | null> { ... }
```

**Rules:**
- Use `@param` for every parameter with a description (not just the type)
- Use `@returns` to describe return value — not just the type
- Use `@throws` for every error condition
- Include at least one `@example` for public functions
- Use `{@link}` to cross-reference related functions
- Toolchain: TypeDoc 0.25+; output: `docs/api/`

### Python (Google-style Docstrings)

```python
def get_user_by_id(
    user_id: str,
    *,
    include_deleted: bool = False,
) -> User | None:
    """Retrieve a user by their unique ID.

    Args:
        user_id: The UUID of the user to retrieve. Must be a valid UUIDv4.
        include_deleted: Whether to include soft-deleted users. Defaults to False.

    Returns:
        The User object if found, otherwise None.

    Raises:
        DatabaseError: If the database connection fails.
        ValidationError: If user_id is not a valid UUID format.

    Example:
        >>> user = get_user_by_id("550e8400-e29b-41d4-a716-446655440000")
        >>> print(user.email if user else "Not found")
    """
```

**Rules:**
- Google style preferred over NumPy or reStructuredText
- All public functions in non-trivial modules require docstrings
- `Args:`, `Returns:`, `Raises:`, `Example:` sections
- Toolchain: Sphinx + autodoc extension; output: `docs/build/html/`

### Java (JavaDoc)

```java
/**
 * Retrieves a user by their unique ID.
 *
 * <p>Returns an empty Optional if no user is found with the given ID.
 * Deleted users are excluded by default.</p>
 *
 * @param userId the UUID of the user to retrieve; must not be null
 * @param includeDeleted whether to include soft-deleted users
 * @return an Optional containing the user, or empty if not found
 * @throws DatabaseException if the database connection fails
 * @throws IllegalArgumentException if userId is null or invalid UUID format
 *
 * @see UserRepository#findById(UUID)
 * @since 1.0
 */
public Optional<User> getUserById(@NonNull UUID userId, boolean includeDeleted) { ... }
```

**Rules:**
- All `public` methods in non-private classes must have JavaDoc
- Use `@param`, `@return`, `@throws` for every signature element
- Use `{@link}` for cross-references, `{@code}` for inline code
- Toolchain: Maven Javadoc plugin; output: `target/site/apidocs/`

### Kotlin (KDoc)

```kotlin
/**
 * Retrieves a user by their unique ID.
 *
 * Returns `null` if no user exists with the given [userId].
 *
 * @param userId the UUID of the user to retrieve
 * @param includeDeleted whether to include soft-deleted users; defaults to `false`
 * @return the [User] if found, or `null` otherwise
 * @throws DatabaseException if the database connection fails
 *
 * @sample com.example.UserServiceSamples.getUserByIdExample
 */
suspend fun getUserById(userId: UUID, includeDeleted: Boolean = false): User?
```

Toolchain: Dokka; output: `build/dokka/html/`

### Go (GoDoc)

```go
// GetUserByID retrieves a user by their unique ID.
//
// It returns an error wrapping [ErrUserNotFound] if no user exists
// with the given id. Use errors.Is to check for this condition.
//
// Example:
//
//	user, err := svc.GetUserByID(ctx, "550e8400-e29b-41d4-a716-446655440000")
//	if errors.Is(err, ErrUserNotFound) {
//	    // handle not found
//	}
func (s *UserService) GetUserByID(ctx context.Context, id string) (*User, error) { ... }
```

**Rules:**
- Every exported identifier (function, type, constant, variable, package) must have a doc comment
- Comment begins with the identifier name
- Use `Example_` functions for testable examples
- Package-level comment in `doc.go`: `// Package users provides user account management.`
- Toolchain: `go doc` / pkg.go.dev (automatic on publish)

### C# / .NET (XML Doc Comments)

```csharp
/// <summary>
/// Retrieves a user by their unique identifier.
/// </summary>
/// <param name="userId">The UUID of the user. Must not be empty.</param>
/// <param name="includeDeleted">
///   Whether to include soft-deleted users. Defaults to <see langword="false"/>.
/// </param>
/// <returns>
///   The <see cref="User"/> if found; <see langword="null"/> otherwise.
/// </returns>
/// <exception cref="DatabaseException">Thrown if the database connection fails.</exception>
/// <exception cref="ArgumentException">Thrown if <paramref name="userId"/> is empty.</exception>
/// <example>
/// <code>
/// var user = await userService.GetUserByIdAsync(userId);
/// if (user is not null) Console.WriteLine(user.Email);
/// </code>
/// </example>
public async Task<User?> GetUserByIdAsync(Guid userId, bool includeDeleted = false) { ... }
```

Toolchain: DocFX 2.x; output: `_site/`

### Swift (DocC)

```swift
/// Retrieves a user by their unique identifier.
///
/// Returns `nil` if no user exists with the given `userID`.
///
/// - Parameters:
///   - userID: The unique identifier of the user.
///   - includeDeleted: Whether to include soft-deleted users. Defaults to `false`.
/// - Returns: The ``User`` if found, or `nil` otherwise.
/// - Throws: ``UserError/notFound`` if the user doesn't exist.
///           ``NetworkError`` if the request fails.
///
/// ## Topics
/// ### User Retrieval
/// - ``getUserById(_:includeDeleted:)``
/// - ``getUserByEmail(_:)``
func getUserById(_ userID: String, includeDeleted: Bool = false) async throws -> User?
```

Toolchain: DocC (Xcode); output: `.doccarchive` → interactive docs

### Dart / Flutter (Dartdoc)

```dart
/// Retrieves a user by their unique identifier.
///
/// Returns `null` if no user is found with [userId].
///
/// Throws [UserNotFoundException] if strict mode is enabled and user not found.
/// Throws [DatabaseException] if the database connection fails.
///
/// Example:
/// ```dart
/// final user = await userRepository.getUserById('abc-123');
/// if (user != null) {
///   print(user.email);
/// }
/// ```
///
/// See also:
///  * [getUserByEmail], for lookup by email address.
Future<User?> getUserById(String userId) async { ... }
```

Toolchain: `dart doc`; output: `doc/api/`

---

## OpenAPI Annotation Standards

### Annotate all REST endpoints with:
1. `operationId` — unique, camelCase, verb + noun: `getUserById`, `createOrder`
2. `summary` — one-line description (used in Swagger UI operation list)
3. `description` — detailed explanation with edge cases
4. `tags` — group by resource: `["Users"]`, `["Orders"]`
5. `security` — declare auth requirement explicitly
6. Response schemas for ALL documented status codes (200, 201, 400, 401, 403, 404, 422, 429, 500)
7. `example` values on all request/response schemas

### Common response patterns to reuse via `$ref`:
```yaml
components:
  responses:
    Unauthorized:
      description: Authentication credentials missing or invalid
      content:
        application/json:
          schema: { $ref: '#/components/schemas/ErrorResponse' }
    NotFound:
      description: Resource not found
      content:
        application/json:
          schema: { $ref: '#/components/schemas/ErrorResponse' }
  schemas:
    ErrorResponse:
      type: object
      required: [error]
      properties:
        error:
          type: object
          required: [code, message]
          properties:
            code:    { type: string, example: "USER_NOT_FOUND" }
            message: { type: string, example: "No user found with that ID" }
            details: { type: array, items: { type: string } }
```

---

## Architecture Diagram Standards

### Mermaid conventions (use for all inline diagrams)
```
Sequence diagrams: sequenceDiagram
System diagrams:   graph LR or graph TD
ERD:              erDiagram
State machines:   stateDiagram-v2
Class diagrams:   classDiagram
Timeline:         timeline (for release plans)
```

### C4 model (use for architecture overview)
- **Level 1 Context**: system + external actors — for stakeholders
- **Level 2 Container**: services, databases, message queues — for architects
- **Level 3 Component**: internal modules — for senior devs
- **Level 4 Code**: class/function level — only for complex algorithms

### Diagram quality rules
- Every diagram must have a title and legend if symbols are used
- Label all relationship arrows with the type of interaction
- Use consistent color coding: green=external, blue=internal, red=deprecated
- Diagrams must be regeneratable from code — no "draw.io" blobs in the repo

---

## Documentation Staleness Prevention

### Pre-commit check
Add to `.git/hooks/pre-commit`:
```bash
#!/usr/bin/env bash
# Warn if source changed but no doc files changed
CHANGED_SRC=$(git diff --cached --name-only | grep "^src/" | grep -v "\.test\.")
CHANGED_DOCS=$(git diff --cached --name-only | grep -E "\.(md|yaml|json)$" | grep "docs/")
if [ -n "$CHANGED_SRC" ] && [ -z "$CHANGED_DOCS" ]; then
  echo "⚠️  Source changed without documentation updates. Consider running /doc-api or /docs."
fi
```

### CI staleness gate (add to .github/workflows/ci.yml)
```yaml
- name: Check docs freshness
  run: |
    # Validate OpenAPI spec is in sync
    npx @redocly/cli lint openapi.json
    # Validate markdown links are not broken
    npx markdown-link-check docs/**/*.md --config .mlc.json
```
