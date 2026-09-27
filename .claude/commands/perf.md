Diagnose and fix a performance problem with measurements, not guesses.

---

## Step 1: Define the target

- Restate the symptom: which operation, how slow, under what load, since when.
- Set a measurable goal (for example "p95 of `GET /orders` below 200 ms at 100 rps", "cold start
  below 1 s", "bundle below 200 kB gzipped", "job finishes in under 10 minutes").
- If no target is given, propose one based on the SLOs in `agent.config.yaml` or the architecture
  docs, and state it explicitly.

## Step 2: Measure the baseline

Reproduce the problem and capture numbers before changing code:

| Area | Tools (use what the stack provides) |
|------|------------------------------------|
| Backend latency | Traces (OpenTelemetry), request timing logs, load test (k6, Gatling, wrk, Locust) |
| CPU / memory | Profilers: `--cpu-prof` / clinic, py-spy / scalene, pprof, async-profiler / JFR, dotnet-trace, cargo flamegraph |
| Database | `EXPLAIN (ANALYZE, BUFFERS)`, slow query log, query count per request |
| Frontend | Lighthouse, Core Web Vitals (LCP, INP, CLS), bundle analyzer, React/Vue profiler |
| Mobile | Xcode Instruments, Android Studio Profiler / Macrobenchmark |

Record the baseline in the report. Never optimize without a baseline.

## Step 3: Find the bottleneck

Check the usual suspects in order of likelihood:
1. N+1 queries, missing indexes, unbounded result sets, missing pagination
2. Synchronous calls to slow dependencies in the request path; missing timeouts; sequential
   calls that could run in parallel
3. Missing or wrong caching (no cache, cache stampede, cache keys that never hit)
4. Serialization of large payloads; over-fetching fields
5. Blocking work on the event loop / main thread; lock contention
6. Algorithmic complexity (O(n²) over growing data), excessive allocation
7. Frontend: render-blocking resources, large bundles, unnecessary re-renders, unoptimized images

If `codegraph.enabled` is `true`, use `trace_path` on the hot function to see every path that
reaches it before choosing where to fix.

## Step 4: Fix one thing at a time

- Branch: `fix/perf-<slug>`.
- Apply the single change with the largest expected impact, re-measure with the same method,
  and keep it only if it moves the metric. Repeat until the target is met.
- Prefer structural fixes (index, batching, pagination, removing work) over micro-optimizations.
- Caching requires a documented invalidation strategy and TTL.
- Add a regression guard where practical: benchmark test, query-count assertion, bundle-size
  budget in CI, or a latency alert.

## Step 5: Report

```
Target:     <metric and goal>
Baseline:   <value>          After: <value>   (method: <how measured>)
Root cause: <one sentence>
Changes:    <list>
Guard:      <test / budget / alert added>
```

---

Performance problem to investigate: $ARGUMENTS
