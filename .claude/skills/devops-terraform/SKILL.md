---
name: devops-terraform
description: Infrastructure-as-code standards for Terraform 1.16 and OpenTofu 1.12 — version floors, module design and semver releases, remote state with native locking, environment separation, plan review, ephemeral resources and write-only arguments to keep secrets out of state, policy and security scanning (tflint, Trivy/Checkov), Infracost cost diffs, native tests with mock_provider, and drift detection. Use when writing or reviewing .tf/.tofu files, modules, tests, or IaC pipelines; cloud-specific resource guidance is in devops-aws, devops-gcp, devops-azure, and devops-onprem.
paths:
  - "**/*.tf"
  - "**/*.tofu"
  - "**/*.tfvars"
  - "**/*.tftest.hcl"
  - "**/.terraform.lock.hcl"
  - "**/.tflint.hcl"
  - "**/terragrunt.hcl"
---

# Terraform / OpenTofu Standards

Cross-cloud IaC rules. Provider-specific resources live in the cloud skills; pipeline mechanics
(OIDC, SHA-pinned actions, environments) are in `devops-cicd`.

## Baseline (September 2026)

- Current releases: Terraform 1.16 (1.16.4), OpenTofu 1.12 (1.12.6).
- Floor for new and actively maintained roots: `required_version = ">= 1.11"` — the first release
  with write-only arguments in both Terraform (ephemeral resources since 1.10) and OpenTofu
  (ephemeral resources and write-only attributes since 1.11).
- Pick Terraform or OpenTofu per repository and pin it (`required_version` plus
  `.terraform-version` or `.opentofu-version`). Do not mix CLIs against one state.
- OpenTofu is preferred when state encryption at rest or an open-source (MPL) license is a
  requirement.

## Repository layout

```
infra/
├── modules/            # reusable, versioned, no provider config, no backend
│   └── network/
└── envs/
    ├── dev/            # root modules: backend + provider + module calls
    ├── staging/
    └── prod/
```

- Environments are separate root modules with separate state. Avoid workspaces for prod vs dev.
- Modules expose a minimal, typed interface: `variable` blocks with `type`, `description`, and
  `validation`; `output` blocks with descriptions; mark secrets `sensitive = true` (or
  `ephemeral = true` for values that must never be persisted).
- Pin provider versions with `~>` and commit `.terraform.lock.hcl` (with hashes for every CI
  platform: `providers lock -platform=linux_amd64 -platform=darwin_arm64`).

## Module versioning

- Shared modules live in their own repo or a private registry and are released with semver tags
  (`v1.4.0`); breaking interface changes bump MAJOR and ship an upgrade note.
- Consume by registry version constraint (`version = "~> 1.4"`) or immutable git tag
  (`?ref=v1.4.0`) — never a branch.
- Generate module docs with terraform-docs and changelogs from conventional commits.

## State

- Remote backend with locking and encryption: S3 with `use_lockfile = true` (DynamoDB locking is
  deprecated), GCS, azurerm, or a TACOS. Never local state for shared infrastructure; never commit
  `*.tfstate`.
- Least-privilege state access: CI identity writes, humans read.
- Refactor with `moved`, `import`, and `removed` blocks instead of manual `state mv`/`import`/`rm`.

## Change workflow

1. `fmt -check`, `validate`, `tflint`, and a security scan (Trivy config or Checkov) on every PR.
2. `plan` in CI with the plan and an Infracost cost diff posted to the PR; reviewers read both.
3. `apply` only from CI, using the saved plan artifact from the approved PR.
4. Production applies require manual approval; destroy operations require an explicit extra gate.

- Protect critical resources with `lifecycle { prevent_destroy = true }`.
- Scheduled drift detection (`plan -detailed-exitcode`) alerts on out-of-band changes.

## Secrets and ephemeral values

- A `data` source that reads a secret writes the value into state and plan. Use `ephemeral`
  resources instead and pass the value only to write-only arguments (`*_wo`, bumped via
  `*_wo_version`), provider blocks, or other ephemeral contexts.
- Prefer letting the service own the secret (for example RDS `manage_master_user_password`,
  Cloud SQL IAM auth) over passing any password through IaC.
- Mark variables that carry credentials `ephemeral = true`; they cannot be saved in plan files,
  so supply them at both plan and apply time.

```hcl
ephemeral "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id                = aws_secretsmanager_secret.db.id
  secret_string_wo         = ephemeral.random_password.db.result
  secret_string_wo_version = 1
}
```

Write-only support is per resource argument and per provider version — check the registry docs
before relying on it.

## Security

- CI authenticates with OIDC federation, never long-lived keys.
- No secrets in `.tfvars`, code, or outputs; OpenTofu roots enable state encryption.
- Tag every resource (`owner`, `env`, `cost-center`, `managed-by = terraform`) via provider
  `default_tags` where supported.

## Cost

- Infracost in CI: `infracost breakdown` on the base branch, `infracost diff` on the PR, comment
  the delta; set a threshold that requires an extra approval for large increases.
- Tag-based cost allocation plus budgets and anomaly alerts in each cloud account.

## Testing

- Native tests (`*.tftest.hcl`) for every module: `command = plan` assertions for logic and
  validation; `apply`-mode tests in an ephemeral sandbox account for critical modules.
- Use `mock_provider` (Terraform 1.7+, OpenTofu 1.8+) with `override_resource`/`override_data`
  to test module wiring without cloud credentials.
- Policy-as-code (OPA/Conftest or Sentinel) for organization rules such as "no public buckets".

_Versions verified September 2026._
