# Worked example: one hexagonal feature with minimal APIs (.NET 10)

A "place order" feature across the four projects from SKILL.md. Implicit usings are on;
`using` directives for the solution's own namespaces and for `Microsoft.Extensions.*`
(`DependencyInjection`, `Configuration`, `Logging`) are omitted. Class libraries reference the
matching abstractions packages (`Microsoft.Extensions.DependencyInjection.Abstractions`,
`Microsoft.Extensions.Logging.Abstractions`, `Microsoft.Extensions.Options.DataAnnotations`);
the Api project gets them from the ASP.NET Core shared framework.

## Domain: shared Result type and the aggregate

```csharp
// Orders.Domain/Common/Result.cs
using System.Diagnostics.CodeAnalysis;

namespace Orders.Domain.Common;

public enum ErrorKind { Validation, NotFound, Conflict, Forbidden }

public sealed record Error(ErrorKind Kind, string Code, string Message);

public sealed class Result<T>
{
    private Result(T? value, Error? error)
    {
        Value = value;
        Error = error;
    }

    public T? Value { get; }
    public Error? Error { get; }

    [MemberNotNullWhen(true, nameof(Value))]
    [MemberNotNullWhen(false, nameof(Error))]
    public bool IsSuccess => Error is null;

    public static Result<T> Success(T value) => new(value, null);
    public static Result<T> Failure(Error error) => new(default, error);

    public static implicit operator Result<T>(T value) => Success(value);
    public static implicit operator Result<T>(Error error) => Failure(error);

    public TOut Match<TOut>(Func<T, TOut> onSuccess, Func<Error, TOut> onFailure) =>
        IsSuccess ? onSuccess(Value) : onFailure(Error);
}
```

```csharp
// Orders.Domain/Orders/Order.cs
namespace Orders.Domain.Orders;

public readonly record struct OrderId(Guid Value)
{
    public static OrderId New() => new(Guid.CreateVersion7());
}

public static class OrderErrors
{
    public static readonly Error InvalidTotal =
        new(ErrorKind.Validation, "order.invalid_total", "Order total must be positive.");
    public static readonly Error CustomerBlocked =
        new(ErrorKind.Forbidden, "order.customer_blocked", "Customer cannot place orders.");
}

public sealed class Order
{
    private Order(OrderId id, string customerId, long totalCents)
    {
        Id = id;
        CustomerId = customerId;
        TotalCents = totalCents;
    }

    public OrderId Id { get; }
    public string CustomerId { get; }
    public long TotalCents { get; }

    public static Result<Order> Create(string customerId, long totalCents) =>
        totalCents <= 0 ? OrderErrors.InvalidTotal : new Order(OrderId.New(), customerId, totalCents);
}
```

## Application: ports and handler

```csharp
// Orders.Application/Features/Orders/PlaceOrder.cs
using Microsoft.Extensions.Logging;

namespace Orders.Application.Features.Orders;

public sealed record PlaceOrderCommand(string CustomerId, long TotalCents);

public interface IOrderRepository
{
    Task AddAsync(Order order, CancellationToken ct);
}

public interface ICustomerDirectory
{
    Task<bool> IsBlockedAsync(string customerId, CancellationToken ct);
}

public interface IPlaceOrderHandler
{
    Task<Result<OrderId>> HandleAsync(PlaceOrderCommand command, CancellationToken ct);
}

public sealed class PlaceOrderHandler(
    IOrderRepository orders,
    ICustomerDirectory customers,
    ILogger<PlaceOrderHandler> logger) : IPlaceOrderHandler
{
    public async Task<Result<OrderId>> HandleAsync(PlaceOrderCommand command, CancellationToken ct)
    {
        if (await customers.IsBlockedAsync(command.CustomerId, ct))
        {
            logger.CustomerBlocked(command.CustomerId);
            return OrderErrors.CustomerBlocked;
        }

        var created = Order.Create(command.CustomerId, command.TotalCents);
        if (!created.IsSuccess)
        {
            return created.Error;
        }

        await orders.AddAsync(created.Value, ct);
        return created.Value.Id;
    }
}

internal static partial class PlaceOrderLog
{
    [LoggerMessage(Level = LogLevel.Information, Message = "Order rejected: customer {CustomerId} is blocked")]
    public static partial void CustomerBlocked(this ILogger logger, string customerId);
}

public static class OrdersApplicationServiceCollectionExtensions
{
    public static IServiceCollection AddOrdersApplication(this IServiceCollection services) =>
        services.AddScoped<IPlaceOrderHandler, PlaceOrderHandler>();
}
```

## Infrastructure: outbound adapters

```csharp
// Orders.Infrastructure/Persistence/OrdersDbContext.cs
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace Orders.Infrastructure.Persistence;

public sealed class OrdersDbContext(DbContextOptions<OrdersDbContext> options) : DbContext(options)
{
    public DbSet<Order> Orders => Set<Order>();

    protected override void OnModelCreating(ModelBuilder modelBuilder) =>
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(OrdersDbContext).Assembly);
}

internal sealed class OrderConfiguration : IEntityTypeConfiguration<Order>
{
    public void Configure(EntityTypeBuilder<Order> builder)
    {
        builder.ToTable("orders");
        builder.HasKey(o => o.Id);
        builder.Property(o => o.Id).HasConversion(id => id.Value, value => new OrderId(value));
        builder.Property(o => o.CustomerId).HasMaxLength(64).IsRequired();
        builder.Property(o => o.TotalCents).IsRequired();
    }
}

internal sealed class EfOrderRepository(OrdersDbContext db) : IOrderRepository
{
    public async Task AddAsync(Order order, CancellationToken ct)
    {
        db.Orders.Add(order);
        await db.SaveChangesAsync(ct);
    }
}
```

```csharp
// Orders.Infrastructure/Customers/CustomerDirectoryClient.cs
using System.ComponentModel.DataAnnotations;
using System.Net.Http.Json;

namespace Orders.Infrastructure.Customers;

public sealed class CustomerDirectoryOptions
{
    [Required]
    public required Uri BaseAddress { get; init; }
}

internal sealed class CustomerDirectoryClient(HttpClient http) : ICustomerDirectory
{
    public async Task<bool> IsBlockedAsync(string customerId, CancellationToken ct)
    {
        var status = await http.GetFromJsonAsync<CustomerStatus>(
            $"customers/{Uri.EscapeDataString(customerId)}/status", ct);
        // Fail closed: an unreadable status blocks the order rather than allowing it.
        return status?.IsBlocked ?? true;
    }

    private sealed record CustomerStatus(bool IsBlocked);
}
```

```csharp
// Orders.Infrastructure/OrdersInfrastructureServiceCollectionExtensions.cs
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace Orders.Infrastructure;

public static class OrdersInfrastructureServiceCollectionExtensions
{
    public static IServiceCollection AddOrdersInfrastructure(
        this IServiceCollection services, IConfiguration configuration)
    {
        services.AddDbContext<OrdersDbContext>(options =>
            options.UseNpgsql(configuration.GetConnectionString("Orders")));
        services.AddScoped<IOrderRepository, EfOrderRepository>();

        services.AddOptions<CustomerDirectoryOptions>()
            .Bind(configuration.GetSection("CustomerDirectory"))
            .ValidateDataAnnotations()
            .ValidateOnStart();
        services.AddHttpClient<ICustomerDirectory, CustomerDirectoryClient>((sp, client) =>
                client.BaseAddress = sp.GetRequiredService<IOptions<CustomerDirectoryOptions>>().Value.BaseAddress)
            .AddStandardResilienceHandler();

        return services;
    }
}
```

## Api: endpoint, error mapping, composition root

```csharp
// Orders.Api/Features/Orders/PlaceOrderEndpoint.cs
using System.ComponentModel.DataAnnotations;
using System.Security.Claims;
using Microsoft.AspNetCore.Http.HttpResults;

namespace Orders.Api.Features.Orders;

public sealed record PlaceOrderRequest([Range(1, int.MaxValue)] int TotalCents);

public sealed record PlaceOrderResponse(Guid OrderId);

public static class PlaceOrderEndpoint
{
    public static RouteGroupBuilder MapPlaceOrder(this RouteGroupBuilder group)
    {
        group.MapPost("/", HandleAsync)
            .WithName("PlaceOrder")
            .WithSummary("Places an order for the authenticated customer.");
        return group;
    }

    internal static async Task<Results<Created<PlaceOrderResponse>, ProblemHttpResult>> HandleAsync(
        PlaceOrderRequest request, ClaimsPrincipal user, IPlaceOrderHandler handler, CancellationToken ct)
    {
        // The customer comes from the token, never from the request body.
        var customerId = user.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? throw new InvalidOperationException("Authenticated principal has no identifier claim.");

        var result = await handler.HandleAsync(new PlaceOrderCommand(customerId, request.TotalCents), ct);

        return result.Match<Results<Created<PlaceOrderResponse>, ProblemHttpResult>>(
            orderId => TypedResults.Created($"/orders/{orderId.Value}", new PlaceOrderResponse(orderId.Value)),
            error => error.ToProblem());
    }
}
```

```csharp
// Orders.Api/ErrorHttpMapping.cs
using Microsoft.AspNetCore.Http.HttpResults;

namespace Orders.Api;

internal static class ErrorHttpMapping
{
    public static ProblemHttpResult ToProblem(this Error error) => TypedResults.Problem(
        title: error.Message,
        statusCode: error.Kind switch
        {
            ErrorKind.Validation => StatusCodes.Status400BadRequest,
            ErrorKind.NotFound => StatusCodes.Status404NotFound,
            ErrorKind.Conflict => StatusCodes.Status409Conflict,
            ErrorKind.Forbidden => StatusCodes.Status403Forbidden,
            _ => StatusCodes.Status500InternalServerError,
        },
        extensions: new Dictionary<string, object?> { ["code"] = error.Code });
}
```

```csharp
// Orders.Api/UnhandledExceptionHandler.cs
using Microsoft.AspNetCore.Diagnostics;

namespace Orders.Api;

internal sealed partial class UnhandledExceptionHandler(
    IProblemDetailsService problemDetails,
    ILogger<UnhandledExceptionHandler> logger) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext, Exception exception, CancellationToken cancellationToken)
    {
        LogUnhandled(logger, exception, httpContext.Request.Path);
        httpContext.Response.StatusCode = StatusCodes.Status500InternalServerError;
        return await problemDetails.TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = httpContext,
            ProblemDetails = { Title = "An unexpected error occurred." },
        });
    }

    [LoggerMessage(Level = LogLevel.Error, Message = "Unhandled exception for {Path}")]
    private static partial void LogUnhandled(ILogger logger, Exception exception, string path);
}
```

```csharp
// Orders.Api/Program.cs
using Microsoft.AspNetCore.Authorization;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddProblemDetails();
builder.Services.AddExceptionHandler<UnhandledExceptionHandler>();
builder.Services.AddValidation();
builder.Services.AddOpenApi();
builder.Services.AddAuthentication().AddJwtBearer();
builder.Services.AddAuthorizationBuilder()
    .SetFallbackPolicy(new AuthorizationPolicyBuilder().RequireAuthenticatedUser().Build());

builder.Services.AddOrdersApplication();
builder.Services.AddOrdersInfrastructure(builder.Configuration);

var app = builder.Build();

app.UseExceptionHandler();
app.UseHttpsRedirection();
app.UseAuthentication();
app.UseAuthorization();

app.MapOpenApi();
app.MapGroup("/orders").RequireAuthorization().MapPlaceOrder();

app.Run();

public partial class Program;
```

`AddJwtBearer` needs the `Microsoft.AspNetCore.Authentication.JwtBearer` package (same version as
the other 10.0.x ASP.NET Core packages); the authority and audience come from configuration
(`Authentication:Schemes:Bearer:*`), not code.

## Tests

Unit test — no host, NSubstitute for ports, Shouldly assertions:

```csharp
using Microsoft.Extensions.Logging.Abstractions;
using NSubstitute;
using Shouldly;

public sealed class PlaceOrderHandlerTests
{
    private readonly IOrderRepository _orders = Substitute.For<IOrderRepository>();
    private readonly ICustomerDirectory _customers = Substitute.For<ICustomerDirectory>();

    [Fact]
    public async Task HandleAsync_BlockedCustomer_ReturnsCustomerBlocked()
    {
        _customers.IsBlockedAsync("c-1", Arg.Any<CancellationToken>()).Returns(true);
        var handler = new PlaceOrderHandler(_orders, _customers, NullLogger<PlaceOrderHandler>.Instance);

        var result = await handler.HandleAsync(
            new PlaceOrderCommand("c-1", 1_500), TestContext.Current.CancellationToken);

        result.Error.ShouldBe(OrderErrors.CustomerBlocked);
        await _orders.DidNotReceiveWithAnyArgs().AddAsync(default!, default);
    }
}
```

Integration test — real app, real PostgreSQL:

```csharp
using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Shouldly;
using Testcontainers.PostgreSql;

public sealed class OrdersApiFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly PostgreSqlContainer _db = new PostgreSqlBuilder("postgres:18-alpine").Build();

    public async ValueTask InitializeAsync()
    {
        await _db.StartAsync();
        using var scope = Services.CreateScope();
        await scope.ServiceProvider.GetRequiredService<OrdersDbContext>().Database.MigrateAsync();
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseSetting("ConnectionStrings:Orders", _db.GetConnectionString());
        builder.UseSetting("CustomerDirectory:BaseAddress", "http://customers.test/");
    }

    public override async ValueTask DisposeAsync()
    {
        await _db.DisposeAsync();
        await base.DisposeAsync();
    }
}

public sealed class OrdersApiTests(OrdersApiFactory factory) : IClassFixture<OrdersApiFactory>
{
    [Fact]
    public async Task PlaceOrder_WithoutToken_ReturnsUnauthorized()
    {
        using var client = factory.CreateClient();

        var response = await client.PostAsJsonAsync(
            "/orders", new { totalCents = 1_500 }, TestContext.Current.CancellationToken);

        response.StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
    }
}
```

Replace the customer directory with a fake in `ConfigureWebHost` (`services.RemoveAll<ICustomerDirectory>()`
then register a stub) and add a test authentication handler when exercising authorized paths.
