---
name: devops-observability
description: Observability standards — OpenTelemetry traces, metrics, and logs with OTLP and the Collector, semantic conventions, context propagation, cardinality control, SLOs with burn-rate alerting, and dashboards/runbooks. Use when adding instrumentation, logging, metrics, alerts, or tracing to a service, or when defining SLOs.
globs:
  - "**/otel*.yaml"
  - "**/otel*.yml"
  - "**/*collector*.yaml"
  - "**/prometheus*.yml"
  - "**/alerts/**"
  - "**/dashboards/**"
  - "**/instrumentation.*"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# Observability Standards

## OpenTelemetry first

- Instrument with OpenTelemetry SDKs and export OTLP to an OpenTelemetry Collector; the
  Collector, not the application, decides vendors, sampling, and redaction.
- Use auto-instrumentation for HTTP, gRPC, databases, and messaging; add manual spans only
  around meaningful business operations.
- Set `service.name`, `service.version`, and `deployment.environment.name` resource attributes
  on every service.
- Follow OpenTelemetry semantic conventions for attribute names (`http.request.method`,
  `db.system.name`, `messaging.system`, `gen_ai.*`) — no home-grown names for standard concepts.

## Traces

- Propagate W3C Trace Context (`traceparent`) across HTTP, gRPC, and message headers — including
  producers and consumers of queues.
- Record errors with `span.recordException` and set span status; do not create a span per
  function.
- Sampling: head-based in the SDK for volume control, tail-based in the Collector to keep
  errors and slow traces.

## Metrics

- RED for request-driven services (Rate, Errors, Duration); USE for resources (Utilization,
  Saturation, Errors).
- Histograms for latency, never averages. Choose buckets that bracket the SLO threshold.
- Cardinality budget: never use user ids, emails, request ids, or raw URLs as metric labels;
  use route templates (`/orders/{id}`).

## Logs

- Structured JSON with `trace_id` and `span_id` injected for log-trace correlation.
- Levels mean something: `error` is actionable, `warn` is degraded, `info` is business events,
  `debug` is off in production.
- Never log secrets, tokens, passwords, or unredacted PII; enforce redaction in the Collector too.

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

## Post-deploy verification

- Compare error rate and p95/p99 latency against the pre-deploy baseline for the monitoring window
  defined in `agent.config.yaml`; roll back automatically on sustained regression.
