---
name: ai-llm-apps
description: Standards for building LLM-powered features — provider adapters, structured output, RAG, tool calling, prompt-injection defense (OWASP LLM Top 10), cost control, observability, and MCP server development. Use when adding or changing any code that calls an LLM, builds prompts, retrieves context for a model, exposes tools to an agent, or implements an MCP server.
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# LLM Application Standards

## Architecture — the model is an external system

- Put every model provider behind a port (`LlmClient`, `EmbeddingClient`) in the application layer;
  vendor SDKs live only in infrastructure adapters. Swapping providers or models must not touch
  domain code.
- Model name, temperature, max tokens, and timeouts come from configuration, never literals.
- Prompts are versioned artifacts: store them in `prompts/` (or equivalent) with an id and version,
  not as string literals scattered through services. Log the prompt version with every call.
- Keep deterministic logic out of the model. Validation, authorization, arithmetic, and business
  rules run in code; the model only does what code cannot.

## Structured output

- Request structured output (JSON schema / tool call) instead of parsing free text.
- Validate every response against the same schema at runtime (Zod, Pydantic, etc.) and treat a
  validation failure as a recoverable error: retry once with the validation error, then fail.
- Never `eval`, execute, or render model output as HTML without escaping and validation.

## Security — OWASP Top 10 for LLM Applications

| Risk | Required control |
|------|------------------|
| Prompt injection (direct and indirect) | Treat user input, retrieved documents, web pages, and tool results as untrusted data. Delimit them clearly; never let them change the system prompt or tool permissions. |
| Sensitive information disclosure | Redact secrets and PII before sending to the model and before logging prompts. Enforce data residency rules per provider. |
| Excessive agency | Tools get least privilege and an allowlist. Destructive or irreversible actions (payments, deletes, emails, merges) require explicit human confirmation. |
| System prompt leakage | Assume the system prompt will be extracted. Never put secrets, credentials, or authorization logic in it. |
| Vector and embedding weaknesses | Enforce tenant and permission filters at retrieval time, not after generation. |
| Improper output handling | Output feeding SQL, shell, HTML, or file paths is validated exactly like user input. |
| Unbounded consumption | Per-user and per-tenant rate limits, max input size, max tokens, and request timeouts on every call. |

## Retrieval-augmented generation (RAG)

- Chunk on semantic boundaries (headings, functions, paragraphs), not fixed character counts, and
  store source id, section, and permissions metadata with every chunk.
- Prefer hybrid retrieval (BM25 + vector) with a reranker over pure vector search.
- Always return citations; answer "not found in sources" instead of guessing when retrieval is empty.
- Re-embed on source change using content hashes; never rebuild the whole index for one edit.

## Cost and latency

- Put stable content (system prompt, tool definitions, reference docs) first so provider prompt
  caching applies; put volatile content (user turn) last.
- Route by task: small/fast model for classification and extraction, large model only where
  quality needs it. Record the routing decision.
- Stream responses for user-facing latency; set hard timeouts and a fallback path.
- Track tokens and cost per request, feature, and tenant; alert on budget breaches.

## Observability

- Trace every model call as a span (OpenTelemetry GenAI semantic conventions): model, prompt
  version, input/output tokens, latency, finish reason, tool calls, cache hit.
- Do not log full prompts or completions by default; sample and redact when needed for debugging.

## Evaluation (see `/eval`)

- Every LLM feature ships with an eval set: representative inputs, expected properties, and
  adversarial cases (injection, off-topic, empty retrieval).
- Run evals in CI on prompt, model, or retrieval changes and block on regression.
- LLM-as-judge scores must be calibrated against a human-labelled sample before they gate releases.

## Testing

- Unit tests mock the `LlmClient` port and assert on prompt construction and response handling.
- Never call a real provider in unit tests. Contract tests against the real provider run separately
  and are allowed to be slow.

## MCP server development

- One tool = one clear capability with a precise description; agents choose tools by description.
- Validate tool input against its JSON schema and return actionable error messages.
- Tools return the minimum data needed — paginate and summarize large results to protect the
  caller's context window.
- Read-only by default; mark mutating tools clearly and require confirmation for destructive ones.
- Remote servers authenticate (OAuth 2.1) and authorize per user; never return secrets in results.
- Log every tool invocation with caller identity for audit.
