---
name: devops-cicd
description: CI/CD pipeline standards — GitHub Actions, quality gates, deployment strategies, release process. Use when writing or changing CI/CD pipelines, quality gates, or release automation.
globs:
  - "**/.github/workflows/**"
  - "**/Jenkinsfile"
  - "**/.gitlab-ci.yml"
  - "**/azure-pipelines.yml"
  - "**/Makefile"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# CI/CD Pipeline Standards

## Pipeline Principles
- **Fast feedback**: developer gets results within 10 minutes for core checks
- **Fail fast**: run fastest checks first (lint → test → build → deploy)
- **Reproducible**: same pipeline, same result on any machine at any commit
- **Trunk-based**: main branch always deployable; feature branches short-lived (< 2 days)
- **No manual steps** in the path to production — humans approve, machines execute

## Standard Pipeline Stages

```
Push / PR Open
    │
    ├─ 1. Lint & Format       (< 2 min)  — block PR merge on failure
    ├─ 2. Type Check          (< 2 min)  — block PR merge on failure
    ├─ 3. Unit Tests          (< 5 min)  — block PR merge on failure
    ├─ 4. Security Audit      (< 2 min)  — block PR merge on CRITICAL
    ├─ 5. Build               (< 5 min)  — verify build succeeds
    │
Merge to main
    │
    ├─ 6. Integration Tests   (< 10 min) — deploy only if pass
    ├─ 7. Build & Push Image  (< 5 min)  — tag with git SHA
    ├─ 8. Deploy to Staging   (< 5 min)  — automatic
    ├─ 9. E2E / Smoke Tests   (< 10 min) — rollback staging if fail
    │
Manual approval (or automatic for low-risk)
    │
    └─ 10. Deploy to Production — blue/green or canary
```

## GitHub Actions Patterns

### Reusable Workflow Structure
```
.github/
├── workflows/
│   ├── ci.yml              # PR checks (lint, test, build)
│   ├── cd-staging.yml      # Deploy to staging on main merge
│   ├── cd-production.yml   # Deploy to production on approval
│   ├── security.yml        # Weekly dependency audit
│   └── release.yml         # Tag + changelog generation
└── actions/
    └── setup-project/      # Composite action for common setup
        └── action.yml
```

### Quality Gates (enforce these)
```yaml
# ci.yml — required status checks that block PR merge
jobs:
  lint:       # ruff / eslint / golangci-lint
  typecheck:  # mypy / tsc / go vet
  test:
    strategy:
      matrix:
        shard: [1, 2, 3, 4]   # Parallelize test suite for speed
  security:
    steps:
      - run: npm audit --audit-level=high  # Fail on HIGH+
      - uses: aquasecurity/trivy-action@master  # Container scan
  coverage:
    steps:
      - name: Check coverage threshold
        run: |
          COVERAGE=$(cat coverage/total.txt)
          if (( $(echo "$COVERAGE < 80" | bc -l) )); then
            echo "Coverage $COVERAGE% is below 80% threshold"
            exit 1
          fi
```

### Concurrency & Cancellation
```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true   # Cancel outdated runs on new push
```

### Caching (Critical for Speed)
```yaml
- uses: actions/cache@v4
  with:
    path: |
      ~/.npm
      node_modules
    key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}
    restore-keys: |
      ${{ runner.os }}-node-
```

### Secrets Management in CI
- Store secrets in GitHub Secrets — never in YAML files or code
- Use OIDC for cloud provider auth (no long-lived credentials):
  ```yaml
  permissions:
    id-token: write
    contents: read
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: arn:aws:iam::123456789:role/github-actions
  ```
- Rotate secrets on team member departure
- Never print secrets in logs — use `::add-mask::$SECRET` if needed in output

## Deployment Strategies

### Rolling Update (default for stateless services)
- Gradually replace old instances with new ones
- Zero downtime if health checks are configured
- Kubernetes: `maxSurge: 25%, maxUnavailable: 0`

### Blue-Green (for critical services)
- Two identical environments; switch traffic instantly
- Enables instant rollback by switching back
- Requires double the resources temporarily

### Canary (for high-traffic, risky changes)
- Route small % (e.g., 5%) of traffic to new version
- Monitor error rate and latency; auto-rollback on regression
- Gradually increase to 100% if stable
- Tools: Argo Rollouts, Flagger, AWS CodeDeploy

### Feature Flags (decouple deploy from release)
- Deploy code with feature disabled; enable via flag
- Allows dark launches, A/B testing, instant kill switch
- Tools: LaunchDarkly, Unleash, GrowthBook, environment variables

## Rollback Procedure
- Every deployment must have a documented rollback strategy
- Automated rollback trigger: error rate > threshold for N minutes
- Database migrations must be backward compatible (deployed before code change)
- Keep previous image tag available for at least 48 hours
- Runbook in `docs/workflows/deployment.md`

## Environment Promotion
```
feature branch → dev (auto) → staging (auto on main merge) → production (approval gate)
```
- Each environment has isolated infrastructure (separate DB, secrets, networking)
- Production secrets never available in lower environments
- Environment parity: use the same Docker image across environments (no rebuilds)

## Release Process
- Semantic versioning: `vMAJOR.MINOR.PATCH`
- **Breaking changes**: MAJOR bump; requires migration guide
- **New features**: MINOR bump
- **Bug fixes**: PATCH bump
- Automated changelog from conventional commits: `release-please` or `semantic-release`
- Git tag triggers production deployment pipeline

## Observability Gates
- Deploy only if:
  - Error rate stable for 5 minutes post-deploy
  - p99 latency within 20% of baseline
  - No new alerts firing
- Automated via deployment platform health checks or Argo Rollouts analysis
