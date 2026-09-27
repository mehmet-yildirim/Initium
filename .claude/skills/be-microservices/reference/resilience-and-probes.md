# Resilience, probes, and SLO alerting — configuration examples

Read when configuring an HTTP client pipeline, Kubernetes probes, or SLO alerts for a service.

## .NET: standard resilience handler (Polly v8 underneath)

```csharp
builder.Services
    .AddHttpClient<IInventoryClient, InventoryHttpClient>(client =>
    {
        client.BaseAddress = builder.Configuration.GetValue<Uri>("Inventory:BaseUrl")
            ?? throw new InvalidOperationException("Inventory:BaseUrl is not configured.");
    })
    .AddStandardResilienceHandler(options =>
    {
        // The default retries every method; unsafe calls would be duplicated on retry.
        options.Retry.DisableForUnsafeHttpMethods();
        options.Retry.MaxRetryAttempts = 3;
        options.AttemptTimeout.Timeout = TimeSpan.FromSeconds(2);
        options.TotalRequestTimeout.Timeout = TimeSpan.FromSeconds(8);
        options.CircuitBreaker.SamplingDuration = TimeSpan.FromSeconds(30);
    });
```

- The pipeline order is rate limiter → total timeout → retry → circuit breaker → attempt timeout.
- The handler sets `HttpClient.Timeout` to infinite so the strategies own timeouts; do not set it
  back.
- Options are validated at startup: the circuit-breaker sampling duration must be at least twice
  the attempt timeout.
- `IInventoryClient` is the port; `InventoryHttpClient` is the adapter. Domain code never sees
  `HttpClient`.

## JVM and Go equivalents

- Resilience4j: compose `TimeLimiter`, `Retry` (exponential random backoff), `CircuitBreaker`
  (sliding window, failure-rate threshold), and `Bulkhead` around the adapter call; export metrics
  through Micrometer.
- Go: `failsafe-go` composes retry, circuit breaker, timeout, bulkhead, and rate limiter policies
  in one executor; `sony/gobreaker/v2` is a minimal circuit breaker when that is all you need.
  Always pass `context.Context` with a deadline to the HTTP/gRPC call.

## Kubernetes probes aligned with the health endpoints

```yaml
spec:
  terminationGracePeriodSeconds: 30
  containers:
    - name: orders
      ports:
        - name: http
          containerPort: 8080
      startupProbe:
        httpGet: { path: /health/startup, port: http }
        periodSeconds: 5
        failureThreshold: 30        # up to 150 s to initialize
      livenessProbe:
        httpGet: { path: /health/live, port: http }
        periodSeconds: 10
        failureThreshold: 3
      readinessProbe:
        httpGet: { path: /health/ready, port: http }
        periodSeconds: 5
        failureThreshold: 2
```

- Liveness and readiness start only after the startup probe succeeds, so liveness can stay strict
  without killing slow-starting pods.
- The application's shutdown drain deadline must be shorter than `terminationGracePeriodSeconds`.

## SLO burn-rate alerts (30-day window)

Multi-window, multi-burn-rate alerting from the Google SRE Workbook. Burn rate 1 spends exactly
the error budget over the SLO window.

| Severity | Long window | Short window | Burn rate | Budget spent when it fires |
|---|---|---|---|---|
| Page | 1 h | 5 min | 14.4 | 2% |
| Page | 6 h | 30 min | 6 | 5% |
| Ticket | 3 d | 6 h | 1 | 10% |

Both windows must exceed the threshold; the short window makes the alert reset quickly after
recovery. For a 99.9% availability SLO (error budget 0.001), the first page rule in PromQL, using
recording rules for the error ratio:

```promql
(
  slo:request_errors:ratio_rate1h{service="orders"} > (14.4 * 0.001)
and
  slo:request_errors:ratio_rate5m{service="orders"} > (14.4 * 0.001)
)
```

Pair availability SLOs with latency SLOs (share of requests under a threshold) using the same
rule shape. Define SLOs per user journey, not per pod.
