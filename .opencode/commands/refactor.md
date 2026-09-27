Refactor the specified code without changing its observable behavior.
Refactoring and behavior changes never share a commit.

---

## Step 0: Branch and scope

- Work on a `chore/refactor-<slug>` or `feat/` branch — never on `main` / `develop`.
- Restate the goal (readability, coupling, duplication, layer violation, performance hotspot)
  and the exact scope. If the request mixes refactoring with new behavior, split it: refactor
  first, then `/implement` the behavior change.

## Step 1: Map the blast radius

- Identify every caller of the code in scope. If `codegraph.enabled` is `true`, use
  `/codegraph impact <symbol>`; otherwise search usages explicitly.
- List public contracts that must not change: exported signatures, HTTP/GraphQL/gRPC contracts,
  event schemas, database schema, CLI flags.

## Step 2: Build a safety net

- Run the existing tests for the affected area and record the result.
- If coverage of the code in scope is weak, add characterization tests that pin down current
  behavior (including current edge-case quirks) before changing anything. Commit them separately.

## Step 3: Refactor in small, verified steps

Apply one mechanical transformation at a time and run the tests after each step:

| Smell | Typical move |
|-------|--------------|
| Long function / deep nesting | Extract function, early returns |
| Duplication (3+ occurrences) | Extract shared function or module |
| Business logic in controllers or adapters | Move into application/domain layer behind a port |
| Direct vendor SDK calls in domain code | Introduce port + adapter (see architecture rules) |
| Boolean flag parameters / state flags | Split functions, discriminated unions / sealed types |
| Primitive obsession | Value objects / newtypes |
| Dead code | Delete it (version control keeps history) |

Prefer IDE-grade or codemod transformations (rename, move, extract) over hand edits when available.

## Step 4: Verify behavior is unchanged

- Full test suite for the affected modules passes with no test expectations changed, except
  tests that only referenced renamed internals.
- Lint and type-check pass.
- Public contracts from Step 1 are byte-for-byte compatible (run schema or `buf breaking` checks
  where they exist).

## Step 5: Commit and report

- Commit message: `refactor(<scope>): <what changed structurally>`.
- Report: files changed, transformations applied, contracts verified, tests added, and any
  follow-up refactors deliberately left out of scope.

---

Code or area to refactor, and the goal: $ARGUMENTS
