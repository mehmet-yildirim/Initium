---
name: be-messaging
description: Event streaming and messaging standards — Kafka 4.x (KRaft, KIP-848 consumer protocol, share groups), RabbitMQ, NATS JetStream, and cloud queues; CloudEvents envelopes, schema registry and AsyncAPI 3 contracts, consumer-side schema validation, transactional outbox, idempotent consumers, ordering, retries with DLQs, broker security (TLS, SASL, ACLs), and OpenTelemetry messaging conventions. Use when producing or consuming messages or events, designing event contracts, configuring brokers, or choosing a broker.
paths:
  - "**/asyncapi*.y*ml"
  - "**/*.avsc"
  - "**/messaging/**"
  - "**/consumers/**"
  - "**/producers/**"
---

# Messaging & Event Streaming Standards

Owns asynchronous communication between services. Cross-service architecture is in
`be-microservices`; service internals are in `be-node` and the `lang-*` skills; broker
infrastructure manifests are in `devops-kubernetes` / cloud skills.

## Baseline (September 2026)

- Apache Kafka 4.3 (4.x line). KRaft only — ZooKeeper was removed in 4.0; migrate ZooKeeper-based
  clusters to KRaft on 3.9 before upgrading.
- KIP-848 consumer rebalance protocol: GA since 4.0 and enabled on brokers, but clients must opt
  in with `group.protocol=consumer` (planned default in Kafka 5.0). Use it for new consumers.
- Share groups (KIP-932, "queues for Kafka"): production-ready since 4.2, gated by the
  `share.version` feature. Check your client library supports `KafkaShareConsumer` semantics before
  adopting (the Java client does).
- AsyncAPI 3.1 for channel/operation contracts (3.0 documents upgrade by changing the version).
- CloudEvents 1.0 attributes for the envelope.
- OpenTelemetry messaging semantic conventions are still at Development status — pin the semconv
  version your instrumentation emits.

## Choosing a broker

| Need | Typical fit |
|------|-------------|
| Durable, replayable, ordered event log; high throughput; stream processing | Kafka (consumer groups) |
| Work queue on Kafka data: per-record ack, more consumers than partitions, no ordering | Kafka share groups |
| Task queues, routing, per-message ack and TTLs | RabbitMQ (quorum queues), SQS, Pub/Sub, Service Bus |
| Low-latency request/reply and lightweight streaming | NATS / JetStream |

Put the broker behind ports (`EventPublisher`, `MessageHandler`); domain and use-case code never
import a broker client.

## Event design

- Events are facts in past tense (`OrderPlaced`); commands are imperatives (`ReserveStock`). Do not
  disguise commands as events.
- Envelope: CloudEvents `id`, `source`, `type` (versioned, e.g. `com.acme.orders.order-placed.v1`),
  `time`, `specversion`, plus correlation and causation ids in extensions/headers.
- Keep payloads small: identifiers plus the data consumers need, not whole aggregates.
- Respect broker size limits (Kafka's default is about 1 MB per record). Use the claim-check
  pattern (store the payload in object storage, send a reference) for large data.
- No secrets in events; minimize PII and never put PII in keys or headers (they are logged and
  indexed widely).

## Contracts and schemas

- Schemas are contracts: Avro, Protobuf, or JSON Schema in a schema registry with compatibility
  mode `BACKWARD` (or `FULL`) enforced; CI fails on incompatible changes.
- Document every topic/queue in AsyncAPI 3.x (channels, operations, message schemas, bindings,
  owners) and lint it in CI.
- Evolve additively: add optional fields with defaults; never rename, retype, or reuse fields.
  Breaking changes get a new event type/version and a dual-publish period.
- Consumers validate every message against the schema at the boundary before any business logic
  (Zod 4 in TypeScript, Pydantic, generated Avro/Protobuf classes elsewhere). Accept unknown fields
  (forward compatibility); reject missing/invalid required fields to the DLQ, never crash-loop.

Read `reference/consumer-validation.md` for a validated, idempotent handler behind a port.

## Producing

- Never write to the database and publish in two separate steps. Use the transactional outbox:
  insert the event in the same transaction as the state change; a relay (polling or CDC, e.g.
  Debezium) publishes it.
- Kafka: `acks=all`, idempotent producer (`enable.idempotence=true`, the default), topic
  `min.insync.replicas=2` with replication factor 3. Partition key = the entity whose order matters
  (usually the aggregate id).
- Use Kafka transactions only for read-process-write pipelines that need exactly-once within Kafka;
  side effects outside Kafka still need idempotency.

## Consuming

- Delivery is at-least-once. Every handler is idempotent: dedupe by event id in an inbox table in
  the same transaction as the side effect, or make the operation naturally idempotent.
- Commit offsets / ack only after processing succeeds.
- Ordering is guaranteed only within a partition or queue; share groups give no ordering at all.
- Retries: bounded, exponential backoff with jitter (retry topics or delayed redelivery), never a
  tight in-place loop that blocks the partition.
- Separate transient failures (retry) from permanent ones (schema-invalid, business-rejected → DLQ
  immediately). DLQ records keep the original payload, headers, error, and source
  topic/partition/offset. DLQs are monitored and have a documented replay procedure.
- KIP-848 migration: with `group.protocol=consumer`, remove client-side `partition.assignment.strategy`,
  `session.timeout.ms`, and `heartbeat.interval.ms` (now broker/group configs). Rolling upgrades
  convert classic groups automatically when they use standard assignors.
- Share groups: set the delivery-count limit deliberately; records exceeding it are archived, so
  still route poison messages to a DLQ yourself.
- Consumers tolerate unknown event types (skip and count them) and unknown fields.

## Security

- TLS for all client and inter-broker traffic; no plaintext listeners outside local dev.
- Authenticate every client: SASL/SCRAM-SHA-512, SASL/OAUTHBEARER, or mTLS — one principal per
  service, credentials from the secrets manager.
- Authorize with least-privilege ACLs per principal (produce only to owned topics, consume only with
  its own group ids); deny by default.
- Topics, partitions, retention, ACLs, and schema-registry subjects are managed as code; disable
  auto topic creation in production.
- Encrypt sensitive fields end to end when brokers or DLQs are accessible to other teams.

## Observability

- Propagate W3C trace context in message headers; consumers continue the trace (or add span links
  for batch processing).
- Emit OpenTelemetry messaging spans/metrics (`messaging.system`, `messaging.destination.name`,
  `messaging.operation.type`, `messaging.client.operation.duration`). Because the conventions are
  not stable, pin the instrumentation version and use `OTEL_SEMCONV_STABILITY_OPT_IN=messaging`
  where the library supports it.
- Monitor consumer lag (and share-partition lag), processing latency, DLQ depth, retry rate, and
  rebalance frequency. Alert on sustained lag growth and DLQ depth > 0, not on single failures.
- Structured logs via the service logger with event id, type, partition, and offset — never the
  payload if it can hold PII.

## Testing

- Unit test handlers with in-memory fakes of the ports (inbox, use case, publisher).
- Integration tests against a real broker and schema registry via Testcontainers, including
  redelivery, duplicate delivery, and DLQ routing.
- Contract tests: registry compatibility checks in CI plus Pact message pacts (or AsyncAPI-based
  checks) so producers cannot break consumers.
- Test the outbox relay: a rolled-back transaction must publish nothing.

_Versions verified September 2026._
