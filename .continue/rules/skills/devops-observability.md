---
name: devops-observability
description: Observability standards — OpenTelemetry traces, metrics, and logs over OTLP, semantic conventions pinned to a schema version (1.44), Collector 0.161 distributions (contrib, k8s, custom ocb builds, Grafana Alloy), Collector hardening (memory_limiter, no 0.0.0.0 binds), exponential/native histograms, cardinality and telemetry cost/retention control, SLOs with burn-rate alerting, and dashboards/runbooks. Use when adding instrumentation, logging, metrics, alerts, or tracing to a service, configuring a Collector, Alloy, or Prometheus, or defining SLOs.
globs:
  - "**/otel*.y*ml"
  - "**/otelcol*.yaml"
  - "**/*.alloy"
  - "**/prometheus*.y*ml"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# Observability Standards

Telemetry design, pipelines, and alerting. Language-level logger setup lives in the language and
backend skills; cloud-native agents (ADOT, Cloud Ops, Azure Monitor) are in the cloud skills.

## Baseline (September 2026)

- OpenTelemetry semantic conventions 1.44.0; Collector releases 0.161.x.
- Prometheus 3.x: native histograms are stable (3.8+), enabled per job with
  `scrape_native_histograms: true`; the old `native-histograms` feature flag is a no-op since 3.9.
- Pin the semantic-conventions version per service: set the resource `schema_url`
  (`https://opentelemetry.io/schemas/1.44.0`) and pin the language semconv package. Import only
  stable attribute constants in production code; incubating ones can be renamed.

## OpenTelemetry first

- Instrument with OpenTelemetry SDKs and export OTLP to a Collector; the Collector, not the
  application, decides vendors, sampling, and redaction. Vendor SDKs only behind an adapter.
- Use auto-instrumentation for HTTP, gRPC, databases, and messaging; add manual spans only around
  meaningful business operations.
- Set `service.name`, `service.version`, and `deployment.environment.name` resource attributes on
  every service.
- Follow semantic conventions for attribute names (`http.request.method`, `db.system.name`,
  `messaging.system`, `gen_ai.*`) — no home-grown names for standard concepts.

## Collector

- Distribution: start with `otelcol-contrib` for exploration, `otelcol-k8s` on Kubernetes; for
  production build a minimal custom distribution with `ocb` (OpenTelemetry Collector Builder)
  containing only the components you use — smaller attack surface and image. Grafana Alloy
  (`*.alloy`) is acceptable where the Grafana stack is standard.
- Pin the Collector image by digest and upgrade monthly; read the changelog for breaking
  component changes (the project is still 0.x).
- Topology: agent (DaemonSet or sidecar) near workloads for enrichment; gateway (Deployment) for
  tail sampling, redaction, and export.
- `memory_limiter` is the first processor in every pipeline; size it below the container memory
  limit. Configure exporter `sending_queue` and retry limits so backpressure does not OOM the
  Collector.
- Bind receivers to `localhost` or the pod IP (`${env:MY_POD_IP}:4317`), never `0.0.0.0`.
  Collector 0.110+ defaults to `localhost`; examples on the web often override it — don't copy that.
- Receivers reachable beyond the node require TLS and authentication (bearer token or mTLS
  extension). Keep `pprof` and `zpages` extensions disabled or bound to localhost.
- Redact in the Collector (`attributes`/`transform`/`redaction` processors) as a second line of
  defense after application-side redaction.

Read `reference/collector.md` for a hardened agent/gateway Collector configuration.

## Traces

- Propagate W3C Trace Context (`traceparent`) across HTTP, gRPC, and message headers — including
  producers and consumers of queues.
- Record errors with `span.recordException` and set span status; do not create a span per
  function.
- Sampling: parent-based head sampling in the SDK for volume control, tail sampling in the gateway
  to keep errors and slow traces.

## Metrics

- RED for request-driven services (Rate, Errors, Duration); USE for resources (Utilization,
  Saturation, Errors).
- Latency as histograms, never averages. Prefer exponential histograms
  (`OTEL_EXPORTER_OTLP_METRICS_DEFAULT_HISTOGRAM_AGGREGATION=base2_exponential_bucket_histogram`)
  stored as Prometheus native histograms: automatic bucket resolution and far fewer series. With
  explicit buckets, bracket the SLO threshold.
- Cardinality budget: never use user ids, emails, request ids, or raw URLs as metric attributes;
  use route templates (`/orders/{id}`). Enforce with Collector filters and backend series limits.

## Logs

- Structured JSON via the service logger with `trace_id` and `span_id` for log-trace correlation;
  never `print`/`console.log`.
- Levels mean something: `error` is actionable, `warn` is degraded, `info` is business events,
  `debug` is off in production.
- Never log secrets, tokens, passwords, or unredacted PII; enforce redaction in the Collector too.

## Cost and retention

- Budget telemetry per service (GB/day, active series, spans/s) and review monthly.
- Control volume at the source first: sampling, dropping health-check spans, `debug` off, no
  per-request info logs for high-QPS endpoints.
- Tiered retention, for example: traces 7–14 days, logs 30 days hot then archive, metrics
  13 months with downsampling. Match compliance requirements explicitly.
- Alert on ingestion spikes and cardinality explosions like any other production signal.

## SLOs and alerting

- Define SLIs from the user's perspective (availability and latency of key journeys) and set SLOs
  with an explicit error budget per window.
- Alert on error-budget burn rate using multi-window rules (for example fast: 1h and 5m windows;
  slow: 6h and 30m windows), not on raw CPU or single error spikes.
- Every page-level alert links to a runbook with diagnosis steps and rollback instructions.
- Alerts that fire without requiring action are deleted or downgraded.

## Dashboards

- One service overview dashboard: SLO status, RED metrics, saturation, dependencies, recent
  deploys annotated.
- Dashboards and alert rules are code (versioned JSON/YAML or Terraform), reviewed like code.

## Security

- Telemetry pipelines carry sensitive data: TLS in transit, authenticated receivers,
  least-privilege exporter credentials from a secret store (never inline in config files).
- Restrict who can query raw logs and traces; audit access to production telemetry.

## Testing

- Validate Collector configs in CI (`otelcol validate --config=...` with the pinned binary) and
  Prometheus rules with `promtool check rules` / `promtool test rules`.
- Unit-test instrumentation with in-memory exporters; assert span names, attributes, and status.

## Post-deploy verification

- Compare error rate and p95/p99 latency against the pre-deploy baseline for the monitoring window
  defined in `agent.config.yaml`; roll back automatically on sustained regression.

_Versions verified September 2026._
