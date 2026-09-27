---
name: devops-terraform
description: Infrastructure-as-code standards for Terraform and OpenTofu — module design, remote state with locking, environment separation, plan review, policy and security scanning (tflint, Trivy/Checkov), native tests, and drift detection. Use when writing or reviewing .tf/.tofu files, modules, or IaC pipelines; cloud-specific resource guidance is in devops-aws, devops-gcp, and devops-onprem.
globs:
  - "**/*.tf"
  - "**/*.tofu"
  - "**/*.tfvars"
  - "**/*.tftest.hcl"
  - "**/.terraform.lock.hcl"
  - "**/.tflint.hcl"
  - "**/terragrunt.hcl"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# Terraform / OpenTofu Standards

## Tool choice

- Pick Terraform or OpenTofu per repository and pin it (`required_version` plus a version file
  such as `.terraform-version` or `.opentofu-version`). Do not mix CLIs against one state.
- OpenTofu is preferred when state encryption at rest or an open-source license is a requirement.

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
  `validation`; `output` blocks with descriptions; mark secrets `sensitive = true`.
- Pin provider versions with `~>` and commit `.terraform.lock.hcl`.
- Reference shared modules by tag or registry version, never by a moving branch.

## State

- Remote backend with locking and encryption (S3 with native lockfile or DynamoDB, GCS, azurerm,
  or a TACOS). Never local state for shared infrastructure; never commit `*.tfstate`.
- Least-privilege state access: CI identity writes, humans read.
- Refactor with `moved` blocks and `import` blocks instead of manual `state mv` / `import` commands.

## Change workflow

1. `fmt -check`, `validate`, `tflint`, and a security scan (Trivy config or Checkov) on every PR.
2. `plan` in CI with the plan posted to the PR; reviewers read the plan, not only the code.
3. `apply` only from CI, using the saved plan artifact from the approved PR.
4. Production applies require manual approval; destroy operations require an explicit extra gate.

- Protect critical resources with `lifecycle { prevent_destroy = true }`.
- Scheduled drift detection (`plan -detailed-exitcode`) alerts on out-of-band changes.

## Security

- CI authenticates with OIDC federation, never long-lived keys.
- No secrets in `.tfvars` or code; read them from a secret manager data source at apply time,
  or generate them and store them in the manager.
- Tag every resource (`owner`, `env`, `cost-center`, `managed-by = terraform`) via provider
  `default_tags` where supported.

## Testing

- Native tests (`*.tftest.hcl`) for modules: `plan`-mode assertions for logic, `apply`-mode tests
  in an ephemeral sandbox account for critical modules.
- Policy-as-code (OPA/Conftest or Sentinel) for organization rules such as "no public buckets".
