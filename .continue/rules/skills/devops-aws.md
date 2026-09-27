---
name: devops-aws
description: AWS deployment standards — multi-account Organizations with SCPs and IAM Identity Center, ECS Fargate on Graviton with render-and-deploy task definitions, EKS, Lambda, Aurora PostgreSQL 17/18 serverless, S3 + CloudFront with OAC, ECR, GitHub OIDC, Secrets Manager, AWS Backup, and ADOT/CloudWatch. Targets Terraform AWS provider 6.x, CDK v2 and SAM. Use when designing, writing, or reviewing AWS infrastructure, CDK/SAM apps, or AWS deploy pipelines.
globs:
  - "**/aws/**"
  - "**/cdk.json"
  - "**/samconfig.toml"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# AWS Deployment Standards

AWS-specific architecture and resources. Generic IaC rules (state backends, module layout, plan
review, drift) are in `devops-terraform`; Kubernetes workload rules for EKS are in
`devops-kubernetes`; pipeline hygiene is in `devops-cicd`; telemetry conventions are in
`devops-observability`.

## Baseline and toolchain (September 2026)

- Terraform ≥ 1.11 (S3 native locking GA) with `hashicorp/aws ~> 6.0` (6.66 current) and
  `terraform-aws-modules/vpc/aws ~> 6.0`. State: S3 backend with `use_lockfile = true`; no
  DynamoDB lock table (`dynamodb_table` is deprecated). See `devops-terraform` for the rest.
- CDK: `aws-cdk-lib` v2 (2.27x), TypeScript, `cdk-nag` in synth. SAM CLI 1.16x for Lambda-only apps.
- Aurora PostgreSQL 17 or 18 (18.4 current). Never start new clusters on 15 or older.
- Compute defaults to Graviton (ARM64) — Fargate, Lambda, RDS, ElastiCache — unless a dependency
  ships x86-only binaries.
- GitHub Actions: `aws-actions/configure-aws-credentials` v6, `amazon-ecr-login` v2,
  `amazon-ecs-render-task-definition` v1, `amazon-ecs-deploy-task-definition` v2 — pinned by SHA.

## Account structure

- One AWS Organization; workloads never run in the management account.
- OU layout: `Security` (log archive, audit/delegated admin), `Infrastructure` (network, shared
  services), `Workloads/{Prod,NonProd}`, `Sandbox`. One account per environment per workload.
- Use Control Tower (or Account Factory for Terraform) to vend accounts with baseline guardrails.
- SCPs deny at minimum: leaving the organization, disabling CloudTrail/Config/GuardDuty/Security
  Hub, unapproved regions, and root-user actions. Resource control policies (RCPs) restrict
  external access to S3, KMS, Secrets Manager and STS.
- Humans sign in via IAM Identity Center with permission sets mapped to IdP groups. No IAM users,
  no long-lived access keys. Break-glass access is audited and alarmed.
- CI assumes roles via GitHub OIDC; one deploy role per account/environment.

Read `reference/organization.md` when writing SCPs, Identity Center assignments, or AWS Backup.

## Architecture defaults

```
Route 53 → CloudFront (WAF, ACM cert, TLSv1.2_2025) → ALB (HTTPS) → ECS Fargate (ARM64, private subnets)
                                                               ↓
                                        Aurora PostgreSQL · ElastiCache (private subnets)
```

- **ECS Fargate** is the default for containers: one team, AWS-native tooling, no cluster ops.
- **EKS** when you need a multi-team platform, custom schedulers/operators, or GitOps across
  clouds. Use EKS Auto Mode or Karpenter; EKS Pod Identity for AWS access; manifests follow
  `devops-kubernetes`.
- **Lambda** for event-driven and scheduled work (≤ 15 min). ARM64, provisioned concurrency only
  where cold starts are measured to matter. Powertools for structured logs/tracing.
- **Static frontends**: private S3 bucket + CloudFront with Origin Access Control.

## ECS Fargate

- Task definitions: `runtime_platform { cpu_architecture = "ARM64" }`, `awsvpc`, private subnets,
  `assign_public_ip = false`, read-only root filesystem, non-root user, health check.
- Secrets reach containers only through the `secrets` array (Secrets Manager / SSM ARNs); never
  plain `environment` values.
- Separate roles: the **execution role** pulls images and reads referenced secrets; the **task
  role** carries the application's AWS permissions.
- Deployments: Terraform creates the service and the initial task definition and sets
  `lifecycle { ignore_changes = [task_definition] }`. CI registers each release as a new task
  definition revision and updates the service (render → deploy). `update-service
  --force-new-deployment` alone reuses the old revision and never ships a new image.
- Enable the deployment circuit breaker with rollback. For zero-downtime validation use ECS native
  blue/green (`deployment_configuration { strategy = "BLUE_GREEN" }`) — no CodeDeploy needed.
- Fargate Spot for non-critical services and batch via capacity provider strategy.

Read `reference/ecs-fargate.md` when writing task definitions, services, or ECR repositories.
Read `reference/github-deploy.md` when writing the OIDC trust, deploy role, or the ECS deploy workflow.

## Data

- Aurora PostgreSQL serverless: `min_capacity = 0` with `seconds_until_auto_pause` for
  non-production (true scale to zero; requires 13.15+/14.12+/15.7+/16.3+ and provider ≥ 5.81);
  production keeps a warm minimum.
- `manage_master_user_password = true` — RDS creates and rotates the master secret. Never pass a
  password variable, never compose connection strings containing passwords in Terraform (it lands
  in state). Applications use IAM database authentication or a dedicated app user whose secret is
  rotated by Secrets Manager.
- `storage_encrypted`, `deletion_protection` and final snapshots in production; enforce TLS with
  `rds.force_ssl = 1`.
- Secrets Manager for credentials and API keys; SSM Parameter Store for non-secret config.
- S3: Block Public Access at account and bucket level, bucket-owner-enforced ownership, SSE-KMS
  for sensitive data, versioning + lifecycle rules.

Read `reference/data-and-edge.md` when writing Aurora, Secrets Manager, S3, or CloudFront resources.

## Edge

- CloudFront with an ACM certificate (us-east-1), `minimum_protocol_version = "TLSv1.2_2025"`
  (or `TLSv1.3_2025` when all clients support it), `sni-only`.
- Use managed cache policies (`Managed-CachingOptimized`, `Managed-CachingDisabled`) and origin
  request policies via `cache_policy_id`; `forwarded_values` is legacy.
- S3 origins use OAC (`origin_access_control_id`) with a bucket policy scoped to the distribution
  ARN. Legacy OAI is not used for new distributions.
- AWS WAF managed rule groups on CloudFront and public ALBs in production.

## Networking

- VPC per account/environment, three AZs, private subnets for tasks and data; only load
  balancers in public subnets.
- NAT gateway per AZ in production; single NAT in non-production. Add VPC endpoints (S3, ECR,
  Secrets Manager, CloudWatch Logs, STS) to cut NAT cost and keep traffic private.
- Security groups reference other security groups, never `0.0.0.0/0` on data tiers.
- Shell access through SSM Session Manager or ECS Exec; no SSH keys, no bastions with public IPs.

## Supply chain

- ECR: `IMMUTABLE` tags, enhanced scanning (Amazon Inspector), lifecycle policy, KMS encryption.
- Deploy by digest (`repo@sha256:…`), never `:latest`. Sign images and attach provenance
  (see `devops-cicd`).
- Pin CDK/SAM CLI and Lambda layer versions; commit `cdk.context.json`.

## Security

- Least privilege: scope IAM actions to resource ARNs; `iam:PassRole` only for the specific task
  roles with `iam:PassedToService`.
- GitHub OIDC trust: `aud = sts.amazonaws.com` and `sub` pinned to
  `repo:<org>/<repo>:environment:<env>` — never `repo:<org>/<repo>:*`. The OIDC provider needs no
  `thumbprint_list`.
- Organization-wide CloudTrail (with log file validation) to the log-archive account; GuardDuty,
  Security Hub, IAM Access Analyzer and AWS Config via delegated admin.
- KMS customer-managed keys for regulated data with key policies naming the consuming roles.
- Backups: AWS Backup plans selected by tag, vault lock in compliance mode for production,
  copies to a separate account (or a logically air-gapped vault) and region; test restores quarterly.

## Observability

- Apps emit OpenTelemetry (see `devops-observability`). On ECS run the ADOT Collector as a
  sidecar or use CloudWatch Application Signals; on EKS use the ADOT add-on.
- Container logs: `awslogs` driver (or FireLens for routing) with a retention period set on every
  log group — never infinite retention.
- Alarms on ALB 5xx rate, target response time, ECS CPU/memory, Aurora ACU/connections, and DLQ
  depth; wire critical alarms to the deployment (circuit breaker / blue-green rollback).
- CloudWatch Logs Insights for structured JSON queries; include trace IDs in every log line.

## Cost

- Graviton everywhere possible; Fargate Spot and Aurora scale-to-zero outside production.
- Savings Plans / reserved capacity only after 2–3 months of steady usage data.
- Cost allocation tags via provider `default_tags`; AWS Budgets and Cost Anomaly Detection per
  account.
- S3 Intelligent-Tiering for large, unpredictably accessed data; VPC endpoints over NAT for
  high-volume AWS API traffic.

## Testing

- `terraform test` / `tofu test` for modules (see `devops-terraform`); CDK assertions
  (`Template.fromStack`) and `cdk-nag` for CDK.
- Checkov or Trivy config scans in CI; IAM Access Analyzer policy validation for new policies.
- Ephemeral sandbox accounts for apply-mode tests; destroy after the run.
- Game days: restore from AWS Backup, fail an AZ, roll back a blue/green deployment.

_Versions verified September 2026._
