# Hardened Collector configuration (gateway)

Gateway Collector on Kubernetes (`otelcol-k8s` or a custom `ocb` build with the same
components). Agents forward OTLP to it over TLS with a bearer token. Secrets and endpoints come
from environment variables injected from Kubernetes Secrets — never inline.

```yaml
# otelcol-gateway.yaml
extensions:
  health_check:
    endpoint: ${env:MY_POD_IP}:13133
  bearertokenauth:
    filename: /var/run/secrets/otel/token

receivers:
  otlp:
    protocols:
      grpc:
        endpoint: ${env:MY_POD_IP}:4317      # never 0.0.0.0
        tls:
          cert_file: /etc/otel/tls/tls.crt
          key_file: /etc/otel/tls/tls.key
        auth:
          authenticator: bearertokenauth

processors:
  memory_limiter:                              # always first
    check_interval: 1s
    limit_percentage: 80
    spike_limit_percentage: 20
  redaction:
    allow_all_keys: true
    blocked_values:
      - "\\b(?:\\d[ -]*?){13,16}\\b"           # card-number-like values
    summary: info
  tail_sampling:
    decision_wait: 10s
    policies:
      - name: errors
        type: status_code
        status_code: { status_codes: [ERROR] }
      - name: slow
        type: latency
        latency: { threshold_ms: 1000 }
      - name: baseline
        type: probabilistic
        probabilistic: { sampling_percentage: 10 }
  batch: {}                                    # after limiter and sampling

exporters:
  otlphttp:
    endpoint: ${env:BACKEND_OTLP_ENDPOINT}
    headers:
      Authorization: "Bearer ${env:BACKEND_TOKEN}"
    sending_queue:
      enabled: true
      queue_size: 1000
    retry_on_failure:
      enabled: true
      max_elapsed_time: 300s

service:
  extensions: [health_check, bearertokenauth]
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, redaction, tail_sampling, batch]
      exporters: [otlphttp]
    metrics:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [otlphttp]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, redaction, batch]
      exporters: [otlphttp]
```

Deployment notes:

- Inject `MY_POD_IP` with the downward API (`status.podIP`); readiness/liveness probes target the
  `health_check` port.
- Tail sampling needs every span of a trace on the same gateway replica: agents export through the
  `loadbalancing` exporter with `routing_key: traceID` to the gateway headless Service.
- Set container memory limits and keep `limit_percentage` below them; run as non-root with a
  read-only root filesystem.
- Issue the TLS certificate with cert-manager and rotate automatically; mount the bearer token
  from a Secret synced by External Secrets.
- Validate before rollout: `otelcol-k8s validate --config=otelcol-gateway.yaml` with the same
  pinned version as production.
