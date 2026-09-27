---
name: devops-cicd
description: CI/CD pipeline standards for GitHub Actions (plus GitLab CI, Jenkins, Azure Pipelines) — third-party actions pinned by full commit SHA, empty top-level permissions with per-job grants, OIDC with environment-scoped `sub` claims, environment protection rules, current action majors on the Node 24 runtime (checkout v7, setup-node v7, attest v4), SLSA build provenance with `actions/attest` and `gh attestation verify`, zizmor and actionlint, script-injection and `pull_request_target` defenses, ephemeral runners, quality gates, progressive delivery, and releases. Use when writing or reviewing workflows, pipelines, quality gates, deployment jobs, or release automation.
globs:
  - "**/.github/workflows/**"
  - "**/.gitlab-ci.yml"
  - "**/Jenkinsfile"
  - "**/azure-pipelines*.yml"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# CI/CD Pipeline Standards

Pipeline design and workflow security. Image build rules are in `devops-docker`; cluster
delivery (GitOps, admission policy) is in `devops-kubernetes`; dependency-update bots and SBOM
policy are in `security-supply-chain`.

## Baseline (September 2026)

- GitHub-hosted runners run JavaScript actions on Node 24 only; Node 20 was removed on
  2026-09-23 and the `ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION` opt-out is gone. Actions still
  declaring `node20` fail — upgrade them.
- Current majors: `actions/checkout` v7, `actions/setup-node` v7, `actions/upload-artifact` v7,
  `actions/attest` v4 (`attest-build-provenance` v4 is now only a wrapper — use `actions/attest`
  for new work), `docker/build-push-action` v7, `docker/setup-buildx-action` v4,
  `docker/login-action` v4, `docker/metadata-action` v6, `aws-actions/configure-aws-credentials`
  v6, `sigstore/cosign-installer` v4, `zizmorcore/zizmor-action` v0.6, actionlint 1.7.
- Pin runner images explicitly (`ubuntu-24.04`) so image upgrades are deliberate.

## Pipeline principles

- Fast feedback: core PR checks finish in under 10 minutes; run the cheapest checks first.
- Reproducible: lockfile installs (`npm ci`), pinned toolchains, pinned actions and images.
- Trunk-based: `main` is always deployable; humans approve, machines execute.
- Build once, promote the same artifact digest through every environment.

Standard stages — PR: lint → typecheck → unit tests (sharded) → dependency audit → build →
workflow lint. Main: integration tests → build, push, attest → deploy staging → smoke/E2E →
approval → production (canary or blue/green).

## Supply chain: pin every action

- Pin every third-party action to a full 40-character commit SHA with the version as a comment:
  `uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1`. Tags and branches
  are mutable. In March 2026 attackers force-pushed 76 of 77 `aquasecurity/trivy-action` tags
  (and all `setup-trivy` tags) to credential-stealing code
  ([GHSA-69fq-xp46-6x23](https://github.com/aquasecurity/trivy/security/advisories/GHSA-69fq-xp46-6x23));
  workflows on `@master` or a version tag ran it, SHA-pinned workflows did not.
- Pin GitHub-authored actions too, and `docker://` actions by digest.
- Resolve SHAs from the action's own repository (not a fork) — `git ls-remote --tags <repo>`.
- Let Dependabot or Renovate bump SHAs and comments; review the diff of the action, not only the
  version number. Dependabot does not raise security alerts for SHA-pinned actions — keep update
  PRs flowing.
- Enable the org/repo policy "Require actions to be pinned to a full-length commit SHA" and an
  allowlist of permitted actions; block known-bad actions with `!owner/action@*` entries.
- Composite actions and reusable workflows you own must pin their inner `uses:` as well.

## Permissions (least privilege)

- Set the org default `GITHUB_TOKEN` permission to read-only.
- Top of every workflow: `permissions: {}`. Grant per job only what that job needs
  (`contents: read`, `packages: write`, `id-token: write`, `attestations: write`, ...).
- `actions/checkout` with `persist-credentials: false` unless a later step must push.
- Never pass `secrets: inherit` to reusable workflows you do not own; pass named secrets.

## Workflow injection defenses

- Never interpolate attacker-controlled context into `run:` or `script:` (PR title/body, branch
  names, issue/comment text, `github.head_ref`). Pass it through `env:` and quote the variable.
- `pull_request_target` and `workflow_run` run with base-repo secrets and a write token. Do not
  check out or execute PR head code in them; prefer `pull_request`. If unavoidable, split into an
  unprivileged build job and a privileged job that only consumes inert artifacts.
- Do not cache or restore build caches in privileged release jobs (cache poisoning); set
  `package-manager-cache: false` on `setup-node` there.
- Lint workflows on every PR with actionlint (syntax, expressions, shellcheck) and zizmor
  (template injection, excessive permissions, unpinned uses, dangerous triggers). Fail on
  zizmor findings of medium severity and above.

## Secrets, OIDC, and environments

- Cloud access via OIDC federation only; no long-lived cloud keys in secrets.
- Deploy jobs declare `environment: <name>`. Scope the cloud trust policy to the environment
  claim: `sub = repo:<org>/<repo>:environment:production`, not `repo:<org>/<repo>:*`.
- Environment protection rules for production: required reviewers (prevent self-review),
  deployment branch/tag restrictions (`main` or `v*` tags), optional wait timer. Store
  production secrets as environment secrets so other jobs cannot read them.
- Mask derived secrets with `::add-mask::`; never echo secrets; rotate on staff departure and
  immediately after any suspected compromise.

## Runners

- Prefer GitHub-hosted or other ephemeral runners: one job per fresh VM/pod.
- Self-hosted runners are ephemeral only (`--ephemeral`, or Actions Runner Controller scale sets),
  never persistent, never attached to public repositories, and isolated per trust level.
- No cluster-admin credentials or `kubectl` contexts on runners; production changes flow through
  GitOps or a narrowly scoped OIDC role.

## Caching and speed

- Use the setup action's cache (`actions/setup-node` with `cache: npm`) — it caches the package
  manager store, not `node_modules`. Current setup-node also auto-enables npm caching when
  `package.json` declares `packageManager: npm@...`.
- Docker layer cache: `cache-from/cache-to: type=gha` in `docker/build-push-action`.
- `concurrency` groups cancel superseded PR runs; never cancel in-progress deploys.
- Set `timeout-minutes` on every job.

## Artifacts, provenance, and verification

- Container images: build with SBOM and `provenance: mode=max`, push, then attest the digest with
  `actions/attest` (`subject-name` without tag, `subject-digest`, `push-to-registry: true`) and
  sign with cosign keyless where cluster admission verifies Sigstore signatures.
- Before every deploy, verify: `gh attestation verify oci://<image>@<digest> --repo <org>/<repo>`.
  Deploy only by digest.
- Upload SBOMs as build artifacts or attest them (`sbom-path`) for audit.
- Artifact attestations need a public repo or GitHub Enterprise Cloud for private repos.

Read `reference/github-actions.md` for complete, SHA-pinned CI and build-attest-deploy workflows.

## Quality gates

- Required status checks: lint, typecheck, unit tests, coverage threshold (enforced in the test
  runner config, e.g. Vitest `coverage.thresholds`), dependency audit, build, workflow lint.
- Dependency audit fails on HIGH+ with a fix available; image scan fails on fixable CRITICAL.
- Branch protection/rulesets: required checks, linear history, signed commits where mandated.

## Deployment strategies

- Rolling (default, stateless): Kubernetes `maxSurge: 25%`, `maxUnavailable: 0`, readiness gates.
- Blue/green (critical services): instant switch and instant rollback; costs double capacity.
- Canary (high traffic/risky): 5% → 25% → 100% with automated analysis; tools: Argo Rollouts,
  Flagger, AWS CodeDeploy.
- Feature flags decouple deploy from release (OpenFeature SDK with Unleash, GrowthBook,
  LaunchDarkly, flagd).

## Rollback and migrations

- Every deployment has a documented, rehearsed rollback: redeploy the previous digest.
- Automated rollback on sustained error-rate or latency regression (see `devops-observability`).
- Database migrations are backward compatible (expand → migrate → contract) and run before the
  code that needs them; see `db-migrations`.
- Keep previous image digests pullable for at least the rollback window (registry retention).

## Environment promotion

- `feature → dev (auto) → staging (auto on main) → production (approval)`.
- Separate infrastructure, secrets, and cloud accounts/projects per environment; production
  secrets are never available to lower environments.

## Release process

- Semantic versioning; breaking changes need a MAJOR bump and a migration guide.
- Automated changelog from conventional commits (`release-please` or `semantic-release`).
- A `v*` tag (protected by a tag ruleset) triggers the production pipeline for that commit's
  already-built digest.

## Observability

- Emit deployment events (service, version, digest, environment) to the observability backend and
  annotate dashboards.
- Deploy gates: error rate stable and p99 within 20% of baseline for the verification window; no
  new alerts. Automate with Argo Rollouts analysis or the platform's health checks.
- Track pipeline DORA metrics (deploy frequency, lead time, change failure rate, time to restore).

## Testing pipelines

- actionlint + zizmor on every PR touching `.github/`.
- Test reusable workflows and composite actions in a sandbox repo before rolling out.
- Dry-run deploy jobs against staging on every main merge; production uses the identical job.

_Versions verified September 2026._
