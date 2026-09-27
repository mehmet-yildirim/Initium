Create or run an evaluation suite for an LLM-powered feature (prompt, RAG pipeline, agent,
classifier, extractor). Load the `ai-llm-apps` skill before starting.

Modes (from `$ARGUMENTS`):
- `create <feature>` — build an eval set and runner for a feature (default)
- `run [feature]` — run existing evals and compare with the stored baseline
- `compare <feature> <variant-a> <variant-b>` — compare prompts, models, or retrieval settings

---

## create

1. **Understand the feature.** Locate the prompt(s), model configuration, retrieval, tools, and
   output schema. Write down what "good" means in observable terms (correct fields, grounded in
   sources, refuses out-of-scope requests, stays within length, valid JSON).
2. **Build the dataset** in `evals/<feature>/dataset.jsonl` — one case per line with `id`,
   `input`, optional `context`, and `expected` (exact value, properties, or reference answer):
   - 20–50 representative cases from real usage (anonymized — no PII or secrets)
   - Edge cases: empty input, very long input, ambiguous requests, other languages
   - Adversarial cases: direct and indirect prompt injection, requests to reveal the system
     prompt, attempts to trigger unauthorized tools, empty or irrelevant retrieval
3. **Choose graders per property**, cheapest reliable first:
   - Deterministic: schema validation, exact match, regex, numeric tolerance, citation present,
     tool-call arguments match
   - Reference-based: similarity or F1 against reference answers
   - LLM-as-judge: only for qualities code cannot check; use a rubric with a fixed scale, a
     different model than the one under test where possible, and calibrate against at least
     20 human-labelled cases before trusting it
4. **Write the runner** (`evals/<feature>/run.*`) using the project's language or an existing
   eval framework already in the repo. It calls the feature through its application port, not the
   provider SDK directly, records per-case scores, tokens, latency, and cost, and writes
   `evals/<feature>/results/<timestamp>.json`.
5. **Set thresholds** in `evals/<feature>/thresholds.json` (for example schema validity 100%,
   groundedness ≥ 0.9, injection resistance 100%) and store the first passing run as `baseline.json`.
6. **Wire into CI** so evals run when prompts, model configuration, retrieval code, or the
   dataset change. Use a small smoke subset on every PR and the full set nightly.

## run

- Execute the runner, compare with `baseline.json` and `thresholds.json`.
- Report per-metric deltas, failing case ids with inputs and outputs, and token/cost/latency
  changes. A threshold breach or a regression on adversarial cases is a failure.
- Never "fix" a failure by editing expected values without explaining why the old expectation
  was wrong.

## compare

- Run both variants on the same dataset with the same graders and seeds.
- Report a side-by-side table (quality metrics, cost per 1k requests, p95 latency) and a
  recommendation with the trade-off stated.

---

Eval request: $ARGUMENTS
