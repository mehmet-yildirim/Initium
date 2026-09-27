# Organizations, SCPs, Identity Center and AWS Backup

Manage these from a dedicated `org` root module that runs with a role in the management account
(or the delegated administrator account where the service supports it).

## Baseline SCP

```hcl
data "aws_iam_policy_document" "baseline_guardrails" {
  statement {
    sid       = "DenyLeavingOrganization"
    effect    = "Deny"
    actions   = ["organizations:LeaveOrganization"]
    resources = ["*"]
  }

  statement {
    sid    = "ProtectSecurityServices"
    effect = "Deny"
    actions = [
      "cloudtrail:StopLogging",
      "cloudtrail:DeleteTrail",
      "config:StopConfigurationRecorder",
      "config:DeleteConfigurationRecorder",
      "guardduty:DeleteDetector",
      "guardduty:DisassociateFromAdministratorAccount",
      "securityhub:DisableSecurityHub",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "DenyRootUser"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:root"]
    }
  }
}

resource "aws_organizations_policy" "baseline_guardrails" {
  name    = "baseline-guardrails"
  type    = "SERVICE_CONTROL_POLICY"
  content = data.aws_iam_policy_document.baseline_guardrails.json
}

resource "aws_organizations_policy_attachment" "workloads" {
  policy_id = aws_organizations_policy.baseline_guardrails.id
  target_id = var.workloads_ou_id
}
```

- Add a region-restriction SCP (`aws:RequestedRegion` with `NotAction` for global services) once
  the list of global services you use is known; test it in a sandbox OU first.
- SCPs never grant permissions; they cap what IAM policies in member accounts can grant.
- Keep SCPs in version control, apply through CI, and attach to OUs — not individual accounts.

## IAM Identity Center

- Connect the IdP (Entra ID, Okta, Google) with SCIM provisioning; assign permission sets to
  groups, never to individual users.
- Permission sets per job function (`ReadOnly`, `Developer`, `PlatformAdmin`), session duration
  ≤ 8 h for admin sets, and `AdministratorAccess` only for a small break-glass group.
- Terraform: `aws_ssoadmin_permission_set`, `aws_ssoadmin_managed_policy_attachment` /
  `aws_ssoadmin_permission_set_inline_policy`, and `aws_ssoadmin_account_assignment` with
  `principal_type = "GROUP"`.
- Developers use `aws sso login` / `aws configure sso` profiles locally; no access keys.

## AWS Backup (tag-based, locked vault)

```hcl
resource "aws_backup_vault" "main" {
  name        = "${var.environment}-vault"
  kms_key_arn = aws_kms_key.backup.arn
}

resource "aws_backup_vault_lock_configuration" "main" {
  backup_vault_name   = aws_backup_vault.main.name
  min_retention_days  = 7
  max_retention_days  = 365
  changeable_for_days = 3 # after this grace period the lock becomes immutable (compliance mode)
}

resource "aws_backup_plan" "daily" {
  name = "${var.environment}-daily"

  rule {
    rule_name         = "daily-35d"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 3 * * ? *)"

    lifecycle {
      delete_after = 35
    }

    copy_action {
      destination_vault_arn = var.backup_account_vault_arn

      lifecycle {
        delete_after = 90
      }
    }
  }
}

resource "aws_backup_selection" "tagged" {
  name         = "tagged-daily"
  plan_id      = aws_backup_plan.daily.id
  iam_role_arn = aws_iam_role.backup.arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "backup"
    value = "daily"
  }
}
```

- The copy destination lives in a separate backup account (optionally a logically air-gapped
  vault) and a second region for DR.
- Use backup policies in AWS Organizations to enforce plans across accounts at scale.
- Run restore tests (AWS Backup restore testing) on a schedule and record RTO/RPO.
