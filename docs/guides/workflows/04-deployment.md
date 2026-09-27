# Workflow: Deployment

The complete deployment workflow from code merge to production, covering strategies,
safety checks, and incident response.

Commands: `/infra <aws|gcp|azure|onprem> [init|ci|secrets|database|monitoring]` scaffolds the
infrastructure and CD pipelines once per platform; `/deploy <staging|production|canary>` runs the
checklist for every deployment. Platform-specific setup is in
[Deployment Platforms](07-deployment-platforms.md).

Detailed, versioned guidance lives in skills — this guide only summarizes it:

| Topic | Skill |
|-------|-------|
| Pipelines, SHA-pinned actions, OIDC, environments, deployment strategies | [`devops-cicd`](../../../.claude/skills/devops-cicd/SKILL.md) |
| Images, multi-stage builds, SBOM + provenance, Compose | [`devops-docker`](../../../.claude/skills/devops-docker/SKILL.md) |
| Kubernetes workloads, Gateway API, GitOps (Argo CD / Flux), admission policy | [`devops-kubernetes`](../../../.claude/skills/devops-kubernetes/SKILL.md) |
| Cloud platforms | [`devops-aws`](../../../.claude/skills/devops-aws/SKILL.md), [`devops-gcp`](../../../.claude/skills/devops-gcp/SKILL.md), [`devops-azure`](../../../.claude/skills/devops-azure/SKILL.md), [`devops-onprem`](../../../.claude/skills/devops-onprem/SKILL.md) |
| Infrastructure as code | [`devops-terraform`](../../../.claude/skills/devops-terraform/SKILL.md) |
| Monitoring, SLOs, burn-rate alerts | [`devops-observability`](../../../.claude/skills/devops-observability/SKILL.md) |
| Schema changes during deploys | [`db-migrations`](../../../.claude/skills/db-migrations/SKILL.md) |

## Deployment Environments

```
Developer Machine → CI (GitHub Actions) → Staging → Production
                                                  ↗
                                         (Canary) → Production
```

| Environment | Purpose | Deploy trigger | Approval |
|-------------|---------|---------------|---------|
| **Local** | Development & debugging | Manual | None |
| **CI** | Automated quality gates | Every push | None |
| **Staging** | Integration testing, demo | Merge to main | None (auto) |
| **Production** | Live users | Tagged release | Required |

## Standard Deployment Flow

### 1. Feature Merge → Staging (Automatic)

After a PR is merged to `main`:
1. CI runs full test suite (if not already passing, merge is blocked)
2. Container image built **once**, pushed, attested (SBOM + SLSA provenance), and referenced by
   digest — the same digest is promoted through every environment
3. Migrations applied by a dedicated deploy step, then the image deployed to staging by digest
4. Smoke / E2E tests run automatically
5. If smoke tests fail: rollback staging, notify team

### 2. Release Creation → Production (Manual approval)

```bash
# Create a release tag (triggers production pipeline for that commit's already-built digest)
git tag v1.2.3
git push origin v1.2.3

# Or via GitHub Releases UI / release-please / semantic-release automation
```

Protect `v*` tags with a tag ruleset and gate the `production` GitHub environment with required
reviewers. `/doc-changelog` generates the changelog entry from conventional commits if you do not
use release automation.

Pre-production checklist:
- [ ] Staging has been running successfully for N hours
- [ ] Product owner has verified the feature on staging
- [ ] Image attestation verified (`gh attestation verify oci://<image>@<digest> --repo <org>/<repo>`)
- [ ] `/deploy production` run to verify all pre-deploy checks
- [ ] On-call engineer available
- [ ] Rollback plan documented

## Database Migration Workflow

Database migrations require special care. Plan them with `/migrate`, audit pending files with
`/db audit`, and follow [Database Migrations](06-database-migrations.md).

### Migration deployment order (zero-downtime)

```
Step 1: Deploy migration (additive changes only)
  ↓ Application continues running on old schema
Step 2: Deploy application code
  ↓ Application uses new schema
Step 3: [After verification] Deploy cleanup migration
  ↓ Remove old columns/tables no longer needed
```

**Golden rule**: Never run destructive schema changes and code changes in the same deployment.

### Migration safety checklist
- [ ] Migration is backward compatible (old code works against new schema)
- [ ] Migrations run once from a dedicated deploy step — never from every replica at startup
- [ ] Migration tested on production-scale data volume
- [ ] Execution time measured (> 30 seconds → batch it as a separate backfill job)
- [ ] DDL starts with `lock_timeout` / `statement_timeout`; indexes on live tables use `CREATE INDEX CONCURRENTLY`
- [ ] Recovery plan written (a corrective forward migration; a down script only if the tool supports it)

## Deployment Strategies

Summary only — see `devops-cicd` for details and platform recipes in the cloud skills.

### Rolling Update (default)
- Gradually replaces pods/instances; zero-downtime
- Requires: startup/readiness probes properly configured; graceful `SIGTERM` handling; stateless application
- Kubernetes config: `maxSurge: 25%, maxUnavailable: 0`; ECS: deployment circuit breaker with rollback enabled

### Blue-Green
- Two identical environments; switch load balancer atomically
- Zero-risk rollback: switch back instantly
- Use for: stateful changes, major releases, high-risk deployments
- Requires: double capacity temporarily

### Canary
- Route a small share of traffic to the new version (e.g. 5% → 25% → 100%) with automated metric analysis
- Automatic rollback if error rate or latency exceeds threshold
- Use for: high-traffic services, algorithm changes, personalization
- Tools: Argo Rollouts, Flagger, Gateway API `HTTPRoute` weights, AWS CodeDeploy, Cloud Deploy
  canary (Cloud Run), Container Apps revision traffic splitting

### Feature Flags
- Deploy code disabled; enable via flag without deployment
- Instant kill switch: disable flag if issues detected
- Tools: OpenFeature SDK with Unleash, GrowthBook, LaunchDarkly, or flagd; simple env vars for small projects

## Post-Deployment Monitoring

### Immediate monitoring (0–5 minutes), then a 30-minute verification window

These match the checks in `/deploy`. Compare every metric to the pre-deploy baseline:

| Metric | Alert threshold | Action |
|--------|----------------|--------|
| Health endpoint | Not 200 (`GET /health/ready`) | Rollback |
| Error rate | > 2x baseline | Rollback |
| p99 latency | > 20% above baseline | Investigate |
| Request rate | Unexpectedly low | Investigate routing |
| Memory usage | Trending up (leak) | Rollback |
| DB connection pool | Exhausted | Investigate |

For production services, alert on SLO error-budget burn rate rather than raw thresholds alone
(see `devops-observability`), and emit a deployment event (service, version, digest, environment)
so dashboards are annotated.

### Automatic rollback triggers
Configure your deployment platform to auto-rollback if:
- Health check fails after deploy (ECS circuit breaker, Kubernetes progress deadline, Cloud Run revision health)
- Error rate exceeds threshold for 5 minutes
- Latency exceeds SLA for 5 minutes

## Rollback Procedure

### Application rollback (< 5 minutes)

Rollback means redeploying the **previous image digest**; keep previous digests in the registry
for at least the rollback window.

```bash
# Kubernetes with GitOps (Argo CD / Flux): revert the digest-bump commit in the environment overlay
git revert <digest-bump-commit> && git push   # the controller reconciles; manual kubectl changes are reverted as drift

# Kubernetes without GitOps
kubectl rollout undo deployment/app-name -n <namespace>

# AWS ECS
aws ecs update-service --cluster <cluster> --service app --task-definition app:<previous-revision>

# Google Cloud Deploy
gcloud deploy targets rollback production --delivery-pipeline=<pipeline>

# Docker Compose: pin the previous digest (e.g. APP_IMAGE in .env), then
docker compose up -d app
```

### Database rollback

Prefer **forward-only recovery**: ship a new corrective migration. Reverting a migration is only
possible if:
- A down/undo migration was prepared and tested (Flyway undo is a paid feature; many tools are forward-only)
- Application code can run against the rolled-back schema

```bash
# Alembic
alembic downgrade -1

# Goose
goose -dir ./db/migrations postgres "$DATABASE_URL" down
```

Other tools: see the per-tool references in [`db-migrations`](../../../.claude/skills/db-migrations/SKILL.md).

**If no recovery migration was prepared and data is affected**: treat as a data incident. Escalate immediately.

## Incident Response

If a deployment causes an incident:

### 1. Immediate (0–5 minutes)
- Assess severity (how many users affected? data loss?)
- If P0/P1: page on-call, start incident channel in Slack
- Initiate rollback if the issue is clearly from the deployment
- In autonomous mode, the agent raises `/escalate critical ...` and waits for a human
  (see [Escalation Protocol](../../../.initium/docs/agent/escalation-protocol.md))

### 2. Stabilize (5–30 minutes)
- Restore service (rollback or hotfix)
- Communicate status to stakeholders
- Document timeline as it happens

### 3. Root cause (post-incident)
- What failed, why, and how it got past testing — `/debug` helps reproduce and isolate it
- 5 Whys analysis
- Fix the underlying gap (missing test? process? monitoring?) and add a regression test

### 4. Post-incident review (within 48 hours)
- Blameless postmortem document
- Action items with owners and deadlines
- Update runbook with lessons learned

## Using /infra and /deploy

Once per project/platform, scaffold the infrastructure and pipelines:

```
/infra aws init        # or: gcp init, azure init, onprem init
/infra aws ci          # regenerate only the CI/CD workflow
/infra aws monitoring  # also: secrets, database
```

`/infra` loads `devops-terraform`, `devops-cicd`, `security-supply-chain`, the platform skill
(`devops-aws` / `devops-gcp` / `devops-azure` / `devops-onprem`), and `devops-kubernetes` for
Kubernetes targets, so generated workflows are SHA-pinned, use OIDC, and deploy by digest.

For any production deployment, run first:

```
/deploy production     # or: staging, canary
```

This walks through:
- Deployment context (change type, risk level, rollback plan)
- Pre-deployment checklist (code, migrations, config and secrets, dependencies, feature flags, communication)
- Exact execution steps for this deployment
- Post-deployment validation and monitoring plan
- Rollback procedure and a deployment record

Never deploy to production without completing the deploy checklist.
