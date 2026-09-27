---
name: lang-dotnet
description: C# and .NET standards for .NET 10 LTS and C# 14 — ASP.NET Core minimal APIs with TypedResults and built-in validation, hexagonal feature folders, EF Core 10, analyzers with TreatWarningsAsErrors, Central Package Management, NuGetAudit, .slnx solutions, source-generated logging, OpenTelemetry, HTTP resilience, and xUnit v3 on Microsoft Testing Platform with Testcontainers. Use when writing, reviewing, or configuring C# code, .csproj/.slnx files, Directory.*.props, global.json, or ASP.NET Core services.
globs:
  - "**/*.cs"
  - "**/*.csproj"
  - "**/*.slnx"
  - "**/*.sln"
  - "**/*.razor"
  - "**/Directory.Build.props"
  - "**/Directory.Packages.props"
  - "**/global.json"
  - "**/appsettings*.json"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# C# / .NET Standards

Covers the language, ASP.NET Core services, EF Core, and .NET builds. Container and pipeline
rules are in `devops-docker` and `devops-cicd`; Azure specifics are in `devops-azure`.

## Baseline

- Target **.NET 10 LTS** (`net10.0`, supported until 14 November 2028) with **C# 14** (the default
  for `net10.0`; do not set `LangVersion` to `preview`).
- .NET 8 and .NET 9 reach end of support on 10 November 2026 — migrate them now.
  .NET 11 (November 2026) is STS; stay on 10 unless there is a specific need.
- Pin the SDK in `global.json` (`"rollForward": "latestFeature"`) and set the test runner there
  (see Testing).
- New solutions use **`.slnx`** (the `dotnet new sln` default since .NET 10). Convert old files
  with `dotnet sln migrate`.

## Toolchain

- **Build settings** live in `Directory.Build.props` at the repo root, not per project:
  `Nullable=enable`, `ImplicitUsings=enable`, `TreatWarningsAsErrors=true`,
  `AnalysisLevel=latest-recommended`, `EnforceCodeStyleInBuild=true`.
- **Central Package Management:** every version lives in `Directory.Packages.props`
  (`ManagePackageVersionsCentrally=true`); `.csproj` files carry `<PackageReference>` without
  versions. Enable `RestorePackagesWithLockFile` and run `dotnet restore --locked-mode` in CI.
- **Vulnerability scanning:** NuGetAudit is on by default and audits transitive packages
  (`NuGetAuditMode=all`) for `net10.0`. With warnings as errors, a vulnerable package fails the
  restore — fix it, or suppress one advisory with `<NuGetAuditSuppress>` plus a linked issue.
- **Format:** `.editorconfig` holds naming and style rules; CI runs
  `dotnet format --verify-no-changes`.
- **Analyzers:** the built-in .NET analyzers at `latest-recommended`, plus `xunit.analyzers` in
  test projects. Suppress individual rules in `.editorconfig` with a reason, never with
  blanket `#pragma warning disable`.
- **Licensing check:** before adding a package, check its license. MediatR (v13+) and
  AutoMapper (v15+) are commercially licensed; FluentAssertions v8+ requires a paid license
  for commercial use.

Read `reference/build-and-packages.md` when creating or reviewing `Directory.Build.props`,
`Directory.Packages.props`, `global.json`, or CI build steps.

## Style and naming

- Types, methods, properties, events, constants: `PascalCase` (C# convention; constants are not
  SCREAMING_SNAKE). Interfaces: `I` prefix. Private fields: `_camelCase`. Locals and
  parameters: `camelCase`. Async methods end in `Async`.
- Allman braces, 4-space indent, file-scoped namespaces, one top-level type per file.
- `var` when the type is obvious from the right-hand side; explicit type otherwise.
- Records for DTOs and value objects; `required` + `init` for mandatory properties; primary
  constructors for simple dependency capture (assign to a `readonly` field if mutation must be
  prevented — primary constructor parameters are mutable).
- C# 14: use extension members (`extension(T receiver) { ... }`) for extension properties, the
  `field` keyword to add logic to auto-properties, and null-conditional assignment
  (`order?.Status = ...`) where it removes a null-check block.

## Structure

Feature folders, each hexagonal. Dependencies point inward: adapters → application → domain.

```
src/
├── Orders.Api/                 # composition root: Program.cs, endpoint mapping, DI wiring
│   └── Features/Orders/        # endpoints (inbound adapter) + request/response records
├── Orders.Application/
│   └── Features/Orders/        # use-case handlers, ports (IOrderRepository, IPaymentGateway)
├── Orders.Domain/              # entities, value objects, domain errors — no package references
└── Orders.Infrastructure/      # outbound adapters: EF Core DbContext, HTTP clients, vendor SDKs
tests/
├── Orders.UnitTests/
└── Orders.IntegrationTests/
```

- Separate projects make the compiler enforce the dependency direction. A small service may use
  one project with the same folders plus an architecture test (NetArchTest or ArchUnitNET).
- The domain references no NuGet packages and no ASP.NET/EF types.
- Vendor SDKs (payments, email, cloud storage) are wrapped in Infrastructure classes that
  implement Application ports. Endpoints never call them directly.
- Use-case handlers are plain classes behind an interface, registered in DI. A mediator is
  optional; if you want one, use the MIT-licensed source-generated `Mediator` package
  (`Mediator.SourceGenerator` + `Mediator.Abstractions`) — not MediatR without a license.
- Group DI registration per feature in extension methods (`services.AddOrdersFeature()`).
- Configuration: `IOptions<T>` bound from configuration and validated on start
  (`.ValidateDataAnnotations().ValidateOnStart()`); never inject `IConfiguration` into
  handlers.

## Minimal APIs

- Return `TypedResults` and declare the union in the signature (`Results<Ok<T>, NotFound>`) so
  OpenAPI metadata and unit tests come for free. Never return domain entities.
- Validation: `builder.Services.AddValidation()` validates Data Annotations on parameters and
  records and returns a 400 `ProblemDetails` automatically. Call it from the assembly that
  defines the endpoints (the source generator is assembly-scoped). Use FluentValidation only
  for rules annotations cannot express.
- OpenAPI: `builder.Services.AddOpenApi()` + `app.MapOpenApi()`. `.WithOpenApi()` is deprecated
  in .NET 10 (ASPDEPR002); customize operations with `AddOpenApiOperationTransformer` or
  `.WithSummary()`/`.WithDescription()`.
- Group routes with `MapGroup("/orders").RequireAuthorization()`.

```csharp
public static class GetOrderEndpoint
{
    public static RouteGroupBuilder MapGetOrder(this RouteGroupBuilder group)
    {
        group.MapGet("/{id:guid}", HandleAsync).WithName("GetOrder");
        return group;
    }

    private static async Task<Results<Ok<OrderResponse>, NotFound>> HandleAsync(
        Guid id, ClaimsPrincipal user, IGetOrderHandler handler, CancellationToken ct)
    {
        // Scope the lookup to the caller so another customer's order id returns 404 (no IDOR).
        var customerId = user.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? throw new InvalidOperationException("Authenticated principal has no identifier claim.");
        var order = await handler.HandleAsync(new GetOrderQuery(id, customerId), ct);
        return order is null ? TypedResults.NotFound() : TypedResults.Ok(OrderResponse.From(order));
    }
}
```

## Errors

- Expected failures are values: handlers return `Result<T>` (one small in-house type in the
  shared kernel carrying a typed `Error` with a code) — one approach across the codebase.
  Do not mix `OneOf`, `FluentResults`, and exceptions for the same purpose.
- Exceptions are for bugs and invariant violations (typed domain exceptions), never control flow.
- Map `Error` codes to `TypedResults`/`ProblemDetails` at the endpoint. Unexpected exceptions go
  through one `IExceptionHandler` + `AddProblemDetails()`; production responses never contain
  stack traces.
- Never catch `Exception` without logging and rethrowing or translating.

Read `reference/minimal-api-feature.md` when implementing a feature end to end (Result type,
handler, port, EF adapter, endpoint mapping, and tests).

## EF Core 10

- EF Core lives in Infrastructure. Configure mappings with `IEntityTypeConfiguration<T>`.
- Migrations are reviewed, tested in CI, and applied by the pipeline with a migration bundle
  (`dotnet ef migrations bundle`) — never `Database.EnsureCreated()` or `Migrate()` on app start
  in production.
- No lazy loading. Use projections (`Select`) or `Include` + `AsSplitQuery()`; `AsNoTracking()`
  for reads; `ExecuteUpdateAsync`/`ExecuteDeleteAsync` for set-based writes.
- Raw SQL only through `FromSql($"... {param}")` / `SqlQuery` (interpolation is parameterized).
  Never `FromSqlRaw` with concatenated input.

## Async and concurrency

- All I/O is `async`; never `.Result`, `.Wait()`, or `async void` (except event handlers).
- Every public async method accepts a `CancellationToken` and passes it down.
- `ConfigureAwait(false)` in reusable libraries; not needed in ASP.NET Core app code.
- `Task.WhenAll` for independent calls; `Channel<T>` for producer/consumer; `BackgroundService`
  for in-process workers, and a durable queue for work that must survive restarts.
- Outbound HTTP via `IHttpClientFactory` typed clients with `AddStandardResilienceHandler()`
  (Microsoft.Extensions.Http.Resilience) for timeouts, retries, and circuit breaking.

## Security

- Authentication (`AddAuthentication().AddJwtBearer()` or OIDC) and authorization policies; set
  a fallback policy that requires an authenticated user so endpoints are denied by default.
- Authorize resources in the handler using the caller's identity from `ClaimsPrincipal`, never
  an id from the request body.
- `UseHttpsRedirection()` + `UseHsts()`; built-in rate limiting (`AddRateLimiter`) on auth and
  expensive endpoints; antiforgery for cookie-authenticated form posts.
- Secrets: `dotnet user-secrets` locally; Azure Key Vault / AWS Secrets Manager / environment
  variables in deployed environments. Never commit secrets to `appsettings*.json`.
- Never deserialize untrusted data with `BinaryFormatter` (removed) or polymorphic
  `TypeNameHandling`; use `System.Text.Json` with source-generated contexts.

## Observability

- `ILogger<T>` only — never `Console.WriteLine`. Use source-generated `[LoggerMessage]` methods
  for hot paths and structured properties (`{OrderId}`), never string interpolation in
  templates.
- JSON console logs in production (`builder.Logging.AddJsonConsole()`) or OTLP log export.
  Never log tokens, passwords, or PII.
- OpenTelemetry traces, metrics, and logs with OTLP export: Aspire ServiceDefaults
  (`builder.AddServiceDefaults()`) or the `OpenTelemetry.Extensions.Hosting` +
  `OpenTelemetry.Instrumentation.AspNetCore`/`.Http` + `OpenTelemetry.Exporter.OpenTelemetryProtocol`
  packages directly. Configure the endpoint with `OTEL_EXPORTER_OTLP_ENDPOINT`.
- Health checks via `AddHealthChecks()` + `MapHealthChecks`: a readiness endpoint that checks
  dependencies and a liveness endpoint that does not. Aspire's `MapDefaultEndpoints()` maps them
  only in Development by default — map them explicitly for production probes.

## Testing

- **xUnit v3** (`xunit.v3` package, Core Framework 4.0.x) on **Microsoft Testing Platform**:
  set `"test": { "runner": "Microsoft.Testing.Platform" }` in `global.json`, then run
  `dotnet test`. MTP filters use xUnit options (`--filter-class`, `--filter-trait`), not VSTest
  `--filter` syntax.
- Mocks: NSubstitute for ports (or hand-written fakes). Assertions: xUnit `Assert`, Shouldly
  (BSD-3), AwesomeAssertions (Apache-2.0 fork of FluentAssertions), or FluentAssertions pinned
  to 7.x. Never add FluentAssertions 8+ without a commercial license.
- Unit tests: handlers and domain without a host. Endpoint handlers can be unit tested directly
  because they return `TypedResults`.
- Integration tests: `WebApplicationFactory<Program>` + Testcontainers (`Testcontainers.PostgreSql`)
  against the real database engine; never the EF in-memory provider as a stand-in.
- Test names: `Method_State_ExpectedResult`. Build data with small builders; `[Theory]` +
  `[MemberData]`/`TheoryData<T>` for data-driven cases.

_Versions verified September 2026._
