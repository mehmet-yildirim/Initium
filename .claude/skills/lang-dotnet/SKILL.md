---
name: lang-dotnet
description: .NET / C# development standards — ASP.NET Core, EF Core, xUnit, clean architecture. Use when writing or reviewing C# / .NET code.
paths:
  - "**/*.cs"
  - "**/*.csproj"
  - "**/*.sln"
  - "**/*.razor"
  - "**/appsettings*.json"
---

# .NET / C# Development Standards

## Code Style
- Follow Microsoft C# Coding Conventions and .editorconfig
- Indent: 4 spaces
- Braces: Allman style (opening brace on its own line) for types and methods
- Prefer expression-bodied members for single-expression properties / methods
- `var` for local variables when the type is obvious from the right-hand side; explicit type otherwise
- Nullable reference types enabled: `<Nullable>enable</Nullable>` in all projects

## Naming Conventions
- Classes / Interfaces / Enums / Methods / Properties: `PascalCase`
- Interface prefix: `I` (e.g., `IUserRepository`)
- Private fields: `_camelCase` (underscore prefix)
- Local variables / parameters: `camelCase`
- Constants: `PascalCase` (not SCREAMING — C# convention)
- Async methods: suffix with `Async` (e.g., `GetUserAsync`)
- Generic type parameters: `T`, `TEntity`, `TResult`

## ASP.NET Core Conventions
- Use minimal APIs (`.NET 8+`) for new services; MVC for complex UI or CRUD-heavy apps
- Dependency injection via constructor — NEVER `ServiceLocator` or static access
- Register dependencies in `Program.cs`; group by feature using extension methods
- `IOptions<T>` for typed configuration binding — never `IConfiguration` directly in services
- Middleware: register in correct order (Auth before Authorization, etc.)
- Use `ILogger<T>` — never `Console.WriteLine` in production code
- Return `Results.Ok()` / `TypedResults.*` from minimal API endpoints for testability

```csharp
// Preferred: minimal API with typed results
app.MapGet("/users/{id}", async (Guid id, IUserService userService) =>
{
    var user = await userService.GetByIdAsync(id);
    return user is null ? Results.NotFound() : Results.Ok(user);
})
.WithName("GetUser")
.WithOpenApi();
```

## Architecture — Clean Architecture
```
API / Presentation layer (Controllers / Endpoints)
    ↓
Application layer (Use Cases, Commands, Queries — MediatR)
    ↓
Domain layer (Entities, Value Objects, Domain Services, Repository interfaces)
    ↓
Infrastructure layer (EF Core, HTTP clients, external services)
```
- Domain has zero external dependencies
- Use CQRS with MediatR: `ICommand<T>` / `IQuery<T>` with handlers
- DTOs / Records for input/output; never expose domain entities to API layer
- Use Result pattern (`Result<T>` / `OneOf`) rather than exceptions for expected failures

## Entity Framework Core
- Code-first with Fluent API configuration in `IEntityTypeConfiguration<T>` classes
- Migrations: always code-reviewed, tested in CI, applied via pipeline (never `Ensure-Created` in prod)
- No lazy loading — use explicit includes or projection queries
- Avoid N+1: use `Include()`, `AsSplitQuery()`, or projections with `Select()`
- Repository pattern over naked DbContext in application/domain layers
- `AsNoTracking()` for read-only queries

## Error Handling
- Use `Result<T>` / `FluentResults` for business errors — avoid exceptions for flow control
- Global error handling via `IExceptionHandler` (.NET 8+) or `UseExceptionHandler` middleware
- `ProblemDetails` (RFC 9457) for all HTTP error responses
- Never expose stack traces or internal details in production error responses
- Domain exceptions for invariant violations only

## Testing (xUnit + Moq/NSubstitute + FluentAssertions)
- Unit tests: no ASP.NET host; mock all dependencies with NSubstitute
- Integration tests: `WebApplicationFactory<Program>` + Testcontainers for real DB
- Use `FluentAssertions` for readable assertions
- Test naming: `MethodName_StateUnderTest_ExpectedBehavior()` or `Should_DoX_When_Y()`
- `AutoFixture` for generating test data; custom builders for complex aggregates
- Avoid `[Theory]` with inline data for complex scenarios — use typed test data classes

## C# Modern Features (C# 12 / .NET 8+)
- Records for immutable DTOs and value objects
- Primary constructors for simple DI scenarios
- Pattern matching, switch expressions over long if/else chains
- Collection expressions `[item1, item2]`
- Required members on DTOs: `public required string Name { get; init; }`
- `IAsyncEnumerable<T>` for streaming results
- `CancellationToken` propagated through all async chains — never ignored

## Async / Concurrency
- All I/O operations must be `async/await` — no `.Result` or `.Wait()` (deadlock risk)
- `ConfigureAwait(false)` in library code
- `CancellationToken` parameter on all public async methods
- Use `Task.WhenAll` for parallel independent operations
- `Channel<T>` or `System.Threading.Channels` for producer/consumer patterns

## Security
- No string interpolation into SQL — use EF Core parameterized queries always
- Anti-forgery tokens for all state-changing form submissions
- HTTPS enforced: `UseHttpsRedirection()` + HSTS
- Input validation: Data Annotations + FluentValidation at API boundary
- Secrets: `dotnet user-secrets` for local dev; Azure Key Vault / AWS Secrets Manager for production
- Never store secrets in `appsettings.json` committed to source control
