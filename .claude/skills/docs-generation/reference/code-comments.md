# Doc comments per language

Same contract everywhere: purpose, every parameter, return value, every error, one runnable
example for non-trivial public APIs, cross-references. Examples use the project logger, typed
errors, and placeholder data.

## TypeScript / JavaScript — TSDoc + TypeDoc 0.28

```typescript
/**
 * Retrieves a user by their unique ID.
 *
 * @param userId - UUID of the user to retrieve.
 * @param options - Query options.
 * @param options.includeDeleted - Include soft-deleted users. Defaults to `false`.
 * @returns The user, or `null` if none exists.
 * @throws {@link ValidationError} If `userId` is not a valid UUID.
 * @throws {@link DatabaseError} If the database is unreachable.
 *
 * @example
 * ```ts
 * const user = await userService.getById('550e8400-e29b-41d4-a716-446655440000');
 * if (user) logger.info({ userId: user.id }, 'user found');
 * ```
 *
 * @see {@link createUser}
 */
export async function getUserById(
  userId: string,
  options?: { includeDeleted?: boolean },
): Promise<User | null> { /* ... */ }
```

- Generator: TypeDoc 0.28 (`typedoc.json` with `entryPoints`, `out: docs/reference/api`,
  `treatWarningsAsErrors: true` in CI). Check its supported TypeScript range before upgrading TS.
- Lint TSDoc syntax with `eslint-plugin-tsdoc`.

## Python — Google-style docstrings

```python
def get_user_by_id(user_id: str, *, include_deleted: bool = False) -> User | None:
    """Retrieve a user by their unique ID.

    Args:
        user_id: UUID of the user to retrieve.
        include_deleted: Include soft-deleted users. Defaults to False.

    Returns:
        The user if found, otherwise None.

    Raises:
        ValidationError: If ``user_id`` is not a valid UUID.
        DatabaseError: If the database is unreachable.

    Example:
        >>> get_user_by_id("550e8400-e29b-41d4-a716-446655440000") is None
        True
    """
```

- Generator: Sphinx (`autodoc` + `napoleon`) or mkdocstrings. Run doctests
  (`pytest --doctest-modules`). Enforce coverage with `interrogate` or Ruff `D` rules.

## Java — Javadoc

```java
/**
 * Retrieves a user by their unique ID.
 *
 * <p>Soft-deleted users are excluded unless {@code includeDeleted} is {@code true}.
 *
 * {@snippet :
 * Optional<User> user = users.getUserById(id, false);
 * }
 *
 * @param userId the user's UUID; must not be null
 * @param includeDeleted whether to include soft-deleted users
 * @return the user, or an empty {@link Optional} if none exists
 * @throws DatabaseException if the database is unreachable
 * @since 1.0
 */
public Optional<User> getUserById(UUID userId, boolean includeDeleted) { /* ... */ }
```

- Use `{@snippet}` (JDK 18+) instead of `<pre>{@code}</pre>`; external snippet files can be
  compiled. Run `javadoc -Xdoclint:all` in CI.

## Kotlin — KDoc + Dokka 2

```kotlin
/**
 * Retrieves a user by their unique ID.
 *
 * @param userId the user's UUID
 * @param includeDeleted include soft-deleted users; defaults to `false`
 * @return the [User], or `null` if none exists
 * @throws DatabaseException if the database is unreachable
 * @sample com.example.users.UserSamples.getUserById
 */
suspend fun getUserById(userId: UUID, includeDeleted: Boolean = false): User?
```

- Dokka 2.x with the v2 Gradle plugin (default since 2.1): `./gradlew :module:dokkaGenerate`.

## Go — doc comments

```go
// GetUserByID retrieves a user by their unique ID.
//
// It returns an error wrapping [ErrUserNotFound] if no user exists; check it with
// [errors.Is].
func (s *UserService) GetUserByID(ctx context.Context, id string) (*User, error)
```

- Start with the identifier name; use `[Name]` doc links; package comment in `doc.go`.
- Runnable examples: `func ExampleUserService_GetUserByID()` with an `// Output:` block.

## C# — XML doc comments

```csharp
/// <summary>Retrieves a user by their unique identifier.</summary>
/// <param name="userId">The user's ID. Must not be empty.</param>
/// <param name="includeDeleted">Include soft-deleted users.</param>
/// <returns>The <see cref="User"/> if found; otherwise <see langword="null"/>.</returns>
/// <exception cref="ArgumentException"><paramref name="userId"/> is empty.</exception>
public Task<User?> GetUserByIdAsync(Guid userId, bool includeDeleted = false);
```

- `<GenerateDocumentationFile>true</GenerateDocumentationFile>` and treat CS1591 as a warning on
  public APIs; publish with DocFX.

## Swift — DocC

```swift
/// Retrieves a user by their unique identifier.
///
/// - Parameters:
///   - userID: The user's identifier.
///   - includeDeleted: Whether to include soft-deleted users.
/// - Returns: The ``User`` if found, or `nil`.
/// - Throws: ``UserError/notFound`` if the user doesn't exist.
func user(withID userID: String, includeDeleted: Bool = false) async throws -> User?
```

- `## Topics` groups belong in type-level comments, articles, or extension files in the `.docc`
  catalog — not in a function's comment.
- Build with `xcodebuild docbuild` or `swift package generate-documentation` (Swift-DocC plugin).

## Dart — dartdoc

```dart
/// Retrieves a user by their unique identifier.
///
/// Returns `null` if no user matches [userId].
/// Throws [DatabaseException] if the database is unreachable.
///
/// See also:
///  * [getUserByEmail], for lookup by email address.
Future<User?> getUserById(String userId) async { /* ... */ }
```

- `dart doc` outputs to `doc/api/`; enable the `public_member_api_docs` lint for packages.
