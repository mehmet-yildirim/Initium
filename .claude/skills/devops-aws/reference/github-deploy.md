# GitHub Actions → AWS (OIDC) and ECS deploy

## OIDC provider and deploy role (one per account/environment)

```hcl
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # No thumbprint_list: IAM validates GitHub's certificate against its trusted CA library.
}

data "aws_iam_policy_document" "github_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:environment:${var.environment}"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name                 = "github-deploy-${var.environment}"
  assume_role_policy   = data.aws_iam_policy_document.github_trust.json
  max_session_duration = 3600
}
```

The job must declare `environment: <env>` so the token's `sub` matches. Protect the GitHub
environment with required reviewers and a deployment branch/tag rule. If the organization has
customized the OIDC subject template, match the exact `sub` your workflows emit.

## Deploy permissions (least privilege)

```hcl
resource "aws_iam_role_policy" "github_deploy" {
  role = aws_iam_role.github_deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "EcrPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
        ]
        Resource = aws_ecr_repository.app.arn
      },
      {
        Sid      = "TaskDefinitions"
        Effect   = "Allow"
        Action   = ["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"]
        Resource = "*" # these actions do not support resource-level permissions
      },
      {
        Sid      = "PassTaskRoles"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = [aws_iam_role.ecs_task.arn, aws_iam_role.ecs_execution.arn]
        Condition = {
          StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" }
        }
      },
      {
        Sid      = "UpdateService"
        Effect   = "Allow"
        Action   = ["ecs:UpdateService", "ecs:DescribeServices"]
        Resource = aws_ecs_service.app.id # the service ARN
      },
    ]
  })
}
```

## Workflow: build once, deploy by digest

Third-party actions are pinned to full commit SHAs (tag in the trailing comment); let
Dependabot/Renovate bump them.

```yaml
# .github/workflows/cd-aws.yml
name: Deploy (AWS ECS)

on:
  push:
    tags: ["v*"]

permissions:
  contents: read

concurrency:
  group: deploy-production
  cancel-in-progress: false

jobs:
  deploy:
    runs-on: ubuntu-24.04
    environment: production
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@e1253824e5c10ff9df46874f81ed3ec929e19cfd # v6.3.0
        with:
          role-to-assume: ${{ vars.AWS_DEPLOY_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}

      - name: Log in to ECR
        id: ecr
        uses: aws-actions/amazon-ecr-login@03f1aad4c6c7ffd436567f42f9384779290529bd # v2.1.7

      - uses: docker/setup-buildx-action@f87e5991a6d7451dcb8d9637bfbc97413f497069 # v4.4.1

      - name: Build and push (ARM64)
        id: build
        uses: docker/build-push-action@c3c9e263c25d99ce0380d002d59b67737d91b0dc # v7.4.0
        with:
          context: .
          platforms: linux/arm64
          push: true
          provenance: mode=max
          sbom: true
          tags: ${{ steps.ecr.outputs.registry }}/${{ vars.ECR_REPOSITORY }}:${{ github.ref_name }}

      - name: Render task definition with the new image digest
        id: render
        uses: aws-actions/amazon-ecs-render-task-definition@138c24f321fdbdf7edee4a685519d253cae2cdea # v1.9.0
        with:
          task-definition-family: ${{ vars.ECS_TASK_FAMILY }}
          container-name: ${{ vars.ECS_CONTAINER_NAME }}
          image: ${{ steps.ecr.outputs.registry }}/${{ vars.ECR_REPOSITORY }}@${{ steps.build.outputs.digest }}

      - name: Register task definition and update service
        uses: aws-actions/amazon-ecs-deploy-task-definition@c465972ecbd160473f22e683363b422a5412a3de # v2.6.3
        with:
          task-definition: ${{ steps.render.outputs.task-definition }}
          cluster: ${{ vars.ECS_CLUSTER }}
          service: ${{ vars.ECS_SERVICE }}
          wait-for-service-stability: true
```

`wait-for-service-stability` fails the job if the circuit breaker rolls back. Building on an ARM64
runner (`ubuntu-24.04-arm`) avoids QEMU emulation for large images. In multi-environment setups,
build in a separate job and promote the same digest through environment-gated deploy jobs.
