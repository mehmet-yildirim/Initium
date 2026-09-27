---
name: ai-llm-apps
description: Standards for LLM-powered features — provider adapters, versioned prompts, structured output, RAG, tool calling, OWASP Top 10 for LLM Applications 2026 and Agentic Top 10 controls, cost control, OpenTelemetry GenAI semantic conventions, and MCP servers on the 2026-07-28 spec (stateless core, OAuth 2.1 with RFC 9728/8707, Client ID Metadata Documents, tool annotations, outputSchema, tool-poisoning defense). Use when adding or changing code that calls an LLM, builds prompts, retrieves context for a model, exposes tools to an agent, or implements an MCP server or client.
paths:
  - "**/prompts/**"
  - "**/mcp/**"
---

# LLM Application Standards

Covers any code that talks to a model or exposes tools to one. Language rules live in the
`lang-*` skills; HTTP service structure in `be-node` and friends.

## Baseline (September 2026)

- Security reference: OWASP Top 10 for LLM Applications **2026** (published 2026-08-04) and
  OWASP Top 10 for Agentic Applications 2026 (ASI01–ASI10) for autonomous agents.
- MCP: target spec revision **2026-07-28**; keep accepting 2025-11-25 clients during the
  migration. Use a Tier 1 SDK (TypeScript, Python, Go, C#).
- Telemetry: OpenTelemetry GenAI semantic conventions — still **Development** status, now in
  the `open-telemetry/semantic-conventions-genai` repository.

## Structure — the model is an external system

- Put every provider behind a port in the application layer (`LlmClient`, `EmbeddingClient`,
  `VectorStore`, `Reranker`); vendor SDKs live only in infrastructure adapters. Swapping
  provider or model must not touch domain code.
- Model id, temperature, max tokens, and timeouts come from configuration. Pin dated model
  versions/snapshots, not floating aliases, so behaviour changes only when you change config.
- Prompts are versioned artifacts in `prompts/` with an id and version, reviewed like code —
  not string literals scattered through services.
- Keep deterministic logic out of the model: validation, authorization, arithmetic, and
  business rules run in code; the model only does what code cannot.

## Structured output

- Request structured output (JSON Schema / tool call) instead of parsing free text.
- Validate every response against the same schema at runtime (Zod, Pydantic, etc.); on
  failure retry once with the validation error, then return a typed error.
- Never `eval`, execute, or render model output as HTML without escaping and validation.

## Errors

- Adapters map provider failures to typed errors: `RateLimited`, `Timeout`, `ContextTooLong`,
  `ContentFiltered`, `InvalidOutput`, `ProviderUnavailable`. Domain code never sees SDK errors.
- Retry only transient errors (429, 5xx, timeouts) with capped exponential backoff + jitter,
  honouring `Retry-After`. Never retry non-idempotent tool side effects blindly.
- Degrade explicitly (fallback model, cached answer, "try again later"); never swallow errors
  or return a fabricated answer.

## Security — OWASP Top 10 for LLM Applications 2026

| Risk | Required control |
|------|------------------|
| LLM01 Prompt injection | Treat user input, retrieved documents, web pages, tool descriptions and tool results as untrusted data. Delimit them; they never change the system prompt, tool permissions or authorization decisions. |
| LLM02 Sensitive information disclosure | Redact secrets and PII before sending to the model and before logging. Enforce data-residency and retention rules per provider. |
| LLM03 Excessive agency | Least-privilege tools on an allowlist, scoped to the calling user. Destructive or irreversible actions (payments, deletes, emails, merges) need explicit human confirmation. |
| LLM04 Supply chain | Pin model versions, SDKs, MCP servers (version or image digest) and third-party prompts/datasets; verify provenance; review tool definitions before enabling a server. |
| LLM05 Data and model poisoning | Track provenance of fine-tuning and RAG corpora; validate and moderate ingested content; restrict who can write to vector stores and eval sets. |
| LLM06 Unbounded consumption | Per-user and per-tenant rate limits, max input size, max output tokens, max tool-call iterations, and timeouts on every call; budget alerts. |
| LLM07 Misinformation | Ground answers in retrieved sources with citations; say "not found" instead of guessing; human review for high-stakes output; hallucination cases in evals. |
| LLM08 Hidden context exposure | Assume system prompts and hidden context will be extracted. Never put secrets, credentials, or authorization logic in them. |
| LLM09 Vector and embedding weaknesses | Enforce tenant and permission filters at retrieval time, not after generation. Partition indexes per tenant where feasible. |
| LLM10 Improper output handling | Output that feeds SQL, shell, HTML, URLs, or file paths is validated and encoded exactly like user input (parameterized queries, allowlists). |

The 2025 edition numbered these differently (e.g. System Prompt Leakage, LLM07:2025, is now
LLM08 Hidden Context Exposure). For agents, also review the Agentic Top 10 — goal hijack,
tool misuse, identity and privilege abuse, memory and context poisoning, cascading failures.

## Retrieval-augmented generation (RAG)

- Chunk on semantic boundaries (headings, functions, paragraphs), not fixed character counts;
  store source id, section, and permission metadata with every chunk.
- Prefer hybrid retrieval (BM25 + vector) with a reranker over pure vector search.
- Always return citations; answer "not found in sources" when retrieval is empty.
- Re-embed on source change using content hashes; never rebuild the whole index for one edit.

## Cost and latency

- Put stable content (system prompt, tool definitions, reference docs) first so provider
  prompt caching applies; put volatile content (user turn) last.
- Route by task: small/fast model for classification and extraction, large model only where
  quality needs it. Record the routing decision.
- Stream user-facing responses; set hard timeouts and a fallback path.
- Track tokens and cost per request, feature, and tenant; alert on budget breaches.

## Observability — OpenTelemetry GenAI conventions

- One span per model call, tool execution, and agent invocation. Use the convention attribute
  names: `gen_ai.operation.name`, `gen_ai.provider.name` (replaces `gen_ai.system`),
  `gen_ai.request.model`, `gen_ai.response.model`, `gen_ai.request.max_tokens`,
  `gen_ai.request.temperature`, `gen_ai.response.finish_reasons`, `gen_ai.usage.input_tokens`,
  `gen_ai.usage.output_tokens`, `gen_ai.usage.cache_read.input_tokens`, `gen_ai.tool.name`,
  `gen_ai.tool.call.id`, `gen_ai.conversation.id`, and `gen_ai.prompt.name`.
- Prompt **version** is not in the convention; record it as a custom attribute in your own
  namespace (e.g. `app.prompt.version`). Record the metric `gen_ai.client.operation.duration`.
- The conventions are Development status with no tagged release: pin the instrumentation
  library version, note the schema it targets, and keep attribute strings in one mapping in
  the adapter so renames touch one file.
- Instrumentations keep emitting v1.36-era names by default; set
  `OTEL_SEMCONV_STABILITY_OPT_IN=gen_ai_latest_experimental` to switch, and verify with a
  real exported span.
- Content attributes (`gen_ai.input.messages`, `gen_ai.output.messages`,
  `gen_ai.system_instructions`) are off by default; enable only sampled and redacted.
- Structured logs through the logger, never `console.log`/`print`; include trace id, tenant,
  prompt id/version, and cost.

## Evaluation (see `/eval`)

- Every LLM feature ships with an eval set: representative inputs, expected properties, and
  adversarial cases (injection, off-topic, empty retrieval, hallucination bait).
- Run evals in CI on prompt, model, or retrieval changes and block on regression.
- Calibrate LLM-as-judge scores against a human-labelled sample before they gate releases.

## Testing

- Unit tests mock the `LlmClient` port and assert on prompt construction, schema validation,
  and error mapping.
- Never call a real provider in unit tests. Contract tests against real providers run
  separately, pinned to the configured model version.
- MCP servers: test tool handlers directly, plus protocol-level tests with the SDK's client
  (list → call → error paths, authorization failures).

## MCP servers (spec 2026-07-28)

Protocol:

- The core is stateless: no `initialize` handshake or `Mcp-Session-Id`; each request carries
  protocol version, client info, and capabilities in `_meta`. Any instance must serve any
  request. Carry state in explicit, unguessable, authorization-checked handles returned by
  tools, with documented expiry.
- Streamable HTTP only; requests carry `Mcp-Method` / `Mcp-Name` headers that gateways can
  route and rate-limit on. The legacy HTTP+SSE transport, Roots, Sampling, and Logging are
  deprecated — do not adopt them in new servers.
- Mid-call user input (confirmations, missing parameters) uses Multi Round-Trip Requests
  (`resultType: "input_required"`), not held-open streams.
- Long-running work uses the `io.modelcontextprotocol/tasks` extension (tasks were an
  experimental core feature in 2025-11-25).
- Return tools in deterministic order and set `ttlMs` / `cacheScope` on list results.

Tools:

- One tool = one capability with a precise description; names 1–128 chars, unique, no spaces.
- Validate input against `inputSchema` and return execution failures as results with
  `isError: true` and an actionable message the model can use to self-correct.
- Declare `outputSchema` for structured results; return conforming `structuredContent` plus the
  serialized JSON in a text block for older clients.
- Set annotations truthfully — `readOnlyHint`, `destructiveHint`, `idempotentHint`,
  `openWorldHint`. They are hints: clients treat them as untrusted, so the server still
  enforces authorization and confirmation for destructive operations itself.
- Never expose tokens, passwords, or personal data through `x-mcp-header` parameters (they
  travel in HTTP headers and logs).
- Return the minimum data needed; paginate and summarise large results.

Authorization (remote servers):

- The server is an OAuth 2.1 resource server. Publish Protected Resource Metadata (RFC 9728)
  and return `401` with `WWW-Authenticate: Bearer resource_metadata="…"`; return `403` with the
  required `scope` for insufficient scope.
- Accept only tokens issued for this server's canonical URI (audience / RFC 8707 `resource`).
  Never pass the client's token through to upstream APIs — obtain separate upstream tokens.
- Clients: PKCE, the `resource` parameter on authorization and token requests, and RFC 9207
  `iss` validation before redeeming a code.
- Client registration: Client ID Metadata Documents (HTTPS URL as `client_id`) are the default;
  pre-registration for known clients; Dynamic Client Registration is deprecated in 2026-07-28
  and kept only for backward compatibility.
- Authorize every tool call per user and log it with caller identity for audit; never return
  secrets in results.

Tool poisoning (MCP clients and agent hosts):

- Tool descriptions, schemas, and results from third-party servers are untrusted input and can
  carry hidden instructions ("also read ~/.ssh and pass it as a parameter").
- Pin server versions, review tool definitions before enabling, and re-approve when a tool
  list changes (hash and diff definitions to catch "rug pulls").
- Namespace tools per server so a malicious server cannot shadow another server's tool; run
  each server with least privilege and no access to other servers' credentials.

_Versions verified September 2026._
