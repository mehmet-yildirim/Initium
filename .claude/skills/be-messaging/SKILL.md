---
name: be-messaging
description: Event streaming and messaging standards — Kafka, RabbitMQ, NATS, and cloud queues; event design and schemas, transactional outbox, idempotent consumers, ordering and partitioning, retries with dead-letter queues, and consumer observability. Use when producing or consuming messages or events, designing event contracts, or choosing a broker.
paths:
  - "**/*consumer*.*"
  - "**/*producer*.*"
  - "**/*listener*.*"
  - "**/events/**"
  - "**/messaging/**"
  - "**/*.avsc"
  - "**/asyncapi*.yaml"
---

# Messaging & Event Streaming Standards

## Choosing a broker

| Need | Typical fit |
|------|-------------|
| Durable, replayable event log; high throughput; stream processing | Kafka (or compatible) |
| Task queues, routing, per-message acknowledgement | RabbitMQ, SQS, Pub/Sub |
| Low-latency request/reply and lightweight streaming | NATS / JetStream |

Put the broker behind a port (`EventPublisher`, `MessageHandler`); domain code never imports a
broker client.

## Event design

- Events are facts in past tense (`OrderPlaced`), commands are imperatives (`ReserveStock`).
  Do not disguise commands as events.
- Envelope with `id`, `type`, `source`, `time`, `schema version`, and correlation / causation ids
  (CloudEvents attributes are a good default).
- Schemas are contracts: Avro, Protobuf, or JSON Schema in a registry with compatibility rules
  (backward or full). Document topics and channels in AsyncAPI.
- Evolve additively: add optional fields; never rename, retype, or reuse fields. Breaking changes
  get a new event type or version.
- Keep payloads small; include identifiers and the data consumers need, not whole aggregates.

## Producing

- Never write to the database and publish in two separate steps. Use the transactional outbox:
  write the event to an outbox table in the same transaction, relay it asynchronously
  (polling or CDC).
- Kafka: `acks=all` and idempotent producer enabled; choose the partition key for the ordering you
  need (usually the aggregate id).

## Consuming

- Delivery is at-least-once. Every handler is idempotent: dedupe by event id (inbox table) or make
  the operation naturally idempotent.
- Commit offsets / ack only after processing succeeds.
- Ordering is guaranteed only within a partition or queue; do not assume global order.
- Retries: bounded with exponential backoff and jitter; poison messages go to a dead-letter
  queue with the error and original metadata. DLQs are monitored and have a replay procedure.
- Separate transient failures (retry) from permanent ones (DLQ immediately).
- Consumers handle unknown fields and unknown event types gracefully.

## Operations

- Monitor consumer lag, processing latency, DLQ depth, and rebalance frequency; alert on lag
  growth, not on single failures.
- Propagate trace context in message headers (see `devops-observability`).
- Define retention and compaction per topic deliberately; document who owns each topic.
- Topic/queue creation and ACLs are managed as code, not by auto-creation in production.

## Testing

- Unit test handlers with in-memory fakes of the port.
- Integration tests against a real broker via Testcontainers.
- Contract tests on schemas (registry compatibility check in CI) so producers cannot break consumers.
